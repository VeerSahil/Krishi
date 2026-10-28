import 'package:flutter_test/flutter_test.dart';
import 'package:krishi/services/offline_team.dart';
import 'package:krishi/services/private_store.dart';
import 'package:krishi/services/team_api.dart';
import 'package:krishi/services/backend_client.dart';
import 'package:krishi/models/field_visit.dart';

class MemoryStore implements LocalStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

class NetworkTeam extends TeamRepository {
  bool online = true;
  bool conflict = false;
  final submitted = <Map<String, dynamic>>[];
  void check() {
    if (!online) throw const ApiException('offline', connectionFailure: true);
  }

  @override
  Future<VisitPage> visits({String? status, String? cursor}) async {
    check();
    return VisitPage([await visit('v1')], null);
  }

  @override
  Future<FieldVisit> visit(String id) async {
    check();
    return FieldVisit.fromJson(
        {'surveyId': id, 'status': 'approved', 'farmName': 'Test farm'});
  }

  @override
  Future<void> start(String id) async {
    check();
  }

  @override
  Future<void> submit(String id, Map<String, dynamic> readings) async {
    submitted.add(readings);
    check();
    if (conflict) throw const ApiException('Visit cancelled', statusCode: 409);
  }
}

void main() {
  test(
      'offline restart restores visit, partial draft and immutable queued report',
      () async {
    final store = MemoryStore();
    final remote = NetworkTeam();
    var repo =
        OfflineTeamRepository(remote: remote, uid: 'alice', store: store);
    await repo.visits();
    await repo.saveDraft('v1', {'moisture': '43'});
    remote.online = false;
    repo = OfflineTeamRepository(remote: remote, uid: 'alice', store: store);
    expect((await repo.visits()).visits.single.farmName, 'Test farm');
    expect(repo.offline, isTrue);
    expect((await repo.draft('v1'))!['moisture'], '43');
    await repo.submit('v1', {'moisture': 43});
    final originalId = repo.pending.single['payload']['clientSubmissionId'];
    repo = OfflineTeamRepository(remote: remote, uid: 'alice', store: store);
    await repo.sync();
    expect(repo.pending.single['payload']['clientSubmissionId'], originalId);
    remote.online = true;
    await repo.sync();
    expect(repo.pending, isEmpty);
    expect(remote.submitted.last['clientSubmissionId'], originalId);
    expect(await repo.draft('v1'), isNull);
  });
  test('accounts cannot open each others cached visits or drafts', () async {
    final store = MemoryStore();
    final remote = NetworkTeam();
    final alice =
        OfflineTeamRepository(remote: remote, uid: 'alice', store: store);
    await alice.visits();
    await alice.saveDraft('v1', {'moisture': '99'});
    remote.online = false;
    final bob = OfflineTeamRepository(remote: remote, uid: 'bob', store: store);
    await expectLater(bob.visits(), throwsA(isA<ApiException>()));
    expect(await bob.draft('v1'), isNull);
    expect(bob.pending, isEmpty);
  });
  test('server conflict keeps saved report and concurrent sync sends once',
      () async {
    final remote = NetworkTeam()..conflict = true;
    final repo = OfflineTeamRepository(
        remote: remote, uid: 'alice', store: MemoryStore());
    await repo.submit('v1', {'moisture': 43});
    expect(repo.pending.length, 1);
    expect(repo.syncError, contains('cancelled'));
    await expectLater(
        repo.submit('v1', {'moisture': 99}), throwsA(isA<ApiException>()));
    remote.conflict = false;
    final before = remote.submitted.length;
    await Future.wait(
        [repo.sync(retryBlocked: true), repo.sync(retryBlocked: true)]);
    expect(remote.submitted.length, before + 1);
    expect(repo.pending, isEmpty);
  });
}
