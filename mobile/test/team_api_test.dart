import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:krishi/services/backend_client.dart';
import 'package:krishi/services/team_api.dart';

void main() {
  test('assigned visit filtering and pagination use authenticated GET requests',
      () async {
    final backend = BackendClient(
        tokenProvider: (_) async => 'team-token',
        baseUrl: 'https://example.invalid',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.headers['Authorization'], 'Bearer team-token');
          expect(request.url.path, '/team/visits');
          expect(request.url.queryParameters,
              {'limit': '20', 'status': 'approved', 'cursor': 'page 2'});
          return http.Response(
              jsonEncode({
                'visits': [
                  {
                    'surveyId': 'visit-1',
                    'status': 'approved',
                    'farmName': 'Pune farm'
                  },
                ],
                'nextCursor': 'page-3'
              }),
              200);
        }));
    final page = await TeamApi(backend: backend)
        .visits(status: 'approved', cursor: 'page 2');
    expect(page.visits.single.canRecord, isTrue);
    expect(page.nextCursor, 'page-3');
    backend.close();
  });

  test('GET refreshes an expired token once', () async {
    var calls = 0;
    final refreshes = <bool>[];
    final backend = BackendClient(tokenProvider: (refresh) async {
      refreshes.add(refresh);
      return 'team-token';
    }, client: MockClient((request) async {
      calls++;
      return calls == 1
          ? http.Response('{"detail":"expired"}', 401)
          : http.Response('{"surveyId":"visit-1","status":"in_progress"}', 200);
    }));
    final visit = await TeamApi(backend: backend).visit('visit-1');
    expect(visit.status, 'in_progress');
    expect(refreshes, [false, true]);
    backend.close();
  });

  test(
      'visit start and report submission preserve the backend reading contract',
      () async {
    final requests = <http.Request>[];
    final backend = BackendClient(
        tokenProvider: (_) async => 'team-token',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }));
    final team = TeamApi(backend: backend);
    await team.start('visit-1');
    final readings = {
      'moisture': 45.0,
      'temperature': 28.0,
      'nitrogen': 400.0,
      'phosphorus': 200.0,
      'potassium': 150.0,
      'notes': 'Measured at farm'
    };
    await team.submit('visit-1', readings);
    expect(requests.map((r) => r.method), ['POST', 'POST']);
    expect(requests.first.url.path, '/team/visits/visit-1/start');
    expect(requests.last.url.path, '/team/visits/visit-1/readings');
    expect(jsonDecode(requests.last.body), readings);
    backend.close();
  });

  test('a conflicting report is surfaced without repeating the submission',
      () async {
    var calls = 0;
    final backend = BackendClient(
        tokenProvider: (_) async => 'team-token',
        client: MockClient((request) async {
          calls++;
          return http.Response(
              '{"detail":"This visit changed. Refresh it."}', 409);
        }));
    await expectLater(
        TeamApi(backend: backend).submit('visit-1', {}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)));
    expect(calls, 1);
    backend.close();
  });
}
