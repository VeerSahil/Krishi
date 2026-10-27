import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';
import 'book_survey_screen.dart';
import 'my_surveys_screen.dart';
import 'reviews_screen.dart';
import 'chatbot_screen.dart';
import 'farm_monitoring_screen.dart';
import 'contact_admin_screen.dart';

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
            context, MaterialPageRoute(builder: (_) => const ReviewsScreen())),
      ),
      const FarmMonitoringScreen(),
      const MySurveysScreen(),
      const ChatbotScreen(),
      const ContactAdminScreen(),
    ];
    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.grass_outlined),
              selectedIcon: Icon(Icons.grass),
              label: 'My farm'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment),
              label: 'Surveys'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Assistant'),
          NavigationDestination(icon: Icon(Icons.support_agent), label: 'Help'),
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
      backgroundColor: const Color(0xFFF6F7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7F1),
        title: const Row(children: [
          Icon(Icons.eco_outlined, color: Color(0xFF235B44)),
          SizedBox(width: 8),
          Text('Krishi Farmer', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => AuthService().signOut()),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hello, ${name == null || name.isEmpty ? 'Farmer' : name}.',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            const Text('A little more clarity for your next harvest.',
                style: TextStyle(color: Color(0xFF76826F))),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF183D32),
                  borderRadius: BorderRadius.circular(22)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.grass_outlined,
                        color: Color(0xFFC0D59B), size: 34),
                    const SizedBox(height: 16),
                    const Text('Know your farm.\nPlan your crop.',
                        style: TextStyle(
                            fontSize: 27,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                    const SizedBox(height: 12),
                    const Text(
                        'Request a survey and get a crop recommendation for your farm.',
                        style: TextStyle(
                            color: Color(0xFFBBCDBB),
                            height: 1.6,
                            fontSize: 13)),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD9E7BA),
                          foregroundColor: const Color(0xFF183D32),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14)),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BookSurveyScreen())),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Book a farm survey'),
                    ),
                  ]),
            ),
            const SizedBox(height: 28),
            const Text('YOUR FARM WORKSPACE',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    color: Color(0xFF829272),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _ActionCard(
                icon: Icons.grass_outlined,
                title: 'Monitor my farm',
                subtitle: 'See recorded moisture, temperature and nutrients',
                onTap: onFarm),
            const SizedBox(height: 10),
            _ActionCard(
                icon: Icons.support_agent,
                title: 'Contact our admin team',
                subtitle: 'Ask about a visit, report or recommendation',
                onTap: onHelp),
            const SizedBox(height: 10),
            _ActionCard(
                icon: Icons.assignment_outlined,
                title: 'My surveys',
                subtitle: 'Track your requests and see crop results',
                onTap: onSurveys),
            const SizedBox(height: 10),
            _ActionCard(
                icon: Icons.chat_bubble_outline,
                title: 'Ask the farming assistant',
                subtitle: 'Questions about crops, soil or irrigation',
                onTap: onChat),
            const SizedBox(height: 10),
            _ActionCard(
                icon: Icons.star_outline,
                title: 'Your experience matters',
                subtitle: 'Read reviews or review a completed survey',
                onTap: onReviews),
            const SizedBox(height: 24),
            const Text(
                'Request → Approval → Field visit → Admin release → Your result',
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
          side: const BorderSide(color: Color(0xFFE4E8DC))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(icon, color: const Color(0xFF6C895A), size: 28),
        title: Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle,
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF8A9680)))),
        trailing:
            const Icon(Icons.arrow_forward, size: 17, color: Color(0xFF829272)),
        onTap: onTap,
      ),
    );
  }
}
