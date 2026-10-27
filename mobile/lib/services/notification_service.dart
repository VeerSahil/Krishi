// Placeholder — wire up FCM or email notifications here.
// Currently handles the "admin marks done → farmer gets results" email trigger.

import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  /// Called by admin when marking a survey done.
  /// In production, replace with a Cloud Function or SMTP call.
  static Future<void> sendResultsNotification({
    required String farmerEmail,
    required String farmerName,
    required double rainfall,
    required String crop,
    required String city,
  }) async {
    // Log to Firestore — a Cloud Function can watch this collection
    // and send a real email via SendGrid / Nodemailer.
    await FirebaseFirestore.instance.collection('mail_queue').add({
      'to': farmerEmail,
      'farmerName': farmerName,
      'subject': 'Smart Agro AI – Your Survey Results',
      'body': 'Hi $farmerName,\n\nYour survey for $city is complete.\n\n'
          'Predicted Rainfall: ${rainfall.toStringAsFixed(1)} mm\n'
          'Recommended Crop: $crop\n\nThank you for using Smart Agro AI.',
      'sentAt': FieldValue.serverTimestamp(),
    });
  }
}
