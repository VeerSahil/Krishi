import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/field_visit.dart';
import '../../services/backend_client.dart';
import '../../services/team_api.dart';
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
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && !_loading && !_showingVisit) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_loading && !_showingVisit) _load();
  }

  @override
  void dispose() {
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
        const SnackBar(content: Text('Report submitted for admin review.')),
      );
    }
    await _load(reset: changed == true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF6F7F1),
        appBar: AppBar(
          title: const Text('Krishi Team'),
          actions: [
            IconButton(
                tooltip: 'Refresh visits',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh)),
            IconButton(
                tooltip: 'Sign out',
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout)),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _load(),
          child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const Text('Your field visits',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                    'Visit the assigned farm, record the gadget readings and submit your report for admin review.'),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  value: _status ?? '',
                  decoration: const InputDecoration(
                      labelText: 'Visit status', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('All assigned visits')),
                    ...FieldVisit.statusLabels.entries.map((entry) =>
                        DropdownMenuItem(
                            value: entry.key, child: Text(entry.value))),
                  ],
                  onChanged: (value) {
                    _status = value == '' ? null : value;
                    _load(reset: true);
                  },
                ),
                const SizedBox(height: 20),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(children: [
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                        TextButton(
                            onPressed: _load, child: const Text('Try again')),
                      ])),
                if (!_loading && _error == null && _visits.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                          'No visits in this view. Admin-approved visits appear here once assigned to you.',
                          textAlign: TextAlign.center)),
                ..._visits.map((visit) => Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(visit.statusLabel,
                                    style: const TextStyle(
                                        color: Color(0xFF587345))),
                                const SizedBox(height: 10),
                                Text(visit.farmName,
                                    style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(visit.text('farmerName', 'Farmer')),
                                const SizedBox(height: 5),
                                Text(visit.text(
                                    'farmAddress', visit.text('city'))),
                                const SizedBox(height: 14),
                                OutlinedButton(
                                    onPressed: () => _open(visit),
                                    child: Text(visit.canRecord
                                        ? 'Open visit & record readings'
                                        : 'View submitted report')),
                              ])),
                    )),
                const SizedBox(height: 8),
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
                          child: const Text('Previous')),
                      Text('Page ${_page + 1}'),
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
                          child: const Text('Next')),
                    ]),
              ]),
        ),
      );
}
