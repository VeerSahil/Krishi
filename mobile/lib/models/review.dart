import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  final String id;
  final String farmerId;
  final String farmerName;
  final String surveyId;
  final int rating;
  final String comment;
  final DateTime createdAt;

  Review({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.surveyId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory Review.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Review(
      id: doc.id,
      farmerId: data['farmerId'] ?? data['userId'] ?? '',
      farmerName: data['farmerName'] ?? '',
      surveyId: data['surveyId'] ?? '',
      rating: data['rating'] ?? 5,
      comment: data['comment'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'farmerId': farmerId,
        'farmerName': farmerName,
        'surveyId': surveyId,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
