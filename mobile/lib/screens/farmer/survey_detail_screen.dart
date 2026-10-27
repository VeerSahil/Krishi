import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/survey.dart';
import 'reviews_screen.dart';
import 'contact_admin_screen.dart';

class SurveyDetailScreen extends StatelessWidget {
  final Survey survey;
  const SurveyDetailScreen({super.key, required this.survey});

  Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500))),
        ]),
      );

  Widget section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 17),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const Divider(height: 24),
                ...children
              ],
            )),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('farm_inputs')
          .doc(survey.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Scaffold(
              appBar: AppBar(title: const Text('Survey details')),
              body: const Center(
                  child:
                      Text('Unable to load this survey. Please try again.')));
        if (snapshot.hasData && !snapshot.data!.exists)
          return Scaffold(
              appBar: AppBar(title: const Text('Survey details')),
              body: const Center(
                  child: Text('This survey is no longer available.')));
        final s =
            snapshot.hasData ? Survey.fromFirestore(snapshot.data!) : survey;
        final stage = s.status == SurveyStatus.pending
            ? 0
            : s.status == SurveyStatus.approved
                ? 1
                : s.status == SurveyStatus.inProgress
                    ? 2
                    : s.status == SurveyStatus.awaitingReview
                        ? 3
                        : s.isCompleted
                            ? 4
                            : -1;
        return Scaffold(
          appBar: AppBar(title: const Text('Track your survey')),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            Text(s.farmName,
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(s.status.label,
                style: const TextStyle(color: Color(0xFF6C895A))),
            const SizedBox(height: 22),
            section('Visit progress', [
              for (var index = 0; index < 5; index++)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Icon(
                          stage >= index
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: stage >= index
                              ? const Color(0xFF63864D)
                              : Colors.grey[300],
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              [
                                'Request sent',
                                'Visit approved & team assigned',
                                'Field team visiting',
                                'Admin reviewing team report',
                                'Recommendation released'
                              ][index],
                              style: TextStyle(
                                  fontSize: 12,
                                  color: stage >= index
                                      ? Colors.black87
                                      : Colors.grey))),
                    ])),
            ]),
            section('Farm information', [
              row('Address', s.farmAddress.isEmpty ? s.city : s.farmAddress),
              row('City', s.city),
              row('Soil', s.soilType),
              row('Season', '${s.season} ${s.year}'),
              if (s.assignedTeamName.isNotEmpty)
                row('Assigned team', s.assignedTeamName),
            ]),
            if (s.isDemo)
              const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(Survey.demoNotice,
                      style: TextStyle(color: Color(0xFF9C6428)))),
            if (s.moisture != null)
              section('Team-recorded readings', [
                row('Moisture', '${s.moisture!.toStringAsFixed(1)}%'),
                row(
                    s.isDemo ? 'Temperature (SIMULATED)' : 'Temperature',
                    s.temperature == null
                        ? '—'
                        : '${s.temperature!.toStringAsFixed(1)} °C'),
                row('Manual nitrogen', '${s.nitrogen ?? '—'}'),
                row('Manual phosphorus', '${s.phosphorus ?? '—'}'),
                row('Manual potassium', '${s.potassium ?? '—'}'),
              ]),
            if (s.status == SurveyStatus.awaitingReview)
              const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                      'The team report has arrived. Admin is reviewing your crop recommendation.',
                      style: TextStyle(color: Color(0xFF9C7B38), height: 1.6))),
            if (s.isCompleted)
              section('Your released recommendation', [
                Text(s.recommendedCrop ?? '—',
                    style: const TextStyle(
                        fontSize: 29, color: Color(0xFF235B44))),
                const SizedBox(height: 10),
                row(
                    'Estimated rainfall',
                    s.predictedRainfall == null
                        ? '—'
                        : '${s.predictedRainfall!.toStringAsFixed(1)} mm'),
                OutlinedButton.icon(
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Review this survey'),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ReviewsScreen(
                                surveyId: s.id, surveyCompleted: true)))),
              ]),
            if (s.status == SurveyStatus.rejected)
              const Text(
                  'This request was rejected or cancelled. Contact admin if you need help.',
                  style: TextStyle(color: Colors.grey)),
            OutlinedButton.icon(
                icon: const Icon(Icons.support_agent),
                label: const Text('Contact admin about this survey'),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ContactAdminScreen(surveyId: s.id)))),
          ]),
        );
      },
    );
  }
}
