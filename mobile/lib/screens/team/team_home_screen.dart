import '../../services/app_language.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/field_visit.dart';
import '../../services/backend_client.dart';
import '../../services/team_api.dart';
import '../../services/offline_team.dart';
import 'team_visit_screen.dart';

class TeamHomeScreen extends StatefulWidget {
  final TeamRepository repository;
  final VoidCallback onSignOut;
  const TeamHomeScreen(
      {super.key, required this.repository, required this.onSignOut});

  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen>
    with WidgetsBindingObserver {
  List<FieldVisit> _visits = [];
  List<String?> _cursors = [null];
  int _page = 0;
  int _request = 0;
  String? _next;
  String? _status;
  String? _error;
  bool _loading = true;
  bool _showingVisit = false;
  bool _foreground = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.repository is OfflineTeamRepository) {
      (widget.repository as OfflineTeamRepository).addListener(_offlineChanged);
    }
    _load();
    _timer = Timer.periodic(Duration(seconds: 30), (_) {
      if (_foreground && !_loading && !_showingVisit) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_loading && !_showingVisit) _load();
  }

  void _offlineChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.repository is OfflineTeamRepository) {
      (widget.repository as OfflineTeamRepository)
          .removeListener(_offlineChanged);
    }
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 0;
      _cursors = [null];
      _visits = [];
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.repository is OfflineTeamRepository) {
        await (widget.repository as OfflineTeamRepository).sync();
      }
      final result = await widget.repository
          .visits(status: _status, cursor: _cursors[_page]);
      if (!mounted || request != _request) return;
      setState(() {
        _visits = result.visits;
        _next = result.nextCursor;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      if (error is ApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        widget.onSignOut();
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(FieldVisit visit) async {
    _showingVisit = true;
    final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => TeamVisitScreen(
            visitId: visit.id,
            repository: widget.repository,
            onSessionEnded: widget.onSignOut,
          ),
        ));
    _showingVisit = false;
    if (!mounted) return;
    if (changed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr(
                widget.repository is OfflineTeamRepository &&
                        (widget.repository as OfflineTeamRepository)
                            .pending
                            .isNotEmpty
                    ? 'Report saved on this phone. Waiting to sync.'
                    : 'Report submitted for admin review.',
                context: context))),
      );
    }
    await _load(reset: changed == true);
  }

  Widget _syncPanel(OfflineTeamRepository repo) => Card(
      child: Padding(
          padding: EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(
                repo.offline
                    ? 'Offline: showing saved visits'
                    : 'Offline field notebook',
                context: context)),
            Text(tr('Reports waiting to sync: ${repo.pending.length}',
                context: context)),
            Text(tr(
                'Open assigned visits online before leaving. Save drafts on this phone; sync when connected. Uninstalling clears local reports.',
                context: context)),
            if (repo.syncError != null)
              Text(tr(repo.syncError!, context: context)),
            TextButton.icon(
                onPressed: repo.syncing
                    ? null
                    : () async {
                        await repo.sync(retryBlocked: true);
                        await _load();
                      },
                icon: Icon(Icons.sync),
                label: Text(tr(repo.syncing ? 'Syncing' : 'Sync saved reports',
                    context: context))),
            for (final job in repo.pending)
              ListTile(
                title: Text(tr(job['visitId'], context: context)),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job['savedAt']),
                      if (job['lastError'] != null)
                        Text(tr(job['lastError'], context: context))
                    ]),
                trailing: IconButton(
                    icon: Icon(Icons.delete_outline),
                    tooltip: tr('Discard local report', context: context),
                    onPressed: repo.syncing
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                        title: Text(tr('Discard local report?',
                                            context: context)),
                                        content: Text(tr(
                                            'Unsynced readings will be removed from this phone. A report already received by the server will remain there.',
                                            context: context)),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(tr('Cancel',
                                                  context: context))),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: Text(tr('Discard',
                                                  context: context)))
                                        ]));
                            if (confirmed == true)
                              await repo.discard(
                                  job['payload']['clientSubmissionId']);
                          }),
              ),
          ])));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Color(0xFFF6F7F1),
        appBar: AppBar(
          title: Text(tr('Krishi Team', context: context)),
          actions: [
            IconButton(
                tooltip: tr('Refresh visits', context: context),
                onPressed: _loading ? null : _load,
                icon: Icon(Icons.refresh)),
            IconButton(
                tooltip: tr('Sign out', context: context),
                onPressed: widget.onSignOut,
                icon: Icon(Icons.logout)),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _load(),
          child: ListView(
              padding: EdgeInsets.all(20),
              physics: AlwaysScrollableScrollPhysics(),
              children: [
                if (widget.repository is OfflineTeamRepository)
                  _syncPanel(widget.repository as OfflineTeamRepository),
                Text(tr('Your field visits', context: context),
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w600)),
                SizedBox(height: 8),
                Text(tr(
                    'Visit the assigned farm, record the gadget readings and submit your report for admin review.',
                    context: context)),
                SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  value: _status ?? '',
                  decoration: InputDecoration(
                      labelText: tr('Visit status', context: context),
                      border: OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(
                        value: '',
                        child:
                            Text(tr('All assigned visits', context: context))),
                    ...FieldVisit.statusLabels.entries.map((entry) =>
                        DropdownMenuItem(
                            value: entry.key,
                            child: Text(tr(entry.value, context: context)))),
                  ],
                  onChanged: (value) {
                    _status = value == '' ? null : value;
                    _load(reset: true);
                  },
                ),
                SizedBox(height: 20),
                if (_loading) LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Column(children: [
                        Text(tr(_error!, context: context),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                        TextButton(
                            onPressed: _load,
                            child: Text(tr('Try again', context: context))),
                      ])),
                if (!_loading && _error == null && _visits.isEmpty)
                  Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                          tr('No visits in this view. Admin-approved visits appear here once assigned to you.',
                              context: context),
                          textAlign: TextAlign.center)),
                ..._visits.map((visit) => Card(
                      margin: EdgeInsets.only(bottom: 16),
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(tr(visit.statusLabel, context: context),
                                    style: TextStyle(color: Color(0xFF587345))),
                                SizedBox(height: 10),
                                Text(visit.farmName,
                                    style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(height: 8),
                                Text(tr(visit.text('farmerName', 'Farmer'),
                                    context: context)),
                                SizedBox(height: 5),
                                Text(tr(
                                    visit.text(
                                        'farmAddress', visit.text('city')),
                                    context: context)),
                                SizedBox(height: 14),
                                OutlinedButton(
                                    onPressed: () => _open(visit),
                                    child: Text(tr(
                                        visit.canRecord
                                            ? 'Open visit & record readings'
                                            : 'View submitted report',
                                        context: context))),
                              ])),
                    )),
                SizedBox(height: 8),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                          onPressed: _loading || _page == 0
                              ? null
                              : () {
                                  _page--;
                                  _load();
                                },
                          child: Text(tr('Previous', context: context))),
                      Text(tr('Page ${_page + 1}', context: context)),
                      TextButton(
                          onPressed: _loading || _next == null
                              ? null
                              : () {
                                  _cursors = [
                                    ..._cursors.take(_page + 1),
                                    _next
                                  ];
                                  _page++;
                                  _load();
                                },
                          child: Text(tr('Next', context: context))),
                    ]),
              ]),
        ),
      );
}
