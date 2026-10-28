import '../../services/app_language.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/survey.dart';
import 'reviews_screen.dart';
import 'contact_admin_screen.dart';

class SurveyDetailScreen extends StatelessWidget {
  final Survey survey;
  const SurveyDetailScreen({super.key, required this.survey});

  Widget row(BuildContext context, String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(tr(label, context: context),
                  style: TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(
              child: Text(tr(value, context: context),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ]),
      );

  Widget section(BuildContext context, String title, List<Widget> children) =>
      Card(
        margin: EdgeInsets.only(bottom: 17),
        child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr(title, context: context),
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                Divider(height: 24),
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
              appBar:
                  AppBar(title: Text(tr('Survey details', context: context))),
              body: Center(
                  child: Text(tr(
                      'Unable to load this survey. Please try again.',
                      context: context))));
        if (snapshot.hasData && !snapshot.data!.exists)
          return Scaffold(
              appBar:
                  AppBar(title: Text(tr('Survey details', context: context))),
              body: Center(
                  child: Text(tr('This survey is no longer available.',
                      context: context))));
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
          appBar:
              AppBar(title: Text(tr('Track your survey', context: context))),
          body: ListView(padding: EdgeInsets.all(20), children: [
            Text(tr(s.farmName, context: context),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(tr(s.status.label, context: context),
                style: TextStyle(color: Color(0xFF6C895A))),
            SizedBox(height: 22),
            section(context, 'Visit progress', [
              for (var index = 0; index < 5; index++)
                Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Icon(
                          stage >= index
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: stage >= index
                              ? Color(0xFF63864D)
                              : Colors.grey[300],
                          size: 20),
                      SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              tr(
                                  [
                                    'Request sent',
                                    'Visit approved & team assigned',
                                    'Field team visiting',
                                    'Admin reviewing team report',
                                    'Recommendation released'
                                  ][index],
                                  context: context),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: stage >= index
                                      ? Colors.black87
                                      : Colors.grey))),
                    ])),
            ]),
            section(context, 'Farm information', [
              row(context, 'Address',
                  s.farmAddress.isEmpty ? s.city : s.farmAddress),
              row(context, 'City', s.city),
              row(context, 'Soil', s.soilType),
              row(context, 'Season', '${s.season} ${s.year}'),
              if (s.assignedTeamName.isNotEmpty)
                row(context, 'Assigned team', s.assignedTeamName),
            ]),
            if (s.isDemo)
              Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(tr(Survey.demoNotice, context: context),
                      style: TextStyle(color: Color(0xFF9C6428)))),
            if (s.moisture != null)
              section(context, 'Team-recorded readings', [
                row(context, 'Moisture', '${s.moisture!.toStringAsFixed(1)}%'),
                row(
                    context,
                    s.isDemo ? 'Temperature (SIMULATED)' : 'Temperature',
                    s.temperature == null
                        ? '—'
                        : '${s.temperature!.toStringAsFixed(1)} °C'),
                row(context, 'Manual nitrogen', '${s.nitrogen ?? '—'}'),
                row(context, 'Manual phosphorus', '${s.phosphorus ?? '—'}'),
                row(context, 'Manual potassium', '${s.potassium ?? '—'}'),
              ]),
            if (s.status == SurveyStatus.awaitingReview)
              Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                      tr('The team report has arrived. Admin is reviewing your crop recommendation.',
                          context: context),
                      style: TextStyle(color: Color(0xFF9C7B38), height: 1.6))),
            if (s.isCompleted)
              section(context, 'Your released recommendation', [
                Text(tr(s.recommendedCrop ?? '—', context: context),
                    style: TextStyle(fontSize: 29, color: Color(0xFF235B44))),
                SizedBox(height: 10),
                row(
                    context,
                    'Estimated rainfall',
                    s.predictedRainfall == null
                        ? '—'
                        : '${s.predictedRainfall!.toStringAsFixed(1)} mm'),
                OutlinedButton.icon(
                    icon: Icon(Icons.star_outline),
                    label: Text(tr('Review this survey', context: context)),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ReviewsScreen(
                                surveyId: s.id, surveyCompleted: true)))),
              ]),
            if (s.status == SurveyStatus.rejected)
              Text(
                  tr('This request was rejected or cancelled. Contact admin if you need help.',
                      context: context),
                  style: TextStyle(color: Colors.grey)),
            OutlinedButton.icon(
                icon: Icon(Icons.support_agent),
                label: Text(
                    tr('Contact admin about this survey', context: context)),
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
