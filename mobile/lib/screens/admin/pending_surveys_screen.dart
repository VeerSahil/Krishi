import '../../services/app_language.dart';
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
          title: Text(tr('Process Survey', context: context)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Moisture (%)', context: context),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: moisture,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: tr('${moisture.toStringAsFixed(0)}%',
                          context: context),
                      activeColor: Colors.green[700],
                      onChanged: (val) => setState(() => moisture = val),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      tr('${moisture.toStringAsFixed(0)}%', context: context),
                      style: TextStyle(fontSize: 13),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                tr('Temperature', context: context),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: temperatureCategory,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'Low',
                      child: Text(tr('Low (~20°C)', context: context))),
                  DropdownMenuItem(
                      value: 'Moderate',
                      child: Text(tr('Moderate (~28°C)', context: context))),
                  DropdownMenuItem(
                      value: 'High',
                      child: Text(tr('High (~35°C)', context: context))),
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
              child: Text(tr('Cancel', context: context)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Process', context: context)),
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
          SnackBar(
            content:
                Text(tr('Survey processed successfully', context: context)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(e.toString(), context: context)),
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
        title: Text(tr('Pending Surveys', context: context)),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<Survey>>(
        stream: ApiService().pendingSurveysStream(),
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
            return LoadingWidget(message: 'Loading pending surveys...');
          }
          final surveys = snapshot.data ?? [];
          if (surveys.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green),
                  SizedBox(height: 12),
                  Text(tr('No pending surveys', context: context),
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: surveys.length,
            itemBuilder: (context, i) {
              final s = surveys[i];
              return Card(
                margin: EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(s.farmerName, context: context),
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(tr(s.farmerEmail, context: context),
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          _chip(context, Icons.location_city, s.city),
                          SizedBox(width: 8),
                          _chip(context, Icons.landscape, s.soilType),
                          SizedBox(width: 8),
                          _chip(context, Icons.wb_sunny_outlined, s.season),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (s.moisture != null)
                        Text(
                            tr('Moisture: ${s.moisture}% | Temp: ${s.temperature}°C',
                                context: context),
                            style: TextStyle(fontSize: 13))
                      else
                        Text(
                            tr('⚠ Awaiting on-site measurements',
                                context: context),
                            style:
                                TextStyle(color: Colors.orange, fontSize: 13)),
                      SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.green[700]),
                          icon: Icon(Icons.check),
                          label: Text(tr('Mark as Done', context: context)),
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

  Widget _chip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.green[700]),
          SizedBox(width: 4),
          Text(tr(label, context: context),
              style: TextStyle(fontSize: 12, color: Colors.green[700])),
        ],
      ),
    );
  }
}
