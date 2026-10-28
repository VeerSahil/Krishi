import '../../services/app_language.dart';
import 'package:flutter/material.dart';
import '../../models/field_visit.dart';
import '../../services/backend_client.dart';
import '../../services/team_api.dart';
import '../../services/offline_team.dart';
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
  final _soilReference = TextEditingController();
  final _attachment = TextEditingController();
  String _nutrientUnit = 'unknown';
  String _nutrientSource = 'manual';
  String _moistureSource = 'manual';
  String? _capturedAt;
  String? _draftMessage;
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
    _soilReference.dispose();
    _attachment.dispose();
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
      if (visit.canRecord &&
          !preserveDraft &&
          widget.repository is OfflineTeamRepository) {
        final draft = await (widget.repository as OfflineTeamRepository)
            .draft(widget.visitId);
        if (!mounted) return;
        if (draft != null) {
          for (final key in fields.keys) {
            _controllers[key]!.text = draft[key]?.toString() ?? '';
          }
          _notes.text = draft['notes'] ?? '';
          _simulated = draft['temperatureSource'] == 'simulated';
          _temperatureCategory = draft['temperatureCategory'] ?? 'moderate';
          _nutrientUnit = draft['nutrientUnit'] ?? 'unknown';
          _nutrientSource = draft['nutrientSource'] ?? 'manual';
          _moistureSource = draft['moistureSource'] ?? 'manual';
          _soilReference.text = draft['soilTestReference'] ?? '';
          _attachment.text = draft['soilTestAttachmentUrl'] ?? '';
          _capturedAt = draft['capturedAt'];
          _draftMessage = 'Saved draft restored from this phone.';
        }
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
      'capturedAt': _capturedAt ?? DateTime.now().toUtc().toIso8601String(),
      'soilTestAttachmentUrl':
          _attachment.text.trim().isEmpty ? null : _attachment.text.trim(),
      'nutrientUnit': _nutrientUnit,
      'nutrientSource': _nutrientSource,
      'moistureSource': _moistureSource,
      'soilTestReference': _soilReference.text.trim().isEmpty
          ? null
          : _soilReference.text.trim(),
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

  Future<void> _saveDraft() async {
    if (widget.repository is! OfflineTeamRepository) return;
    try {
      _capturedAt = DateTime.now().toUtc().toIso8601String();
      await (widget.repository as OfflineTeamRepository)
          .saveDraft(widget.visitId, {
        for (final key in fields.keys) key: _controllers[key]!.text,
        'notes': _notes.text,
        'temperatureSource': _simulated ? 'simulated' : 'measured',
        'temperatureCategory': _temperatureCategory,
        'capturedAt': _capturedAt,
        'soilTestAttachmentUrl':
            _attachment.text.trim().isEmpty ? null : _attachment.text.trim(),
        'nutrientUnit': _nutrientUnit,
        'nutrientSource': _nutrientSource,
        'moistureSource': _moistureSource,
        'soilTestReference': _soilReference.text,
      });
      if (mounted)
        setState(() => _draftMessage = 'Draft saved privately on this phone.');
    } catch (e) {
      _showError(e);
    }
  }

  Widget _choice(String label, String value, List<String> options,
          ValueChanged<String> change) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: tr(label, context: context)),
        items: options
            .map((e) => DropdownMenuItem(
                value: e, child: Text(tr(e, context: context))))
            .toList(),
        onChanged: _busy ? null : (value) => setState(() => change(value!)),
      );

  String? _validate(String key, String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || !number.isFinite)
      return tr('Enter a valid number', context: context);
    if (key == 'temperature' &&
        _simulated &&
        !DemoTemperature.matches(_temperatureCategory, number)) {
      return tr('Value must match the selected demo range', context: context);
    }
    if (key == 'moisture' && number > 100) {
      return tr(
          'This looks like a raw sensor reading. Enter the calibrated 0-100 value.',
          context: context);
    }
    final minimum = key == 'temperature' ? -40 : 0;
    final maximum = key == 'moisture'
        ? 100
        : key == 'temperature'
            ? 80
            : 10000;
    if (number < minimum || number > maximum)
      return tr('Use a value from $minimum to $maximum', context: context);
    return null;
  }

  Widget _detail(String label, String value) => Padding(
        padding: EdgeInsets.only(bottom: 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(label, context: context),
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          SizedBox(height: 4),
          SelectableText(tr(value.isEmpty ? '—' : value, context: context)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar:
              AppBar(title: Text(tr('Farm visit', context: context)), actions: [
            IconButton(
                tooltip: tr('Refresh report', context: context),
                onPressed: _busy || _loading ? null : _load,
                icon: Icon(Icons.refresh)),
          ]),
          body: _loading
              ? Center(child: CircularProgressIndicator())
              : ListView(padding: EdgeInsets.all(22), children: [
                  if (visit != null) ...[
                    Text(visit.farmName,
                        style: TextStyle(
                            fontSize: 27, fontWeight: FontWeight.w600)),
                    SizedBox(height: 8),
                    Text(tr(visit.statusLabel, context: context)),
                    if (visit.text('temperatureSource') == 'simulated')
                      Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              tr(DemoTemperature.notice, context: context),
                              style: TextStyle(color: Color(0xFF9C6428)))),
                    Divider(height: 35),
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
                          icon: Icon(Icons.play_arrow),
                          label: Text(tr('Start visit', context: context)),
                        ),
                      SizedBox(height: 20),
                      Text(tr('Record field readings', context: context),
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w600)),
                      SizedBox(height: 10),
                      Text(tr(
                          'Enter moisture and manual N/P/K. For the LM393 prototype, select demo temperature and copy its generated value or generate one below.',
                          context: context)),
                      SizedBox(height: 20),
                      Form(
                          key: _form,
                          child: Column(children: [
                            if (_draftMessage != null)
                              Text(tr(_draftMessage!, context: context)),
                            if (widget.repository is OfflineTeamRepository &&
                                (widget.repository as OfflineTeamRepository)
                                    .offline)
                              Text(tr(
                                  'Offline: assignment will be checked again during sync.',
                                  context: context)),
                            ExpansionTile(
                              title: Text(tr('Optional report details',
                                  context: context)),
                              initiallyExpanded: false,
                              maintainState: true,
                              children: [
                                _choice(
                                    'Moisture source',
                                    _moistureSource,
                                    ['manual', 'sensor'],
                                    (v) => _moistureSource = v),
                                _choice(
                                    'Nutrient source',
                                    _nutrientSource,
                                    ['manual', 'soil_test'],
                                    (v) => _nutrientSource = v),
                                _choice(
                                    'Nutrient units',
                                    _nutrientUnit,
                                    ['unknown', 'mg/kg', 'kg/ha'],
                                    (v) => _nutrientUnit = v),
                                Text(tr(
                                    'Use the units on the original test. The demo model has no documented NPK units; values are not converted or validated against a lab standard.',
                                    context: context)),
                                TextFormField(
                                    controller: _soilReference,
                                    maxLength: 200,
                                    decoration: InputDecoration(
                                        labelText: tr('Soil-test reference',
                                            context: context)),
                                    validator: (v) => _nutrientSource ==
                                                'soil_test' &&
                                            ((v?.trim().isEmpty ?? true) ||
                                                _nutrientUnit == 'unknown')
                                        ? tr('Enter test reference and units',
                                            context: context)
                                        : null),
                                TextFormField(
                                    controller: _attachment,
                                    maxLength: 1500,
                                    decoration: InputDecoration(
                                        labelText: tr(
                                            'Soil report link (optional HTTPS)',
                                            context: context)),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty)
                                        return null;
                                      final url = Uri.tryParse(v.trim());
                                      return url != null &&
                                              url.scheme == 'https' &&
                                              url.host.isNotEmpty &&
                                              url.userInfo.isEmpty
                                          ? null
                                          : tr(
                                              'Enter a valid HTTPS report link',
                                              context: context);
                                    }),
                              ],
                            ),
                            if (widget.repository is OfflineTeamRepository)
                              OutlinedButton.icon(
                                  onPressed: _busy ? null : _saveDraft,
                                  icon: Icon(Icons.save_outlined),
                                  label: Text(tr('Save draft on phone',
                                      context: context))),
                            SwitchListTile(
                              title: Text(tr('Use simulated temperature (demo)',
                                  context: context)),
                              value: _simulated,
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                        _simulated = value;
                                        _controllers['temperature']!.clear();
                                      }),
                            ),
                            if (_simulated) ...[
                              Text(
                                  tr(DemoTemperature.notice, context: context)),
                              DropdownButtonFormField<String>(
                                value: _temperatureCategory,
                                decoration: InputDecoration(
                                    labelText: tr('Demo temperature range',
                                        context: context)),
                                items: [
                                  DropdownMenuItem(
                                      value: 'low',
                                      child: Text(tr('Low: 15–19.9 °C',
                                          context: context))),
                                  DropdownMenuItem(
                                      value: 'moderate',
                                      child: Text(tr('Moderate: 20–29.9 °C',
                                          context: context))),
                                  DropdownMenuItem(
                                      value: 'high',
                                      child: Text(tr('High: 30–35 °C',
                                          context: context))),
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
                                  icon: Icon(Icons.casino_outlined),
                                  label: Text(tr('Generate demo temperature',
                                      context: context))),
                            ],
                            for (final entry in fields.entries)
                              Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: TextFormField(
                                  key: ValueKey(entry.key),
                                  controller: _controllers[entry.key],
                                  enabled: !_busy,
                                  keyboardType: TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: entry.key == 'temperature'),
                                  decoration: InputDecoration(
                                      labelText: tr(
                                          entry.key == 'temperature' &&
                                                  _simulated
                                              ? 'Temperature (SIMULATED °C)'
                                              : entry.value,
                                          context: context),
                                      helperText: entry.key == 'moisture'
                                          ? tr(
                                              'Use the calibrated 0-100 reading shown by the gadget. Raw A0 values like 525 need calibration first.',
                                              context: context)
                                          : null,
                                      helperMaxLines: 4,
                                      border: OutlineInputBorder()),
                                  validator: (value) =>
                                      _validate(entry.key, value),
                                ),
                              ),
                            TextFormField(
                                controller: _notes,
                                enabled: !_busy,
                                maxLength: 2000,
                                maxLines: 3,
                                decoration: InputDecoration(
                                    labelText: tr('Visit notes (optional)',
                                        context: context),
                                    border: OutlineInputBorder())),
                            SizedBox(height: 18),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _submit,
                                  icon: Icon(Icons.send_outlined),
                                  label: Text(tr(
                                      _busy
                                          ? 'Saving report…'
                                          : 'Submit readings for review',
                                      context: context)),
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
                        Text(tr(
                            'Your readings have been submitted. Admin will review and release the crop recommendation.',
                            context: context)),
                      if (visit.status == 'completed')
                        _detail(
                            'Released crop recommendation',
                            visit.text('recommended_crop',
                                visit.text('recommendedCrop', '—'))),
                      if (visit.status == 'rejected')
                        Text(tr(
                            'This visit has been cancelled or rejected. Contact admin for details.',
                            context: context)),
                    ],
                  ],
                  if (_error != null)
                    Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(tr(_error!, context: context),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (visit == null)
                    TextButton(
                        onPressed: _load,
                        child: Text(tr('Try again', context: context))),
                ]),
        ));
  }
}
