import '../../widgets/farmer_report_card.dart';
import '../../services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/backend_client.dart';

class FarmEvidenceScreen extends StatefulWidget {
  final BackendClient? backend;
  const FarmEvidenceScreen({super.key, this.backend});
  @override
  State<FarmEvidenceScreen> createState() => _FarmEvidenceScreenState();
}

class _FarmEvidenceScreenState extends State<FarmEvidenceScreen> {
  late final api = widget.backend ??
      BackendClient(
          tokenProvider: (refresh) async =>
              FirebaseAuth.instance.currentUser?.getIdToken(refresh));
  final _crop = TextEditingController();
  final _sowing = TextEditingController();
  final List<Map<String, dynamic>> records = [];
  bool busy = false;
  String? error;
  String? next;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    api.close();
    _crop.dispose();
    _sowing.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await api.get('/farm/evidence' +
          (more && next != null
              ? '?cursor=${Uri.encodeComponent(next!)}'
              : ''));
      if (!mounted) return;
      setState(() {
        if (!more) records.clear();
        records.addAll((result['records'] as List)
            .map((v) => Map<String, dynamic>.from(v)));
        next = result['nextCursor'];
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Map<String, dynamic> record) async {
    final plan = Map<String, dynamic>.from(record['cropPlan'] ?? {});
    final crop = _crop..text = plan['proposedCrop'] ?? '';
    final sowing = _sowing..text = plan['sowingDate'] ?? '';
    String water = plan['irrigation'] ?? 'unknown';
    final form = GlobalKey<FormState>();
    final saved = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, change) => AlertDialog(
                  title: Text(tr('Check my crop plan', context: context)),
                  content: SingleChildScrollView(
                      child: Form(
                          key: form,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            TextFormField(
                                controller: crop,
                                maxLength: 80,
                                decoration: InputDecoration(
                                    labelText: tr('Crop you want to grow',
                                        context: context)),
                                validator: (v) => (v?.trim().length ?? 0) < 2
                                    ? tr('Enter a crop name', context: context)
                                    : null),
                            TextFormField(
                                controller: sowing,
                                readOnly: true,
                                decoration: InputDecoration(
                                    labelText: tr('Planned sowing date',
                                        context: context)),
                                onTap: () async {
                                  final selected = await showDatePicker(
                                      context: ctx,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime.now()
                                          .subtract(Duration(days: 365)),
                                      lastDate: DateTime.now()
                                          .add(Duration(days: 730)));
                                  if (selected != null)
                                    sowing.text = selected
                                        .toIso8601String()
                                        .substring(0, 10);
                                }),
                            DropdownButtonFormField<String>(
                                value: water,
                                decoration: InputDecoration(
                                    labelText:
                                        tr('Irrigation', context: context)),
                                items: [
                                  'unknown',
                                  'rainfed',
                                  'irrigated',
                                  'supplemental'
                                ]
                                    .map((v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(tr(v, context: context))))
                                    .toList(),
                                onChanged: (v) => change(() => water = v!)),
                            SizedBox(height: 12),
                            Text(tr(
                                'This checks evidence and missing information. It does not certify a crop as suitable.',
                                context: context)),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(tr('Cancel', context: context))),
                    FilledButton(
                        onPressed: () {
                          if (form.currentState!.validate())
                            Navigator.pop(ctx, {
                              'surveyId': record['surveyId'],
                              'proposedCrop': crop.text.trim(),
                              'sowingDate':
                                  sowing.text.isEmpty ? null : sowing.text,
                              'irrigation': water
                            });
                        },
                        child: Text(tr('Check plan', context: context)))
                  ],
                )));
    if (!mounted) return;
    if (saved == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.post('/farm/crop-plan', saved);
      await load();
    } catch (e) {
      if (mounted)
        setState(() {
          error = e.toString();
          busy = false;
        });
    }
  }

  Widget item(String label, Object? value) => Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(label, context: context),
            style: TextStyle(fontWeight: FontWeight.w600)),
        Text(value == null
            ? tr('Not recorded', context: context)
            : [
                'Status',
                'Irrigation',
                'Nutrient source',
                'Moisture source',
                'Released crop recommendation'
              ].contains(label)
                ? tr(value.toString(), context: context)
                : value.toString())
      ]));
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(tr('Farm evidence & reports', context: context)),
            actions: [
              IconButton(
                  onPressed: busy ? null : () => load(),
                  icon: Icon(Icons.refresh))
            ]),
        body: ListView(padding: EdgeInsets.all(20), children: [
          Text(tr(
              'Dated records for each survey. Farms with similar names are kept separate.',
              context: context)),
          if (busy) LinearProgressIndicator(),
          if (error != null)
            Text(tr(error!, context: context),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!busy && records.isEmpty)
            Text(tr('Book a survey to start your farm evidence record.',
                context: context)),
          for (final r in records)
            Card(
                child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['farmName'] ?? tr('Farm', context: context),
                              style: Theme.of(context).textTheme.titleLarge),
                          item('Survey ID', r['surveyId']),
                          item('Farm address', r['farmAddress']),
                          item('Status', r['status']),
                          for (final e in r['timeline'] as List)
                            item(e['event'], e['at']),
                          if (r['evidence'] != null) ...[
                            item('Evidence record ID',
                                r['evidence']['submissionId']),
                            item('Captured on phone',
                                r['evidence']['capturedAt']),
                            item('Received by server',
                                r['evidence']['receivedAt']),
                            item('Recorded by', r['evidence']['recordedBy']),
                            item('Moisture (%)', r['evidence']['moisture']),
                            item('Moisture source',
                                r['evidence']['moistureSource']),
                            item(
                                r['evidence']['temperatureSource'] ==
                                        'simulated'
                                    ? 'Temperature (SIMULATED)'
                                    : 'Temperature (measured)',
                                r['evidence']['temperature']),
                            item('Nitrogen', r['evidence']['nitrogen']),
                            item('Phosphorus', r['evidence']['phosphorus']),
                            item('Potassium', r['evidence']['potassium']),
                            item('Nutrient source',
                                r['evidence']['nutrientSource']),
                            item('Nutrient units',
                                r['evidence']['nutrientUnit']),
                            item('Soil-test reference',
                                r['evidence']['soilTestReference']),
                            Text(tr(
                                'Sources are declared by the field team. A reference is not independent lab verification.',
                                context: context)),
                          ] else
                            Text(tr(
                                'Legacy record: detailed provenance was not recorded.',
                                context: context)),
                          if (r['evidence']?['soilTestAttachmentUrl'] != null)
                            SelectableText(
                                r['evidence']['soilTestAttachmentUrl']),
                          if (r['releasedCrop'] != null)
                            item('Released crop recommendation',
                                r['releasedCrop']),
                          if (r['publishedBy'] != null)
                            item('Reviewed and released by', r['publishedBy']),
                          if (r['cropPlan'] != null &&
                              r['planCheck'] != null) ...[
                            item('Crop you want to grow',
                                r['cropPlan']['proposedCrop']),
                            item('Planned sowing date',
                                r['cropPlan']['sowingDate']),
                            item('Irrigation', r['cropPlan']['irrigation']),
                            Text(
                                tr(
                                    r['planCheck']['state'] ==
                                            'needs_information'
                                        ? 'More information needed'
                                        : 'Expert review needed',
                                    context: context),
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            for (final gap in r['planCheck']['gaps'] as List)
                              Text(tr(gap, context: context)),
                            if (r['planCheck']['comparison'] == 'same')
                              Text(tr(
                                  'Your chosen crop matches the released demo model result. This does not confirm suitability.',
                                  context: context)),
                            if (r['planCheck']['comparison'] == 'different')
                              Text(tr(
                                  'Your chosen crop differs from the released demo model result. Discuss the reasons with admin; this does not mean your choice is wrong.',
                                  context: context)),
                            for (final action
                                in r['planCheck']['actions'] as List)
                              Text(tr(action, context: context)),
                            for (final limit
                                in r['planCheck']['limits'] as List)
                              Text(tr(limit, context: context)),
                          ],
                          if (r['farmerReport'] != null)
                            FarmerReportCard(
                                report: Map<String, dynamic>.from(
                                    r['farmerReport'])),
                          if (r['farmId'] == null)
                            OutlinedButton.icon(
                                onPressed: busy ? null : () => edit(r),
                                icon: Icon(Icons.fact_check_outlined),
                                label: Text(tr('Check my crop plan',
                                    context: context))),
                        ]))),
          if (next != null)
            TextButton(
                onPressed: busy ? null : () => load(more: true),
                child: Text(tr('Load more', context: context))),
        ]),
      );
}
