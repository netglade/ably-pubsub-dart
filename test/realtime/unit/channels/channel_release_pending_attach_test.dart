import 'dart:async';

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit test for the interaction between patch B (`attach()`'s connection
/// wait) and patch C (`release()`/`dispose()`): only makes sense, and only
/// exercises the defect, with both patches present, so it lives on the
/// integration branch rather than on either patch branch (see NOTICE and
/// PATCHES.md).
void main() {
  group('RTS4a, RTL4b - release() during a pending attach()', () {
    test(
        'settles the pending attach() with 90001 instead of hanging, and '
        'sends no ATTACH once the connection later connects', () async {
      final channelName = testChannelName('RTS4a-RTL4b-release-pending-attach');
      final attachedChannels = <String>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Open the socket but withhold the CONNECTED protocol message
          // until the test sends it below, leaving attach()'s RTL4i wait
          // (patch B) pending.
          conn.respondWithSilence();
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachedChannels.add(msg.channel!);
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      // RTL4i: attach() while INITIALIZED implicitly starts connect(), then
      // waits, with no timeout of its own, for the connection to settle.
      final attachFuture = channel.attach();

      await _pumpEventQueue();
      expect(channel.state, equals(ChannelState.attaching));
      expect(client.connection.state, equals(ConnectionState.connecting));

      // B×C: release() while that attach() is still pending. Before this
      // fix, detach()'s RTL5l path transitioned straight to DETACHED
      // without failing the pending attach completer, and dispose() then
      // closed the state-change controller out from under it, so the
      // attach() above never settled.
      await client.channels.release(channelName);

      await expectLater(
        attachFuture.timeout(const Duration(seconds: 3)),
        throwsA(
          isA<AblyException>()
              .having((e) => e.errorInfo?.code, 'errorInfo.code', 90001),
        ),
      );

      // The connection now connects. Before this fix, the released
      // channel's attach() fell through to _sendAttachMessage(), putting a
      // spurious ATTACH for a released, disposed channel on the wire.
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.connected(),
      );
      await _awaitConnectionState(client.connection, ConnectionState.connected);
      await _pumpEventQueue();

      expect(attachedChannels, isNot(contains(channelName)));

      mockWs.dispose();
    });
  });
}

/// Waits for connection to reach the specified state.
Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState) return;
  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

/// Pumps the event queue to allow async operations to complete.
Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}
