import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';

/// Unit tests for `ErrorInfo.detail` (TI1, TI6), the field that carries Ably
/// Chat's moderation rejection detail for error codes 42211 and 42213
/// (CHA-M3e).
void main() {
  group('TI1, TI6 - ErrorInfo.detail decodes from the wire error object', () {
    test('detail decodes as a map of string keys to string values', () {
      final error = ErrorInfo.fromMap({
        'code': 42211,
        'statusCode': 400,
        'message': 'Message rejected by moderation',
        'detail': {'rejectionReason': 'profanity', 'ruleId': 'r-1'},
      });

      expect(error.code, equals(42211));
      expect(
        error.detail,
        equals({'rejectionReason': 'profanity', 'ruleId': 'r-1'}),
      );
    });

    test('detail round-trips through toMap', () {
      const error = ErrorInfo(
        code: 42213,
        statusCode: 400,
        message: 'Message rejected by moderation',
        detail: {'rejectionReason': 'blocked-term'},
      );

      expect(
        error.toMap()['detail'],
        equals({'rejectionReason': 'blocked-term'}),
      );
      expect(error.toString(), contains('detail='));
    });

    test('TI6 - detail is omitted when absent or empty', () {
      final absent = ErrorInfo.fromMap({'code': 40000, 'statusCode': 400});
      expect(absent.detail, isNull);
      expect(absent.toMap().containsKey('detail'), isFalse);

      final empty = ErrorInfo.fromMap({
        'code': 40000,
        'statusCode': 400,
        'detail': <String, dynamic>{},
      });
      expect(empty.detail, isNull);
      expect(empty.toMap().containsKey('detail'), isFalse);

      const constructedEmpty = ErrorInfo(code: 40000, detail: {});
      expect(constructedEmpty.toMap().containsKey('detail'), isFalse);
      expect(constructedEmpty.toString(), isNot(contains('detail=')));
    });

    test('two errors differing only in detail are not equal', () {
      const a = ErrorInfo(code: 42211, detail: {'rejectionReason': 'a'});
      const b = ErrorInfo(code: 42211, detail: {'rejectionReason': 'b'});
      const c = ErrorInfo(code: 42211, detail: {'rejectionReason': 'a'});

      expect(a, isNot(equals(b)));
      expect(a, equals(c));
      expect(a.hashCode, equals(c.hashCode));
    });
  });

  group('RSC15/TI1 - REST error mapping carries detail', () {
    test('a rejected publish throws an ErrorInfo carrying detail', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(400, {
            'error': {
              'code': 42211,
              'statusCode': 400,
              'message': 'Message rejected by moderation',
              'detail': {'rejectionReason': 'profanity'},
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-error-detail');

      try {
        await channel.publish(name: 'chat.message', data: 'oops');
        fail('Expected AblyException');
      } on AblyException catch (e) {
        expect(e.errorInfo!.code, equals(42211));
        expect(e.errorInfo!.detail, equals({'rejectionReason': 'profanity'}));
      }

      mockHttp.dispose();
    });
  });
}
