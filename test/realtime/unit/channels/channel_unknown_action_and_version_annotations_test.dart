import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Regression test for the merged integration branch only — it exists on
/// `netglade/chat-v0.2.0`, not on either patch branch it covers.
///
/// Patch A (message `version`/`annotations`, PATCHES.md row A) and patch E
/// (unknown wire-enum handling, PATCHES.md row E) both touch
/// `RealtimeChannelImpl._handleMessage`'s per-message decode loop, at
/// distinct anchors, so git merges them without a conflict. A clean
/// textual merge proves nothing about behaviour: this test sends ONE
/// MESSAGE batch containing both an unknown-action entry and a valid
/// entry carrying `version` and `annotations`, requiring both patches'
/// behaviour from the same decode pass:
///
///   - the unknown-action entry is dropped and logged at INFO (patch E),
///   - the valid entry, decoded from that same batch, still carries
///     non-null `version` and `annotations` (patch A).
///
/// Neither patch branch passes this alone. Patch A alone: without patch
/// E, `MessageAction.fromInt` throws `ArgumentError` on action 99 instead
/// of returning null, so the unknown entry is never gracefully dropped
/// and the batch never reaches the valid entry. Patch E alone: without
/// patch A, `_handleMessage` never populates `version` or `annotations`
/// on the delivered `Message` at all, so those fields stay null.
void main() {
  test(
      'a batch with an unknown action and a versioned/annotated message: '
      'the unknown one is dropped and logged, the valid one keeps its '
      'version and annotations', () async {
    final channelName = testChannelName('merged-unknown-action-annotations');

    late final MockWebSocketClient mockWs;
    mockWs = MockWebSocketClient(
      onConnectionAttempt: (conn) {
        conn.respondWithSuccess(ProtocolMessageHelpers.connected());
      },
      onMessageFromClient: (msg) {
        if (msg.action == ProtocolAction.attach) {
          mockWs.activeConnection!.sendToClient(
            ProtocolMessageHelpers.attached(channel: channelName),
          );
        }
      },
    );

    final ignoreLogs = <Map<String, dynamic>>[];
    final client = RealtimeClient.forTesting(
      options: ClientOptions(
        key: 'appId.keyId:keySecret',
        autoConnect: false,
        logLevel: LogLevel.info,
        logHandler: (level, message, context) {
          if (level == LogLevel.info &&
              message == 'Ignoring message with unrecognised action') {
            ignoreLogs.add(context);
          }
        },
      ),
      webSocketClient: mockWs,
    );

    final channel = client.channels.get(
      channelName,
      const RealtimeChannelOptions(attachOnSubscribe: false),
    );

    final received = <Message>[];
    channel.subscribe(received.add);

    client.connect();
    await client.connection
        .on()
        .firstWhere((change) => change.current == ConnectionState.connected)
        .timeout(const Duration(seconds: 5));
    await channel.attach();

    mockWs.activeConnection!.sendToClient(
      ProtocolMessage(
        action: ProtocolAction.message,
        channel: channelName,
        id: 'proto:0',
        messages: [
          <String, dynamic>{
            'name': 'unknown',
            'data': 'dropped',
            'serial': 'serial-unknown',
            'action': 99,
          },
          <String, dynamic>{
            'name': 'known',
            'data': 'delivered',
            'serial': '01826232498871-001@abcdefghij:001',
            'timestamp': 1700000000000,
            'action': 0,
            'version': {
              'serial': '01826232498999-002@abcdefghij:001',
              'timestamp': 1700000005000,
              'clientId': 'alice',
            },
            'annotations': {
              'summary': {
                'reaction:distinct.v1': {
                  'like': {
                    'total': 1,
                    'clientIds': ['alice'],
                  },
                },
              },
            },
          },
        ],
      ),
    );

    // Patch E: the unknown-action entry is dropped, not thrown, and the
    // batch continues to the valid entry.
    expect(received, hasLength(1));
    expect(received[0].name, equals('known'));
    expect(channel.state, equals(ChannelState.attached));
    expect(client.connection.state, equals(ConnectionState.connected));
    expect(ignoreLogs, hasLength(1));
    expect(ignoreLogs.single['action'], equals(99));

    // Patch A: the valid entry, decoded from the SAME batch, still
    // carries its version and annotations.
    expect(received[0].version, isNotNull);
    expect(
      received[0].version!.serial,
      equals('01826232498999-002@abcdefghij:001'),
    );
    expect(received[0].version!.timestamp, equals(1700000005000));
    expect(received[0].annotations, isNotNull);
    final summary = received[0].annotations!.summary;
    expect(summary.keys, contains('reaction:distinct.v1'));

    mockWs.dispose();
  });
}
