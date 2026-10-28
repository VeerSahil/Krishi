import 'app_language.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/survey.dart';
import '../models/review.dart';
import 'backend_client.dart';

class ApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static final BackendClient _backend = BackendClient(
    tokenProvider: (forceRefresh) async =>
        FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh),
  );

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw const ApiException('Please sign in first.');
    return user.uid;
  }

  Future<String> bookSurvey({
    required String city,
    required String soilType,
    required String season,
    required int year,
    required String farmerName,
    required String farmerEmail,
    required String farmName,
    required String farmAddress,
    String? contactPhone,
  }) async {
    final data = await _backend.post('/survey/book', {
      'farmName': farmName,
      'farmAddress': farmAddress,
      'contactPhone': contactPhone,
      'city': city,
      'soilType': soilType,
      'season': season,
      'year': year,
      'farmerName': farmerName,
      'farmerEmail': farmerEmail,
    });
    final id = data['surveyId'];
    if (id is! String) {
      throw const ApiException('The server did not return a survey ID.');
    }
    return id;
  }

  Future<void> updateSurveyMeasurements(
    String surveyId, {
    required double moisture,
    required String temperatureCategory,
  }) =>
      markSurveyDone(surveyId,
          moisture: moisture, temperatureCategory: temperatureCategory);

  Stream<List<Survey>> farmerSurveysStream() => _db
      .collection('farm_inputs')
      .where('userId', isEqualTo: _uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Survey.fromFirestore).toList());

  Stream<List<Survey>> allSurveysStream() => _db
      .collection('farm_inputs')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Survey.fromFirestore).toList());

  Stream<List<Survey>> pendingSurveysStream() => _db
      .collection('farm_inputs')
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Survey.fromFirestore).toList());

  Future<void> markSurveyDone(
    String surveyId, {
    required double moisture,
    required String temperatureCategory,
  }) async {
    // Retained only for old, unreachable mobile-admin widgets.
    throw const ApiException(
        'Use the admin web dashboard to approve visits and the field-team workspace to submit readings.');
  }

  Future<void> submitReview({
    required String surveyId,
    required int rating,
    required String comment,
    required String farmerName,
  }) async {
    // Ownership, completed status and duplicate checks happen on the backend.
    await _backend.post('/review/add',
        {'surveyId': surveyId, 'rating': rating, 'comment': comment});
  }

  Stream<List<Review>> reviewsStream() => _db
      .collection('reviews')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Review.fromFirestore).toList());

  Stream<List<Review>> farmerReviewsStream() => _db
      .collection('reviews')
      .where('farmerId', isEqualTo: _uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Review.fromFirestore).toList());

  Future<String> sendChatMessage(String message) async {
    final data = await _backend.post(
        '/chat', {'message': message, 'language': AppLanguage.instance.value});
    final response = data['response'];
    if (response is! String || response.trim().isEmpty) {
      throw const ApiException('The assistant did not return a response.');
    }
    return response;
  }

  Future<void> contactAdmin(
      {required String subject,
      required String message,
      String? surveyId}) async {
    await _backend.post('/support/messages',
        {'subject': subject, 'message': message, 'surveyId': surveyId});
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> supportMessagesStream() => _db
      .collection('support_threads')
      .where('userId', isEqualTo: _uid)
      .orderBy('createdAt', descending: true)
      .snapshots();
}
