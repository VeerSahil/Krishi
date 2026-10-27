import 'package:flutter/material.dart';
import '../../models/survey.dart';
import '../../services/api_service.dart';
import '../../widgets/loading_widget.dart';
import '../../auth/auth_service.dart';

class PendingSurveysScreen extends StatelessWidget {
  const PendingSurveysScreen({super.key});

  Future<void> _markDone(BuildContext context, Survey survey) async {
    double moisture = survey.moisture ?? 50.0;
    String temperatureCategory = 'Moderate';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Process Survey'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Moisture (%)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: moisture,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '${moisture.toStringAsFixed(0)}%',
                      activeColor: Colors.green[700],
                      onChanged: (val) => setState(() => moisture = val),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${moisture.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 13),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Temperature',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: temperatureCategory,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'Low', child: Text('Low (~20°C)')),
                  DropdownMenuItem(
                      value: 'Moderate', child: Text('Moderate (~28°C)')),
                  DropdownMenuItem(value: 'High', child: Text('High (~35°C)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => temperatureCategory = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Process'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      await ApiService().markSurveyDone(
        survey.id,
        moisture: moisture,
        temperatureCategory: temperatureCategory,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Survey processed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Surveys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<Survey>>(
        stream: ApiService().pendingSurveysStream(),
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
            return const LoadingWidget(message: 'Loading pending surveys...');
          }
          final surveys = snapshot.data ?? [];
          if (surveys.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green),
                  SizedBox(height: 12),
                  Text('No pending surveys',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: surveys.length,
            itemBuilder: (context, i) {
              final s = surveys[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.farmerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(s.farmerEmail,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _chip(Icons.location_city, s.city),
                          const SizedBox(width: 8),
                          _chip(Icons.landscape, s.soilType),
                          const SizedBox(width: 8),
                          _chip(Icons.wb_sunny_outlined, s.season),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (s.moisture != null)
                        Text(
                            'Moisture: ${s.moisture}% | Temp: ${s.temperature}°C',
                            style: const TextStyle(fontSize: 13))
                      else
                        const Text('⚠ Awaiting on-site measurements',
                            style:
                                TextStyle(color: Colors.orange, fontSize: 13)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.green[700]),
                          icon: const Icon(Icons.check),
                          label: const Text('Mark as Done'),
                          onPressed: () => _markDone(context, s),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.green[700]),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.green[700])),
        ],
      ),
    );
  }
}
