// Standalone HTTP-client contract checks; no Flutter engine or network needed.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/services/backend_client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  var passed = 0;
  var calls = 0;
  final requestedRefresh = <bool>[];
  final client = BackendClient(
    tokenProvider: (force) async {
      requestedRefresh.add(force);
      return 'test-token';
    },
    baseUrl: 'https://example.invalid/',
    client: MockClient((request) async {
      check(request.url.toString() == 'https://example.invalid/survey/book', 'URL mismatch');
      check(request.headers['Authorization'] == 'Bearer test-token', 'Missing token');
      check(jsonDecode(request.body)['city'] == 'Pune', 'Missing JSON payload');
      calls++;
      return calls == 1
          ? http.Response('{"detail":"expired"}', 401)
          : http.Response('{"surveyId":"survey-one"}', 200);
    }),
  );
  final booked = await client.post('/survey/book', {'city': 'Pune'});
  check(booked['surveyId'] == 'survey-one', 'Wrong response');
  check(calls == 2 && requestedRefresh.toString() == '[false, true]',
      'Token was not refreshed exactly once');
  passed++;
  client.close();

  final invalid = BackendClient(
    tokenProvider: (_) async => 'token',
    client: MockClient((_) async => http.Response(
        '{"detail":[{"msg":"Moisture must be 0 to 100"}]}', 422)),
  );
  try {
    await invalid.post('/admin/process-survey', {});
    throw StateError('Validation error was accepted');
  } on ApiException catch (error) {
    check(error.statusCode == 422 && error.message.contains('Moisture'), 'Unreadable validation');
    passed++;
  }
  invalid.close();

  final html = BackendClient(
    tokenProvider: (_) async => 'token',
    client: MockClient((_) async => http.Response('<html>Unavailable</html>', 503)),
  );
  try {
    await html.post('/chat', {});
    throw StateError('HTML response was accepted');
  } on ApiException catch (error) {
    check(error.message.contains('unexpected response'), 'HTML error leaked');
    passed++;
  }
  html.close();

  var timeoutCalls = 0;
  final timed = BackendClient(
    tokenProvider: (_) async => 'token',
    timeout: const Duration(milliseconds: 5),
    client: MockClient((_) async {
      timeoutCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{"surveyId":"one"}', 200);
    }),
  );
  try {
    await timed.post('/survey/book', {});
    throw StateError('Timeout was ignored');
  } on ApiException catch (error) {
    check(timeoutCalls == 1 && error.message.contains('Check your surveys'),
        'A timed-out mutation was retried');
    passed++;
  }
  timed.close();

  final signedOut = BackendClient(
    tokenProvider: (_) async => null,
    client: MockClient((_) async => throw StateError('Signed-out request was sent')),
  );
  try {
    await signedOut.post('/survey/book', {});
    throw StateError('Signed-out request succeeded');
  } on ApiException catch (error) {
    check(error.message.contains('sign in'), 'Missing login guidance');
    passed++;
  }
  signedOut.close();
  print('$passed standalone HTTP-client contract checks passed.');
}
