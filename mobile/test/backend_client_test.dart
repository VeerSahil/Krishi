import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:krishi/services/backend_client.dart';

void main() {
  test('survey request sends a Firebase token and JSON to the configured URL',
      () async {
    final client = BackendClient(
      tokenProvider: (_) async => 'test-token',
      baseUrl: 'https://example.invalid/',
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.invalid/survey/book');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(jsonDecode(request.body)['city'], 'Pune');
        return http.Response('{"surveyId":"one"}', 200);
      }),
    );
    expect((await client.post('/survey/book', {'city': 'Pune'}))['surveyId'],
        'one');
    client.close();
  });

  test('expired token is refreshed once', () async {
    var calls = 0;
    final refresh = <bool>[];
    final client = BackendClient(
      tokenProvider: (force) async {
        refresh.add(force);
        return 'token';
      },
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('{"detail":"expired"}', 401)
            : http.Response('{"response":"Ready"}', 200);
      }),
    );
    expect((await client.post('/chat', {'message': 'Hello'}))['response'],
        'Ready');
    expect(refresh, [false, true]);
    client.close();
  });

  test('validation errors become readable messages', () async {
    final client = BackendClient(
      tokenProvider: (_) async => 'token',
      client: MockClient((_) async => http.Response(
          '{"detail":[{"msg":"Moisture must be 0 to 100"}]}', 422)),
    );
    await expectLater(
        client.post('/admin/process-survey', {}),
        throwsA(isA<ApiException>().having(
            (error) => error.message, 'message', contains('Moisture'))));
    client.close();
  });

  test('HTML and network failures have readable messages', () async {
    final client = BackendClient(
      tokenProvider: (_) async => 'token',
      client: MockClient(
          (_) async => http.Response('<html>Unavailable</html>', 503)),
    );
    await expectLater(client.post('/chat', {}), throwsA(isA<ApiException>()));
    client.close();
  });

  test('timed out survey request is not retried', () async {
    var calls = 0;
    final client = BackendClient(
      tokenProvider: (_) async => 'token',
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('{"surveyId":"one"}', 200);
      }),
    );
    await expectLater(
        client.post('/survey/book', {}),
        throwsA(isA<ApiException>().having((error) => error.message, 'message',
            contains('Check your surveys'))));
    expect(calls, 1);
    client.close();
  });
}
