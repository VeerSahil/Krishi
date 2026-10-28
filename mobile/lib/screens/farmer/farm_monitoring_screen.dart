import '../../services/app_language.dart';
import 'package:flutter/material.dart';
import '../../models/survey.dart';
import '../../services/api_service.dart';
import 'survey_detail_screen.dart';

class FarmMonitoringScreen extends StatelessWidget {
  const FarmMonitoringScreen({super.key});

  Widget reading(
          BuildContext context, String label, String value, IconData icon) =>
      Expanded(
          child: Column(children: [
        Icon(icon, color: Color(0xFF6A8758), size: 25),
        SizedBox(height: 8),
        Text(tr(value, context: context),
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w500)),
        Text(tr(label, context: context),
            style: TextStyle(fontSize: 10, color: Colors.grey)),
      ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF6F7F1),
      appBar: AppBar(title: Text(tr('My farm', context: context))),
      body: StreamBuilder<List<Survey>>(
        stream: ApiService().farmerSurveysStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
                child: Text(tr(
                    'Unable to load farm readings. Please try again.',
                    context: context)));
          if (!snapshot.hasData)
            return Center(child: CircularProgressIndicator());
          final groups = <String, List<Survey>>{};
          for (final survey in snapshot.data!) {
            final key = survey.farmId ??
                '${survey.farmName}|${survey.farmAddress.isEmpty ? survey.city : survey.farmAddress}'
                    .toLowerCase();
            groups.putIfAbsent(key, () => []).add(survey);
          }
          if (groups.isEmpty)
            return Center(
                child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                        tr('Book your first survey to start tracking your farm and its readings.',
                            context: context),
                        textAlign: TextAlign.center)));
          return ListView(padding: EdgeInsets.all(20), children: [
            Text(tr('Your farm, at a glance.', context: context),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            SizedBox(height: 9),
            Text(
                tr('These are the latest recorded field-visit readings. They update when our team submits a report.',
                    context: context),
                style: TextStyle(color: Colors.grey, height: 1.6)),
            SizedBox(height: 22),
            ...groups.values.map((history) {
              final latest = history.first;
              final measured = history
                  .where((survey) =>
                      survey.moisture != null && survey.temperature != null)
                  .toList();
              final released =
                  history.where((survey) => survey.isCompleted).toList();
              final report = measured.isEmpty ? null : measured.first;
              return Card(
                color: Colors.white,
                elevation: 0,
                margin: EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: Color(0xFFE1E7D8))),
                child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(latest.farmName,
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600)),
                        SizedBox(height: 6),
                        Text(
                            tr(
                                latest.farmAddress.isEmpty
                                    ? latest.city
                                    : latest.farmAddress,
                                context: context),
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        SizedBox(height: 15),
                        Text(
                            tr('Latest request: ${latest.status.label}',
                                context: context),
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF6C895A))),
                        Divider(height: 32),
                        if (report == null)
                          Text(tr(
                              'Readings will appear after the field team visits your farm.',
                              context: context))
                        else ...[
                          Row(children: [
                            reading(
                                context,
                                'Moisture',
                                '${report.moisture!.toStringAsFixed(1)}%',
                                Icons.water_drop_outlined),
                            reading(
                                context,
                                report.isDemo
                                    ? 'Demo temperature'
                                    : 'Temperature',
                                '${report.temperature!.toStringAsFixed(1)} °C',
                                Icons.thermostat_outlined),
                          ]),
                          SizedBox(height: 22),
                          if (report.isDemo)
                            Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                    tr(Survey.demoNotice, context: context),
                                    style:
                                        TextStyle(color: Color(0xFF9C6428)))),
                          Text(
                              tr('Manual N / P / K: ${report.nitrogen ?? '—'} / ${report.phosphorus ?? '—'} / ${report.potassium ?? '—'}',
                                  context: context),
                              style: TextStyle(fontSize: 12)),
                          if (report.measuredAt != null) ...[
                            SizedBox(height: 7),
                            Text(
                                tr('Recorded: ${report.measuredAt!.day}/${report.measuredAt!.month}/${report.measuredAt!.year}',
                                    context: context),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ],
                        ],
                        if (released.isNotEmpty) ...[
                          if (released.first.isDemo)
                            Text(tr(Survey.demoNotice, context: context),
                                style: TextStyle(color: Color(0xFF9C6428))),
                          Divider(height: 30),
                          Text(tr('LAST APPROVED REPORT', context: context),
                              style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  color: Colors.grey)),
                          SizedBox(height: 7),
                          Text(
                              tr(released.first.recommendedCrop ?? '—',
                                  context: context),
                              style: TextStyle(
                                  fontSize: 22, color: Color(0xFF235B44))),
                        ],
                        SizedBox(height: 16),
                        OutlinedButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        SurveyDetailScreen(survey: latest))),
                            child: Text(
                                tr('Track latest survey', context: context))),
                      ],
                    )),
              );
            }),
          ]);
        },
      ),
    );
  }
}
