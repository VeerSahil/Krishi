import 'package:cloud_firestore/cloud_firestore.dart';

enum SurveyStatus {
  pending,
  approved,
  inProgress,
  awaitingReview,
  done,
  completed,
  failed,
  rejected
}

class Survey {
  final String id;
  final String farmerId;
  final String farmerName;
  final String farmerEmail;
  final String farmName;
  final String farmAddress;
  final String contactPhone;
  final String assignedTeamName;
  final DateTime? measuredAt;
  final String city;
  final String soilType;
  final double? moisture;
  final double? temperature;
  final String? temperatureCategory;
  final String? temperatureSource;
  final bool isDemo;
  static const demoNotice =
      'Demo recommendation: temperature was simulated, not measured.';
  final String season;
  final int year;
  final SurveyStatus status;
  final double? predictedRainfall;
  final String? recommendedCrop;
  final double? nitrogen;
  final double? phosphorus;
  final double? potassium;
  final DateTime createdAt;
  final DateTime? completedAt;

  Survey({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.farmerEmail,
    this.farmName = 'My farm',
    this.farmAddress = '',
    this.contactPhone = '',
    this.assignedTeamName = '',
    this.measuredAt,
    required this.city,
    required this.soilType,
    this.moisture,
    this.temperature,
    this.temperatureCategory,
    this.temperatureSource,
    this.isDemo = false,
    required this.season,
    required this.year,
    required this.status,
    this.predictedRainfall,
    this.recommendedCrop,
    this.nitrogen,
    this.phosphorus,
    this.potassium,
    required this.createdAt,
    this.completedAt,
  });

  /// Maps backend status strings to [SurveyStatus].
  /// "completed" (backend) is treated as [SurveyStatus.done] for UI purposes.
  static SurveyStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'pending':
        return SurveyStatus.pending;
      case 'approved':
        return SurveyStatus.approved;
      case 'awaiting_review':
        return SurveyStatus.awaitingReview;
      case 'inProgress':
      case 'in_progress':
        return SurveyStatus.inProgress;
      case 'done':
      case 'completed': // backend sends "completed"
        return SurveyStatus.done;
      case 'failed':
        return SurveyStatus.failed;
      case 'rejected':
        return SurveyStatus.rejected;
      default:
        return SurveyStatus.pending;
    }
  }

  factory Survey.fromFirestore(DocumentSnapshot doc) {
    return Survey.fromData(doc.id, doc.data() as Map<String, dynamic>);
  }

  factory Survey.fromData(String id, Map<String, dynamic> data) {
    return Survey(
      id: id,
      // backend uses 'userId' not 'farmerId'
      farmerId: data['farmerId'] ?? data['userId'] ?? '',
      farmerName: data['farmerName'] ?? '',
      farmerEmail: data['farmerEmail'] ?? '',
      farmName: data['farmName'] ?? 'My farm',
      farmAddress: data['farmAddress'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      assignedTeamName: data['assignedTeamName'] ?? '',
      measuredAt: (data['measuredAt'] as Timestamp?)?.toDate(),
      city: data['city'] ?? '',
      soilType: data['soilType'] ?? data['soil_type'] ?? '',
      moisture: (data['moisture'] as num?)?.toDouble(),
      temperature: (data['temperature'] as num?)?.toDouble(),
      temperatureCategory: data['temperatureCategory'] as String?,
      temperatureSource: data['temperatureSource'] as String?,
      isDemo: data['temperatureSource'] == 'simulated' ||
          data['recommendationIsDemo'] == true,
      season: data['season'] ?? '',
      year: data['year'] ?? DateTime.now().year,
      status: _parseStatus(data['status'] as String?),
      // backend field: predicted_rainfall_mm
      predictedRainfall: (data['predicted_rainfall_mm'] as num?)?.toDouble() ??
          (data['predictedRainfall'] as num?)?.toDouble(),
      // backend field: recommended_crop
      recommendedCrop: data['recommended_crop'] as String? ??
          data['recommendedCrop'] as String?,
      nitrogen: (data['nitrogen'] as num?)?.toDouble(),
      phosphorus: (data['phosphorus'] as num?)?.toDouble(),
      potassium: (data['potassium'] as num?)?.toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Whether this survey has results ready to display.
  bool get isCompleted =>
      status == SurveyStatus.done || status == SurveyStatus.completed;

  Map<String, dynamic> toMap() => {
        'farmerId': farmerId,
        'farmerName': farmerName,
        'farmerEmail': farmerEmail,
        'city': city,
        'soilType': soilType,
        'moisture': moisture,
        'temperature': temperature,
        'temperatureCategory': temperatureCategory,
        'temperatureSource': temperatureSource,
        'recommendationIsDemo': isDemo,
        'season': season,
        'year': year,
        'status': status.name,
        'predicted_rainfall_mm': predictedRainfall,
        'recommended_crop': recommendedCrop,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
        'createdAt': FieldValue.serverTimestamp(),
        'completedAt': completedAt,
      };
}

extension SurveyStatusLabel on SurveyStatus {
  String get label {
    switch (this) {
      case SurveyStatus.pending:
        return 'Awaiting approval';
      case SurveyStatus.approved:
        return 'Visit approved';
      case SurveyStatus.inProgress:
        return 'Team visiting';
      case SurveyStatus.awaitingReview:
        return 'Admin reviewing report';
      case SurveyStatus.done:
      case SurveyStatus.completed:
        return 'Result released';
      case SurveyStatus.failed:
        return 'Needs attention';
      case SurveyStatus.rejected:
        return 'Rejected / cancelled';
    }
  }
}
