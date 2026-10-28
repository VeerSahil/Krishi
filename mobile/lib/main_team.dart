import 'services/app_language.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'screens/team/team_home_screen.dart';
import 'services/team_api.dart';
import 'services/offline_team.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppLanguage.instance.load();
  runApp(KrishiTeamApp());
}

class KrishiTeamApp extends StatelessWidget {
  const KrishiTeamApp({super.key});

  @override
  Widget build(BuildContext context) => LanguageApp(
      create: (locale, builder) => MaterialApp(
            locale: locale,
            supportedLocales: LanguageApp.locales,
            localizationsDelegates: LanguageApp.delegates,
            builder: builder,
            title: 'Krishi Team',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF587345)),
                scaffoldBackgroundColor: Color(0xFFF6F7F1)),
            home: TeamAuthGate(),
          ));
}

class TeamAuthGate extends StatefulWidget {
  const TeamAuthGate({super.key});
  @override
  State<TeamAuthGate> createState() => _TeamAuthGateState();
}

class _TeamAuthGateState extends State<TeamAuthGate> {
  OfflineTeamRepository? _repository;
  String? _uid;
  TeamRepository repositoryFor(String uid) {
    if (_uid != uid) {
      _repository?.dispose();
      _uid = uid;
      _repository = OfflineTeamRepository(remote: TeamApi(), uid: uid);
    }
    return _repository!;
  }

  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!snapshot.hasData) return LoginScreen(team: true);
          return FutureBuilder<String?>(
            future: AuthService().getUserRole(),
            builder: (context, role) {
              if (role.connectionState == ConnectionState.waiting) {
                return Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              return TeamAccountAccess(
                role: role.hasError ? null : role.data,
                repository:
                    repositoryFor(FirebaseAuth.instance.currentUser!.uid),
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
      appBar: AppBar(title: Text(tr('Krishi Team', context: context))),
      body: Center(
          child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.badge_outlined, size: 58, color: Color(0xFF587345)),
                SizedBox(height: 20),
                Text(tr('Field-team account required', context: context),
                    style: TextStyle(fontSize: 23),
                    textAlign: TextAlign.center),
                SizedBox(height: 12),
                Text(
                    tr(
                        role == null
                            ? 'Unable to verify your account profile. Sign in again or ask admin to check your team access.'
                            : 'Ask admin for a field-team account. Farmers use Krishi Farmer; administrators use the web dashboard.',
                        context: context),
                    textAlign: TextAlign.center),
                SizedBox(height: 20),
                FilledButton(
                    onPressed: onSignOut,
                    child: Text(tr('Sign out', context: context))),
              ]))),
    );
  }
}
