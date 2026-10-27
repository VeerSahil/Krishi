import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    String role = 'farmer',
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _db.collection('users').doc(cred.user!.uid).set({
      'name': name,
      'email': email,
      'phone': phone,
      'role': 'farmer',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await cred.user!.updateDisplayName(name);
    return cred;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async => await _auth.signOut();

  Future<String?> getUserRole() async {
    if (currentUser == null) return null;
    final doc = await _db.collection('users').doc(currentUser!.uid).get();
    return doc.data()?['role'] as String?;
  }

  Future<Map<String, dynamic>?> getUserData() async {
    if (currentUser == null) return null;
    final doc = await _db.collection('users').doc(currentUser!.uid).get();
    return doc.data();
  }
}
