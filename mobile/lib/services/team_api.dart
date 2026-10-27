import 'package:firebase_auth/firebase_auth.dart';
import '../models/field_visit.dart';
import 'backend_client.dart';

abstract class TeamRepository {
  Future<VisitPage> visits({String? status, String? cursor});
  Future<FieldVisit> visit(String id);
  Future<void> start(String id);
  Future<void> submit(String id, Map<String, dynamic> readings);
}

class TeamApi implements TeamRepository {
  final BackendClient backend;
  TeamApi({BackendClient? backend})
      : backend = backend ??
            BackendClient(
              tokenProvider: (refresh) async =>
                  FirebaseAuth.instance.currentUser?.getIdToken(refresh),
            );

  @override
  Future<VisitPage> visits({String? status, String? cursor}) async {
    final path = Uri(path: '/team/visits', queryParameters: {
      'limit': '20',
      if (status != null) 'status': status,
      if (cursor != null) 'cursor': cursor,
    });
    final response = await backend.get(path.toString());
    final rows = response['visits'];
    if (rows is! List) {
      throw const ApiException('The server did not return a visit list.');
    }
    return VisitPage(
      rows
          .map((row) => FieldVisit.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      response['nextCursor'] as String?,
    );
  }

  @override
  Future<FieldVisit> visit(String id) async => FieldVisit.fromJson(
      await backend.get('/team/visits/${Uri.encodeComponent(id)}'));

  @override
  Future<void> start(String id) async {
    await backend.post('/team/visits/${Uri.encodeComponent(id)}/start', {});
  }

  @override
  Future<void> submit(String id, Map<String, dynamic> readings) async {
    await backend.post(
        '/team/visits/${Uri.encodeComponent(id)}/readings', readings);
  }
}
