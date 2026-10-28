import 'services/app_language.dart';
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
  await AppLanguage.instance.load();
  runApp(SmartAgroApp());
}

class SmartAgroApp extends StatelessWidget {
  const SmartAgroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LanguageApp(
        create: (locale, builder) => MaterialApp(
              locale: locale,
              supportedLocales: LanguageApp.locales,
              localizationsDelegates: LanguageApp.delegates,
              builder: builder,
              title: 'Krishi Farmer',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Color(0xFF2E7D32),
                  brightness: Brightness.light,
                ),
                useMaterial3: true,
                fontFamily: 'Roboto',
              ),
              home: AuthGate(),
            ));
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
          return Scaffold(
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
                        Text(tr(
                            'Unable to load your account. Please sign in again.',
                            context: context)),
                        TextButton(
                          onPressed: () => AuthService().signOut(),
                          child: Text(tr('Sign out', context: context)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (roleSnapshot.data == 'team') {
                return TeamAccountNotice();
              }
              if (roleSnapshot.data == 'admin') {
                return AdminAccountNotice();
              }
              if (roleSnapshot.data == 'farmer') {
                return FarmerHomeScreen();
              }
              return Scaffold(
                body: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr(
                      'Your account profile needs setup. Please contact admin.',
                      context: context)),
                  TextButton(
                      onPressed: () => AuthService().signOut(),
                      child: Text(tr('Sign out', context: context))),
                ])),
              );
            },
          );
        }
        return LoginScreen();
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
            padding: EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.admin_panel_settings_outlined,
                    size: 58, color: Color(0xFF235B44)),
                SizedBox(height: 20),
                Text(
                    tr('Your admin workspace is on the web.', context: context),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24)),
                SizedBox(height: 12),
                Text(
                    tr('This phone app is for farmers. Monitor farmers and process surveys from the admin dashboard on your computer.',
                        context: context),
                    textAlign: TextAlign.center),
                SizedBox(height: 24),
                SelectableText(tr(url, context: context),
                    textAlign: TextAlign.center),
                SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr('Admin dashboard link copied',
                              context: context))));
                    }
                  },
                  icon: Icon(Icons.copy, size: 17),
                  label: Text(tr('Copy dashboard link', context: context)),
                ),
                TextButton(
                    onPressed: () => AuthService().signOut(),
                    child: Text(tr('Sign out', context: context))),
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
      padding: EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.agriculture_outlined, size: 58, color: Color(0xFF235B44)),
        SizedBox(height: 20),
        Text(tr('Use Krishi Team for your field visits.', context: context),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 24)),
        SizedBox(height: 14),
        Text(
            tr('Install the separate Krishi Team app to open your assigned visits and submit readings. You can also use the team website below.',
                context: context),
            textAlign: TextAlign.center),
        SizedBox(height: 22),
        SelectableText(tr(url, context: context), textAlign: TextAlign.center),
        TextButton(
            onPressed: () => AuthService().signOut(),
            child: Text(tr('Sign out', context: context))),
      ]),
    ))));
  }
}
