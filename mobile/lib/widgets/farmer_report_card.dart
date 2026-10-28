import 'package:flutter/material.dart';
import '../services/app_language.dart';

class FarmerReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  const FarmerReportCard({super.key, required this.report});
  Widget reading(BuildContext context, String label, Object? value,
          [String unit = '']) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
                child: Text(tr(label, context: context),
                    style: const TextStyle(
                        color: Color(0xFF76876B), fontSize: 12))),
            Text(value == null ? '—' : '$value$unit',
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ]));
  @override
  Widget build(BuildContext context) {
    final readings = Map<String, dynamic>.from(report['readings'] ?? {});
    final steps = List<String>.from(report['actions'] ?? []);
    final notices = List<String>.from(report['notices'] ?? []);
    final grade = report['careClass'] ?? 'U';
    return Card(
        color: const Color(0xFFF0F5E8),
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 18),
        child: Padding(
            padding: const EdgeInsets.all(21),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.fact_check_outlined,
                        color: Color(0xFF4D7444)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            report['title'] ??
                                tr('Your farm visit report', context: context),
                            style: const TextStyle(
                                fontSize: 21, fontWeight: FontWeight.w600)))
                  ]),
                  const SizedBox(height: 15),
                  Text(
                      '${tr('Care class', context: context)} $grade · ${report['careLabel'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text(report['summary'] ?? '',
                      style: const TextStyle(fontSize: 16, height: 1.65)),
                  const SizedBox(height: 19),
                  Text(tr('Your next steps', context: context),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (var i = 0; i < steps.length; i++)
                    Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: Text('${i + 1}. ${steps[i]}',
                            style: const TextStyle(height: 1.65))),
                  if (readings.isNotEmpty)
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                            tr('Readings from this visit', context: context),
                            style: const TextStyle(fontSize: 13)),
                        children: [
                          reading(
                              context,
                              readings['moistureUnit'] == 'vwc_percent'
                                  ? 'Volumetric moisture'
                                  : 'Relative / declared moisture',
                              readings['moisture'],
                              '%'),
                          reading(
                              context,
                              readings['temperatureSource'] == 'simulated'
                                  ? 'Temperature (SIMULATED)'
                                  : 'Temperature',
                              readings['temperature'],
                              ' °C'),
                          for (final key in [
                            'nitrogen',
                            'phosphorus',
                            'potassium'
                          ])
                            reading(
                                context,
                                {
                                  'nitrogen': 'Nitrogen',
                                  'phosphorus': 'Phosphorus',
                                  'potassium': 'Potassium'
                                }[key]!,
                                readings[key]),
                          Text(
                              readings['nutrientUnit'] == 'unknown'
                                  ? tr('Nutrient units were not specified.',
                                      context: context)
                                  : '${tr('Nutrient units', context: context)}: ${readings['nutrientUnit'] ?? '—'}',
                              style: const TextStyle(fontSize: 11)),
                        ]),
                  for (final note in notices)
                    Padding(
                        padding: const EdgeInsets.only(top: 13),
                        child: Text(note,
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: Color(0xFF92743A)))),
                ])));
  }
}
