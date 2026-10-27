import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth/login_screen.dart';
import 'auth/auth_service.dart';
import 'screens/farmer/home_screen.dart';
import 'package:flutter/services.dart';
import 'services/backend_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SmartAgroApp());
}

class SmartAgroApp extends StatelessWidget {
  const SmartAgroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Krishi Farmer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return FutureBuilder<String?>(
            future: AuthService().getUserRole(),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                            'Unable to load your account. Please sign in again.'),
                        TextButton(
                          onPressed: () => AuthService().signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (roleSnapshot.data == 'team') {
                return const TeamAccountNotice();
              }
              if (roleSnapshot.data == 'admin') {
                return const AdminAccountNotice();
              }
              if (roleSnapshot.data == 'farmer') {
                return const FarmerHomeScreen();
              }
              return Scaffold(
                body: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Your account profile needs setup. Please contact admin.'),
                  TextButton(
                      onPressed: () => AuthService().signOut(),
                      child: const Text('Sign out')),
                ])),
              );
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}

/// The customer APK deliberately contains no route into the admin workspace.
class AdminAccountNotice extends StatelessWidget {
  const AdminAccountNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final url =
        BackendClient.defaultBaseUrl.replaceAll(RegExp(r'/+$'), '') + '/admin/';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings_outlined,
                    size: 58, color: Color(0xFF235B44)),
                const SizedBox(height: 20),
                const Text('Your admin workspace is on the web.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24)),
                const SizedBox(height: 12),
                const Text(
                    'This phone app is for farmers. Monitor farmers and process surveys from the admin dashboard on your computer.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                SelectableText(url, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Admin dashboard link copied')));
                    }
                  },
                  icon: const Icon(Icons.copy, size: 17),
                  label: const Text('Copy dashboard link'),
                ),
                TextButton(
                    onPressed: () => AuthService().signOut(),
                    child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TeamAccountNotice extends StatelessWidget {
  const TeamAccountNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final url =
        BackendClient.defaultBaseUrl.replaceAll(RegExp(r'/+$'), '') + '/team/';
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.agriculture_outlined,
            size: 58, color: Color(0xFF235B44)),
        const SizedBox(height: 20),
        const Text('Use Krishi Team for your field visits.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 24)),
        const SizedBox(height: 14),
        const Text(
            'Install the separate Krishi Team app to open your assigned visits and submit readings. You can also use the team website below.',
            textAlign: TextAlign.center),
        const SizedBox(height: 22),
        SelectableText(url, textAlign: TextAlign.center),
        TextButton(
            onPressed: () => AuthService().signOut(),
            child: const Text('Sign out')),
      ]),
    ))));
  }
}
