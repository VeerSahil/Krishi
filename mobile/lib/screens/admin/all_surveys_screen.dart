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
      appBar: AppBar(title: const Text('All Surveys')),
      body: StreamBuilder<List<Survey>>(
        stream: ApiService().allSurveysStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'Unable to load data. Check your connection and try again.'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget();
          }
          final surveys = snapshot.data ?? [];
          if (surveys.isEmpty) {
            return const Center(child: Text('No surveys found'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: surveys.length,
            itemBuilder: (context, i) {
              final s = surveys[i];
              final color = _statusColor(s.status);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  title: Text(
                    s.farmerName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text('${s.city} · ${s.soilType} · ${s.season} ${s.year}'),
                      const SizedBox(height: 4),
                      if (s.isCompleted) ...[
                        if (s.recommendedCrop != null)
                          Text(
                            '🌱 ${s.recommendedCrop}',
                            style: const TextStyle(color: Colors.green),
                          ),
                        if (s.predictedRainfall != null)
                          Text(
                            '💧 ${s.predictedRainfall!.toStringAsFixed(1)} mm rainfall',
                            style: const TextStyle(color: Colors.green),
                          ),
                      ],
                      if (s.status == SurveyStatus.failed)
                        const Text(
                          'Processing failed',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      if (s.status == SurveyStatus.rejected)
                        const Text(
                          'Rejected by admin',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                    ],
                  ),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon(s.status), size: 13, color: color),
                        const SizedBox(width: 4),
                        Text(
                          _statusLabel(s.status),
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
