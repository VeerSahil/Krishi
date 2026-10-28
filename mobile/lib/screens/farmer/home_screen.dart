import '../../services/app_language.dart';
import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';
import 'book_survey_screen.dart';
import 'my_surveys_screen.dart';
import 'reviews_screen.dart';
import 'chatbot_screen.dart';
import 'farm_monitoring_screen.dart';
import 'contact_admin_screen.dart';
import 'farm_evidence_screen.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeTab(
        onFarm: () => setState(() => _selectedIndex = 1),
        onSurveys: () => setState(() => _selectedIndex = 2),
        onChat: () => setState(() => _selectedIndex = 3),
        onHelp: () => setState(() => _selectedIndex = 4),
        onReviews: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ReviewsScreen())),
      ),
      FarmMonitoringScreen(),
      MySurveysScreen(),
      ChatbotScreen(),
      ContactAdminScreen(),
    ];
    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: tr('Home', context: context)),
          NavigationDestination(
              icon: Icon(Icons.grass_outlined),
              selectedIcon: Icon(Icons.grass),
              label: tr('My farm', context: context)),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment),
              label: tr('Surveys', context: context)),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: tr('Assistant', context: context)),
          NavigationDestination(
              icon: Icon(Icons.support_agent),
              label: tr('Help', context: context)),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final VoidCallback onSurveys;
  final VoidCallback onReviews;
  final VoidCallback onChat;
  final VoidCallback onFarm;
  final VoidCallback onHelp;
  const _HomeTab(
      {required this.onSurveys,
      required this.onReviews,
      required this.onChat,
      required this.onFarm,
      required this.onHelp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = AuthService().currentUser?.displayName;
    return Scaffold(
      backgroundColor: Color(0xFFF6F7F1),
      appBar: AppBar(
        backgroundColor: Color(0xFFF6F7F1),
        title: Row(children: [
          Icon(Icons.eco_outlined, color: Color(0xFF235B44)),
          SizedBox(width: 8),
          Text(tr('Krishi Farmer', context: context),
              style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
              tooltip: tr('Sign out', context: context),
              icon: Icon(Icons.logout),
              onPressed: () => AuthService().signOut()),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                tr('Hello, ${name == null || name.isEmpty ? tr('Farmer', context: context) : name}.',
                    context: context),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 7),
            Text(
                tr('A little more clarity for your next harvest.',
                    context: context),
                style: TextStyle(color: Color(0xFF76826F))),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: Color(0xFF183D32),
                  borderRadius: BorderRadius.circular(22)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.grass_outlined,
                        color: Color(0xFFC0D59B), size: 34),
                    SizedBox(height: 16),
                    Text(
                        tr('Know your farm.\nPlan your crop.',
                            context: context),
                        style: TextStyle(
                            fontSize: 27,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                    SizedBox(height: 12),
                    Text(
                        tr('Request a survey and get a crop recommendation for your farm.',
                            context: context),
                        style: TextStyle(
                            color: Color(0xFFBBCDBB),
                            height: 1.6,
                            fontSize: 13)),
                    SizedBox(height: 22),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Color(0xFFD9E7BA),
                          foregroundColor: Color(0xFF183D32),
                          padding: EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14)),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BookSurveyScreen())),
                      icon: Icon(Icons.add, size: 18),
                      label: Text(tr('Book a farm survey', context: context)),
                    ),
                  ]),
            ),
            SizedBox(height: 28),
            Text(tr('YOUR FARM WORKSPACE', context: context),
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    color: Color(0xFF829272),
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            _ActionCard(
                icon: Icons.fact_check_outlined,
                title: 'Crop plan & farm evidence',
                subtitle:
                    'Check your chosen crop and view dated survey records',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => FarmEvidenceScreen()))),
            SizedBox(height: 10),
            _ActionCard(
                icon: Icons.grass_outlined,
                title: 'Monitor my farm',
                subtitle: 'See recorded moisture, temperature and nutrients',
                onTap: onFarm),
            SizedBox(height: 10),
            _ActionCard(
                icon: Icons.support_agent,
                title: 'Contact our admin team',
                subtitle: 'Ask about a visit, report or recommendation',
                onTap: onHelp),
            SizedBox(height: 10),
            _ActionCard(
                icon: Icons.assignment_outlined,
                title: 'My surveys',
                subtitle: 'Track your requests and see crop results',
                onTap: onSurveys),
            SizedBox(height: 10),
            _ActionCard(
                icon: Icons.chat_bubble_outline,
                title: 'Ask the farming assistant',
                subtitle: 'Questions about crops, soil or irrigation',
                onTap: onChat),
            SizedBox(height: 10),
            _ActionCard(
                icon: Icons.star_outline,
                title: 'Your experience matters',
                subtitle: 'Read reviews or review a completed survey',
                onTap: onReviews),
            SizedBox(height: 24),
            Text(
                tr('Request → Approval → Field visit → Admin release → Your result',
                    context: context),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, color: Color(0xFF8B9782), height: 1.7)),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: Color(0xFFE4E8DC))),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(icon, color: Color(0xFF6C895A), size: 28),
        title: Text(tr(title, context: context),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(tr(subtitle, context: context),
                style: TextStyle(fontSize: 11, color: Color(0xFF8A9680)))),
        trailing: Icon(Icons.arrow_forward, size: 17, color: Color(0xFF829272)),
        onTap: onTap,
      ),
    );
  }
}
