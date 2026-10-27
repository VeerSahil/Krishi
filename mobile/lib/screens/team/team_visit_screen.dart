import 'package:flutter/material.dart';
import '../../models/field_visit.dart';
import '../../services/backend_client.dart';
import '../../services/team_api.dart';
import '../../services/demo_temperature.dart';

class TeamVisitScreen extends StatefulWidget {
  final String visitId;
  final TeamRepository repository;
  final VoidCallback onSessionEnded;
  const TeamVisitScreen(
      {super.key,
      required this.visitId,
      required this.repository,
      required this.onSessionEnded});

  @override
  State<TeamVisitScreen> createState() => _TeamVisitScreenState();
}

class _TeamVisitScreenState extends State<TeamVisitScreen> {
  static const fields = {
    'moisture': 'Moisture (%)',
    'temperature': 'Temperature (°C)',
    'nitrogen': 'Nitrogen (manual)',
    'phosphorus': 'Phosphorus (manual)',
    'potassium': 'Potassium (manual)',
  };
  final _form = GlobalKey<FormState>();
  final _controllers = {
    for (final key in fields.keys) key: TextEditingController()
  };
  final _notes = TextEditingController();
  FieldVisit? _visit;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _simulated = false;
  String _temperatureCategory = 'moderate';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    if (error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onSessionEnded();
      return;
    }
    setState(() => _error = error.toString());
  }

  Future<void> _load({bool preserveDraft = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final visit = await widget.repository.visit(widget.visitId);
      if (!mounted) return;
      if (!preserveDraft || !visit.canRecord) {
        for (final key in fields.keys) {
          _controllers[key]!.text = visit.reading(key)?.toString() ?? '';
        }
        _notes.text = visit.text('teamNotes');
        _simulated = visit.text('temperatureSource') == 'simulated';
        _temperatureCategory = visit.text('temperatureCategory', 'moderate');
      }
      setState(() => _visit = visit);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.start(widget.visitId);
      await _load(preserveDraft: true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy || _visit?.canRecord != true)
      return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final readings = <String, dynamic>{
      for (final key in fields.keys)
        key: double.parse(_controllers[key]!.text.trim()),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      if (_simulated) 'temperatureSource': 'simulated',
      if (_simulated) 'temperatureCategory': _temperatureCategory,
    };
    try {
      await widget.repository.submit(widget.visitId, readings);
      if (mounted) {
        setState(() => _busy = false);
        Navigator.pop(context, true);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(String key, String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || !number.isFinite) return 'Enter a valid number';
    if (key == 'temperature' &&
        _simulated &&
        !DemoTemperature.matches(_temperatureCategory, number)) {
      return 'Value must match the selected demo range';
    }
    final minimum = key == 'temperature' ? -40 : 0;
    final maximum = key == 'moisture'
        ? 100
        : key == 'temperature'
            ? 80
            : 10000;
    if (number < minimum || number > maximum)
      return 'Use a value from $minimum to $maximum';
    return null;
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          SelectableText(value.isEmpty ? '—' : value),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Farm visit'), actions: [
            IconButton(
                tooltip: 'Refresh report',
                onPressed: _busy || _loading ? null : _load,
                icon: const Icon(Icons.refresh)),
          ]),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(22), children: [
                  if (visit != null) ...[
                    Text(visit.farmName,
                        style: const TextStyle(
                            fontSize: 27, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(visit.statusLabel),
                    if (visit.text('temperatureSource') == 'simulated')
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(DemoTemperature.notice,
                              style: TextStyle(color: Color(0xFF9C6428)))),
                    const Divider(height: 35),
                    _detail('Farmer', visit.text('farmerName')),
                    _detail('Contact phone', visit.text('contactPhone')),
                    _detail('Farm address',
                        visit.text('farmAddress', visit.text('city'))),
                    _detail('City', visit.text('city')),
                    _detail('Soil',
                        visit.text('soilType', visit.text('soil_type'))),
                    _detail('Season',
                        '${visit.text('season')} ${visit.text('year')}'),
                    if (visit.text('adminNotes').isNotEmpty)
                      _detail('Admin notes', visit.text('adminNotes')),
                    if (visit.canRecord) ...[
                      if (visit.status == 'approved')
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _start,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start visit'),
                        ),
                      const SizedBox(height: 20),
                      const Text('Record field readings',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      const Text(
                          'Enter moisture and manual N/P/K. For the LM393 prototype, select demo temperature and copy its generated value or generate one below.'),
                      const SizedBox(height: 20),
                      Form(
                          key: _form,
                          child: Column(children: [
                            SwitchListTile(
                              title: const Text(
                                  'Use simulated temperature (demo)'),
                              value: _simulated,
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                        _simulated = value;
                                        _controllers['temperature']!.clear();
                                      }),
                            ),
                            if (_simulated) ...[
                              const Text(DemoTemperature.notice),
                              DropdownButtonFormField<String>(
                                value: _temperatureCategory,
                                decoration: const InputDecoration(
                                    labelText: 'Demo temperature range'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'low',
                                      child: Text('Low: 15–19.9 °C')),
                                  DropdownMenuItem(
                                      value: 'moderate',
                                      child: Text('Moderate: 20–29.9 °C')),
                                  DropdownMenuItem(
                                      value: 'high',
                                      child: Text('High: 30–35 °C')),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                          _temperatureCategory = value!;
                                          _controllers['temperature']!.clear();
                                        }),
                              ),
                              TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                            _controllers['temperature']!.text =
                                                DemoTemperature.generate(
                                                        _temperatureCategory)
                                                    .toStringAsFixed(1);
                                          }),
                                  icon: const Icon(Icons.casino_outlined),
                                  label:
                                      const Text('Generate demo temperature')),
                            ],
                            for (final entry in fields.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: TextFormField(
                                  key: ValueKey(entry.key),
                                  controller: _controllers[entry.key],
                                  enabled: !_busy,
                                  keyboardType: TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: entry.key == 'temperature'),
                                  decoration: InputDecoration(
                                      labelText: entry.key == 'temperature' &&
                                              _simulated
                                          ? 'Temperature (SIMULATED °C)'
                                          : entry.value,
                                      border: const OutlineInputBorder()),
                                  validator: (value) =>
                                      _validate(entry.key, value),
                                ),
                              ),
                            TextFormField(
                                controller: _notes,
                                enabled: !_busy,
                                maxLength: 2000,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                    labelText: 'Visit notes (optional)',
                                    border: OutlineInputBorder())),
                            const SizedBox(height: 18),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _submit,
                                  icon: const Icon(Icons.send_outlined),
                                  label: Text(_busy
                                      ? 'Saving report…'
                                      : 'Submit readings for review'),
                                )),
                          ])),
                    ] else ...[
                      for (final entry in fields.entries)
                        if (visit.reading(entry.key) != null)
                          _detail(
                              entry.key == 'temperature' && _simulated
                                  ? 'Temperature (SIMULATED °C)'
                                  : entry.value,
                              visit.reading(entry.key).toString()),
                      if (visit.text('teamNotes').isNotEmpty)
                        _detail('Visit notes', visit.text('teamNotes')),
                      if (visit.status == 'awaiting_review')
                        const Text(
                            'Your readings have been submitted. Admin will review and release the crop recommendation.'),
                      if (visit.status == 'completed')
                        _detail(
                            'Released crop recommendation',
                            visit.text('recommended_crop',
                                visit.text('recommendedCrop', '—'))),
                      if (visit.status == 'rejected')
                        const Text(
                            'This visit has been cancelled or rejected. Contact admin for details.'),
                    ],
                  ],
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (visit == null)
                    TextButton(
                        onPressed: _load, child: const Text('Try again')),
                ]),
        ));
  }
}
