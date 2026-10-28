import '../../services/app_language.dart';
import 'package:flutter/material.dart';
import '../../models/survey.dart';
import '../../services/api_service.dart';
import '../../widgets/loading_widget.dart';

class AllSurveysScreen extends StatelessWidget {
  const AllSurveysScreen({super.key});

  Color _statusColor(SurveyStatus s) {
    switch (s) {
      case SurveyStatus.pending:
        return Colors.orange;
      case SurveyStatus.approved:
      case SurveyStatus.awaitingReview:
      case SurveyStatus.inProgress:
        return Colors.blue;
      case SurveyStatus.done:
      case SurveyStatus.completed:
        return Colors.green;
      case SurveyStatus.failed:
        return Colors.red;
      case SurveyStatus.rejected:
        return Colors.grey;
    }
  }

  String _statusLabel(SurveyStatus s) => s.label;

  IconData _statusIcon(SurveyStatus s) {
    switch (s) {
      case SurveyStatus.pending:
        return Icons.hourglass_bottom;
      case SurveyStatus.approved:
      case SurveyStatus.awaitingReview:
      case SurveyStatus.inProgress:
        return Icons.autorenew;
      case SurveyStatus.done:
      case SurveyStatus.completed:
        return Icons.check_circle;
      case SurveyStatus.failed:
        return Icons.error_outline;
      case SurveyStatus.rejected:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('All Surveys', context: context))),
      body: StreamBuilder<List<Survey>>(
        stream: ApiService().allSurveysStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(tr(
                    'Unable to load data. Check your connection and try again.',
                    context: context)),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return LoadingWidget();
          }
          final surveys = snapshot.data ?? [];
          if (surveys.isEmpty) {
            return Center(
                child: Text(tr('No surveys found', context: context)));
          }
          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: surveys.length,
            itemBuilder: (context, i) {
              final s = surveys[i];
              final color = _statusColor(s.status);
              return Card(
                margin: EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  title: Text(
                    tr(s.farmerName, context: context),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 2),
                      Text(tr(
                          '${s.city} · ${s.soilType} · ${s.season} ${s.year}',
                          context: context)),
                      SizedBox(height: 4),
                      if (s.isCompleted) ...[
                        if (s.recommendedCrop != null)
                          Text(
                            tr('🌱 ${s.recommendedCrop}', context: context),
                            style: TextStyle(color: Colors.green),
                          ),
                        if (s.predictedRainfall != null)
                          Text(
                            tr('💧 ${s.predictedRainfall!.toStringAsFixed(1)} mm rainfall',
                                context: context),
                            style: TextStyle(color: Colors.green),
                          ),
                      ],
                      if (s.status == SurveyStatus.failed)
                        Text(
                          tr('Processing failed', context: context),
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      if (s.status == SurveyStatus.rejected)
                        Text(
                          tr('Rejected by admin', context: context),
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                    ],
                  ),
                  trailing: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon(s.status), size: 13, color: color),
                        SizedBox(width: 4),
                        Text(
                          tr(_statusLabel(s.status), context: context),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
