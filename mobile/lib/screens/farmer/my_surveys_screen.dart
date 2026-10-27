import 'package:flutter/material.dart';
import '../../models/survey.dart';
import '../../services/api_service.dart';
import '../../widgets/loading_widget.dart';
import 'survey_detail_screen.dart';

class MySurveysScreen extends StatelessWidget {
  const MySurveysScreen({super.key});

  Color _statusColor(SurveyStatus s) {
    switch (s) {
      case SurveyStatus.pending:
        return Colors.orange;
      case SurveyStatus.approved:
      case SurveyStatus.awaitingReview:
      case SurveyStatus.inProgress:
        return Colors.blue;
      case SurveyStatus.done:
        return Colors.green;
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
      appBar: AppBar(title: const Text('My Surveys')),
      body: StreamBuilder<List<Survey>>(
        stream: ApiService().farmerSurveysStream(),
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
            return const LoadingWidget(message: 'Loading surveys...');
          }

          final surveys = snapshot.data ?? [];

          if (surveys.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_outlined, size: 70, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No surveys booked yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: surveys.length,
            itemBuilder: (context, index) {
              final s = surveys[index];

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SurveyDetailScreen(survey: s),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Top row: city + status badge ──────────────
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.city,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _statusColor(s.status).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _statusIcon(s.status),
                                    size: 14,
                                    color: _statusColor(s.status),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _statusLabel(s.status),
                                    style: TextStyle(
                                      color: _statusColor(s.status),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '${s.soilType} Soil • ${s.season} ${s.year}',
                          style: const TextStyle(color: Colors.black54),
                        ),

                        const SizedBox(height: 12),

                        // ── Status-specific content ────────────────────
                        if (s.status == SurveyStatus.pending)
                          const Text(
                            '⏳ Waiting for survey processing...',
                            style: TextStyle(color: Colors.orange),
                          ),

                        if (s.status == SurveyStatus.inProgress)
                          const Text(
                            '⚙️ ML analysis in progress...',
                            style: TextStyle(color: Colors.blue),
                          ),

                        if (s.status == SurveyStatus.failed)
                          const Text(
                            '❌ Processing failed. Contact support.',
                            style: TextStyle(color: Colors.red),
                          ),

                        if (s.status == SurveyStatus.rejected)
                          const Text(
                            '🚫 Survey was rejected by admin.',
                            style: TextStyle(color: Colors.grey),
                          ),

                        // Completed / done — show results
                        if (s.isDemo)
                          const Text(Survey.demoNotice,
                              style: TextStyle(color: Color(0xFF9C6428))),
                        if (s.isCompleted) ...[
                          if (s.predictedRainfall != null)
                            Text(
                              '🌧 Rainfall: ${s.predictedRainfall!.toStringAsFixed(1)} mm',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          const SizedBox(height: 4),
                          if (s.recommendedCrop != null)
                            Text(
                              '🌱 Recommended Crop: ${s.recommendedCrop}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
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
