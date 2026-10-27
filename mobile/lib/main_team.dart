import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'screens/team/team_home_screen.dart';
import 'services/team_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const KrishiTeamApp());
}

class KrishiTeamApp extends StatelessWidget {
  const KrishiTeamApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Krishi Team',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF587345)),
            scaffoldBackgroundColor: const Color(0xFFF6F7F1)),
        home: const TeamAuthGate(),
      );
}

class TeamAuthGate extends StatelessWidget {
  const TeamAuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (!snapshot.hasData) return const LoginScreen(team: true);
          return FutureBuilder<String?>(
            future: AuthService().getUserRole(),
            builder: (context, role) {
              if (role.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              return TeamAccountAccess(
                role: role.hasError ? null : role.data,
                repository: TeamApi(),
                onSignOut: () => AuthService().signOut(),
              );
            },
          );
        },
      );
}

class TeamAccountAccess extends StatelessWidget {
  final String? role;
  final TeamRepository repository;
  final VoidCallback onSignOut;
  const TeamAccountAccess(
      {super.key,
      required this.role,
      required this.repository,
      required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    if (role == 'team') {
      return TeamHomeScreen(repository: repository, onSignOut: onSignOut);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Krishi Team')),
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.badge_outlined,
                    size: 58, color: Color(0xFF587345)),
                const SizedBox(height: 20),
                const Text('Field-team account required',
                    style: TextStyle(fontSize: 23),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                    role == null
                        ? 'Unable to verify your account profile. Sign in again or ask admin to check your team access.'
                        : 'Ask admin for a field-team account. Farmers use Krishi Farmer; administrators use the web dashboard.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                    onPressed: onSignOut, child: const Text('Sign out')),
              ]))),
    );
  }
}
