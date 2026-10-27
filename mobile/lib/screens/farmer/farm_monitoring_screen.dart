import 'package:flutter/material.dart';
import '../../models/survey.dart';
import '../../services/api_service.dart';
import 'survey_detail_screen.dart';

class FarmMonitoringScreen extends StatelessWidget {
  const FarmMonitoringScreen({super.key});

  Widget reading(String label, String value, IconData icon) => Expanded(
          child: Column(children: [
        Icon(icon, color: const Color(0xFF6A8758), size: 25),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w500)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F1),
      appBar: AppBar(title: const Text('My farm')),
      body: StreamBuilder<List<Survey>>(
        stream: ApiService().farmerSurveysStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(
                child: Text('Unable to load farm readings. Please try again.'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final groups = <String, List<Survey>>{};
          for (final survey in snapshot.data!) {
            final key =
                '${survey.farmName}|${survey.farmAddress.isEmpty ? survey.city : survey.farmAddress}'
                    .toLowerCase();
            groups.putIfAbsent(key, () => []).add(survey);
          }
          if (groups.isEmpty)
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                        'Book your first survey to start tracking your farm and its readings.',
                        textAlign: TextAlign.center)));
          return ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Your farm, at a glance.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 9),
            const Text(
                'These are the latest recorded field-visit readings. They update when our team submits a report.',
                style: TextStyle(color: Colors.grey, height: 1.6)),
            const SizedBox(height: 22),
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
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFE1E7D8))),
                child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(latest.farmName,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                            latest.farmAddress.isEmpty
                                ? latest.city
                                : latest.farmAddress,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 15),
                        Text('Latest request: ${latest.status.label}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6C895A))),
                        const Divider(height: 32),
                        if (report == null)
                          const Text(
                              'Readings will appear after the field team visits your farm.')
                        else ...[
                          Row(children: [
                            reading(
                                'Moisture',
                                '${report.moisture!.toStringAsFixed(1)}%',
                                Icons.water_drop_outlined),
                            reading(
                                report.isDemo
                                    ? 'Demo temperature'
                                    : 'Temperature',
                                '${report.temperature!.toStringAsFixed(1)} °C',
                                Icons.thermostat_outlined),
                          ]),
                          const SizedBox(height: 22),
                          if (report.isDemo)
                            const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(Survey.demoNotice,
                                    style:
                                        TextStyle(color: Color(0xFF9C6428)))),
                          Text(
                              'Manual N / P / K: ${report.nitrogen ?? '—'} / ${report.phosphorus ?? '—'} / ${report.potassium ?? '—'}',
                              style: const TextStyle(fontSize: 12)),
                          if (report.measuredAt != null) ...[
                            const SizedBox(height: 7),
                            Text(
                                'Recorded: ${report.measuredAt!.day}/${report.measuredAt!.month}/${report.measuredAt!.year}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ],
                        ],
                        if (released.isNotEmpty) ...[
                          if (released.first.isDemo)
                            const Text(Survey.demoNotice,
                                style: TextStyle(color: Color(0xFF9C6428))),
                          const Divider(height: 30),
                          const Text('LAST RELEASED RECOMMENDATION',
                              style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  color: Colors.grey)),
                          const SizedBox(height: 7),
                          Text(released.first.recommendedCrop ?? '—',
                              style: const TextStyle(
                                  fontSize: 22, color: Color(0xFF235B44))),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        SurveyDetailScreen(survey: latest))),
                            child: const Text('Track latest survey')),
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
