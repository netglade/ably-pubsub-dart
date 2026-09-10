import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RTF1: an unrecognised wire enum value must be ignored
/// with a log, never thrown, because the throw happens inside the
/// transport handler before delivery and so cannot be caught by callers.
void main() {
  group('RTF1 - wire enum decoders return null for unknown values', () {
    test('MessageAction.fromInt returns null instead of throwing', () {
      expect(
        MessageActionExtension.fromInt(0),
        equals(MessageAction.messageCreate),
      );
      expect(MessageActionExtension.fromInt(99), isNull);
    });

    test('AnnotationAction.fromInt returns null instead of throwing', () {
      expect(
        AnnotationActionExtension.fromInt(0),
        equals(AnnotationAction.annotationCreate),
      );
      expect(AnnotationActionExtension.fromInt(99), isNull);
    });

    test('PresenceAction.fromInt returns null instead of throwing', () {
      expect(PresenceActionExtension.fromInt(2), equals(PresenceAction.enter));
      expect(PresenceActionExtension.fromInt(99), isNull);
      expect(PresenceActionExtension.fromAblyString('teleported'), isNull);
    });

    test('ProtocolAction.fromInt returns null instead of throwing', () {
      expect(
        ProtocolActionExtension.fromInt(15),
        equals(ProtocolAction.message),
      );
      expect(ProtocolActionExtension.fromInt(254), isNull);
    });

    test('ProtocolMessage.fromJson tolerates an unknown action', () {
      final pm = ProtocolMessage.fromJson({
        'action': 254,
        'channel': 'test-RTF1',
      });
      expect(pm.action, isNull);
      expect(pm.channel, equals('test-RTF1'));
    });
  });

  group('RTF1 - unknown message action is neither thrown nor delivered', () {
    test('the message is dropped and the batch continues', () async {
      final channelName = testChannelName('RTF1-msg-action');

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

      final received = <Message>[];
      channel.subscribe(received.add);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);
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
              'serial': 'serial-known',
              'action': 0,
            },
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].name, equals('known'));
      expect(channel.state, equals(ChannelState.attached));
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTF1 - unknown presence action is neither thrown nor delivered', () {
    test('the presence member is dropped and the channel stays ATTACHED',
        () async {
      final channelName = testChannelName('RTF1-presence-action');

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

      final received = <PresenceMessage>[];
      channel.presence.subscribe(received.add);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);
      await channel.attach();

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          id: 'proto:0',
          connectionId: 'c1',
          presence: [
            <String, dynamic>{
              'action': 99,
              'clientId': 'alice',
              'connectionId': 'c1',
              'id': 'c1:0:0',
            },
          ],
        ),
      );

      expect(received, isEmpty);
      expect(channel.state, equals(ChannelState.attached));
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTF1 - unknown annotation action is neither thrown nor delivered', () {
    test('the unknown annotation is dropped and a known one is delivered',
        () async {
      final channelName = testChannelName('RTF1-annotation-action');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: ChannelMode.annotationSubscribe.flagBit,
              ),
            );
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
        const RealtimeChannelOptions(
          attachOnSubscribe: false,
          modes: [ChannelMode.annotationSubscribe],
        ),
      );

      final received = <Annotation>[];
      channel.annotations.subscribe(received.add);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);
      await channel.attach();

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.annotation,
          channel: channelName,
          id: 'proto:0',
          annotations: [
            <String, dynamic>{
              'action': 99,
              'type': 'reaction:distinct.v1',
              'name': 'like',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-1',
            },
            <String, dynamic>{
              'action': 0,
              'type': 'reaction:distinct.v1',
              'name': 'love',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-2',
            },
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].serial, equals('ann-serial-2'));
      expect(received[0].name, equals('love'));
      expect(channel.state, equals(ChannelState.attached));
      expect(client.connection.state, equals(ConnectionState.connected));

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
