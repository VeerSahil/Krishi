import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/field_visit.dart';
import 'team_api.dart';
import 'backend_client.dart';
import 'private_store.dart';

/// Account-scoped, encrypted Android storage. Server remains authoritative.
class OfflineTeamRepository extends ChangeNotifier implements TeamRepository {
  final TeamRepository remote;
  final LocalStore store;
  final String uid;
  Map<String, dynamic> _state = {};
  Future<void> _tail = Future.value();
  bool offline = false;
  bool syncing = false;
  String? syncError;
  OfflineTeamRepository(
      {required this.remote, required this.uid, LocalStore? store})
      : store = store ?? PrivateStore();
  String get _key => 'team_$uid';
  List<Map<String, dynamic>> get pending =>
      List<Map<String, dynamic>>.from((_state['queue'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e)));
  Future<T> _locked<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  Future<void> _read() async {
    final raw = await store.read(_key);
    _state = raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> _save() async {
    await store.write(_key, jsonEncode(_state));
    notifyListeners();
  }

  bool _network(Object e) =>
      (e is ApiException &&
          (e.connectionFailure ||
              (e.statusCode != null && e.statusCode! >= 500))) ||
      (e is FirebaseAuthException && e.code == 'network-request-failed');
  @override
  Future<VisitPage> visits({String? status, String? cursor}) =>
      _locked(() async {
        await _read();
        final key = '${status ?? "all"}:${cursor ?? "first"}';
        try {
          final page = await remote.visits(status: status, cursor: cursor);
          offline = false;
          final pages = Map<String, dynamic>.from(_state['pages'] ?? {});
          pages[key] = {
            'visits': page.visits.map((v) => v.data).toList(),
            'next': page.nextCursor
          };
          _state['pages'] = pages;
          final details = Map<String, dynamic>.from(_state['details'] ?? {});
          for (final v in page.visits) {
            details[v.id] = v.data;
          }
          _state['details'] = details;
          await _save();
          return page;
        } catch (e) {
          if (!_network(e)) rethrow;
          final saved = (_state['pages'] as Map?)?[key];
          if (saved == null) rethrow;
          offline = true;
          notifyListeners();
          return VisitPage(
              (saved['visits'] as List)
                  .map((v) => FieldVisit.fromJson(Map<String, dynamic>.from(v)))
                  .toList(),
              saved['next'] as String?);
        }
      });
  @override
  Future<FieldVisit> visit(String id) => _locked(() async {
        await _read();
        try {
          final value = await remote.visit(id);
          offline = false;
          final details = Map<String, dynamic>.from(_state['details'] ?? {});
          details[id] = value.data;
          _state['details'] = details;
          await _save();
          return value;
        } catch (e) {
          final cached = (_state['details'] as Map?)?[id];
          if (!_network(e) || cached == null) rethrow;
          offline = true;
          notifyListeners();
          return FieldVisit.fromJson(Map<String, dynamic>.from(cached));
        }
      });
  Future<Map<String, dynamic>?> draft(String id) => _locked(() async {
        await _read();
        final value = (_state['drafts'] as Map?)?[id];
        return value == null ? null : Map<String, dynamic>.from(value);
      });
  Future<void> saveDraft(String id, Map<String, dynamic> fields) =>
      _locked(() async {
        await _read();
        final drafts = Map<String, dynamic>.from(_state['drafts'] ?? {});
        drafts[id] = fields;
        _state['drafts'] = drafts;
        await _save();
      });
  @override
  Future<void> start(String id) => remote.start(id);
  @override
  Future<void> submit(String id, Map<String, dynamic> readings) async {
    await _locked(() async {
      await _read();
      final queue = pending;
      if (queue.any((e) => e['visitId'] == id)) {
        throw const ApiException(
            'A saved report is already waiting to sync. Sync it before recording another report.');
      }
      final random = Random.secure();
      final token = List.generate(
              24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      queue.add({
        'visitId': id,
        'payload': {...readings, 'clientSubmissionId': token},
        'savedAt': DateTime.now().toUtc().toIso8601String()
      });
      _state['queue'] = queue;
      final drafts = Map<String, dynamic>.from(_state['drafts'] ?? {})
        ..remove(id);
      _state['drafts'] = drafts;
      await _save();
    });
    await sync();
  }

  Future<void> discard(String submissionId) => _locked(() async {
        await _read();
        _state['queue'] = pending
            .where((e) => e['payload']['clientSubmissionId'] != submissionId)
            .toList();
        await _save();
      });
  Future<void> sync({bool retryBlocked = false}) async {
    if (syncing) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      await _locked(() async {
        await _read();
        for (final job in pending) {
          if (job['blocked'] == true && !retryBlocked) continue;
          try {
            // Assignment, status and submission identity are checked again on server.
            await remote.submit(
                job['visitId'], Map<String, dynamic>.from(job['payload']));
            _state['queue'] = pending
                .where((e) =>
                    e['payload']['clientSubmissionId'] !=
                    job['payload']['clientSubmissionId'])
                .toList();
            offline = false;
            await _save();
          } catch (e) {
            syncError = e.toString();
            offline = _network(e);
            final blocked = e is ApiException &&
                e.statusCode != null &&
                e.statusCode! < 500;
            _state['queue'] = pending
                .map((value) => value['payload']['clientSubmissionId'] ==
                        job['payload']['clientSubmissionId']
                    ? {...value, 'lastError': e.toString(), 'blocked': blocked}
                    : value)
                .toList();
            await _save();
            // A cancelled visit cannot prevent unrelated visits from syncing.
            if (!blocked) break;
          }
        }
      });
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
