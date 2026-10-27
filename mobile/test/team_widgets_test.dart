import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishi/auth/login_screen.dart';
import 'package:krishi/main_team.dart';
import 'package:krishi/models/field_visit.dart';
import 'package:krishi/screens/team/team_home_screen.dart';
import 'package:krishi/screens/team/team_visit_screen.dart';
import 'package:krishi/services/team_api.dart';

class FakeTeam extends TeamRepository {
  String status = 'approved';
  int listCalls = 0;
  Map<String, dynamic>? submitted;
  bool simulated = false;
  final queries = <Map<String, String?>>[];

  FieldVisit get current => FieldVisit.fromJson({
        'surveyId': 'visit-1',
        'farmName': 'Pune farm',
        'farmerName': 'Test farmer',
        'farmAddress': 'Road 1, Pune',
        'city': 'Pune',
        'soilType': 'Black',
        'season': 'Monsoon',
        'year': 2026,
        'status': status,
        if (status == 'completed') 'recommended_crop': 'Wheat',
        if (simulated) ...{
          'temperatureSource': 'simulated',
          'temperatureCategory': 'high',
          'temperature': 32.4
        },
      });

  @override
  Future<VisitPage> visits({String? status, String? cursor}) async {
    listCalls++;
    queries.add({'status': status, 'cursor': cursor});
    return VisitPage([current], cursor == null ? 'next-page' : null);
  }

  @override
  Future<FieldVisit> visit(String id) async => current;
  @override
  Future<void> start(String id) async {
    status = 'in_progress';
  }

  @override
  Future<void> submit(String id, Map<String, dynamic> readings) async {
    submitted = readings;
    status = 'awaiting_review';
  }
}

Future<void> reveal(WidgetTester tester, Finder finder,
    {double delta = 250}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, delta,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'demo reports stay visibly labelled and switching to measured clears the synthetic value',
      (tester) async {
    final repository = FakeTeam()..simulated = true;
    await tester.pumpWidget(MaterialApp(
        home: TeamVisitScreen(
      visitId: 'visit-1',
      repository: repository,
      onSessionEnded: () {},
    )));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Demo recommendation: temperature was simulated, not measured.'),
        findsWidgets);
    await reveal(tester, find.byType(SwitchListTile));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('temperature')));
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('temperature')))
            .controller!
            .text,
        isEmpty);
  });

  testWidgets(
      'a generated demo report submits its source and category with the value',
      (tester) async {
    final repository = FakeTeam()..status = 'in_progress';
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TeamVisitScreen(
                                  visitId: 'visit-1',
                                  repository: repository,
                                  onSessionEnded: () {}))),
                      child: const Text('Open demo')),
                ))));
    await tester.tap(find.text('Open demo'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Generate demo temperature'));
    await tester.tap(find.text('Generate demo temperature'));
    await tester.pumpAndSettle();
    for (final entry in {
      'moisture': '45',
      'nitrogen': '400',
      'phosphorus': '200',
      'potassium': '150'
    }.entries) {
      await reveal(tester, find.byKey(ValueKey(entry.key)));
      await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Submit readings for review'));
    await tester.tap(find.text('Submit readings for review'));
    await tester.pumpAndSettle();
    expect(repository.submitted!['temperatureSource'], 'simulated');
    expect(repository.submitted!['temperatureCategory'], 'moderate');
    expect(repository.submitted!['temperature'],
        allOf(greaterThanOrEqualTo(20), lessThan(30)));
  });

  testWidgets('team login has its own identity and no public signup',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen(team: true)));
    expect(find.text('Krishi Team'), findsOneWidget);
    expect(find.text('Sign Up'), findsNothing);
    expect(find.text('Use the team account provided by your administrator.'),
        findsOneWidget);
  });

  testWidgets(
      'farmer, admin and missing profiles cannot enter the team workspace',
      (tester) async {
    final repository = FakeTeam();
    for (final role in ['farmer', 'admin', null]) {
      await tester.pumpWidget(MaterialApp(
          home: TeamAccountAccess(
        role: role,
        repository: repository,
        onSignOut: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Field-team account required'), findsOneWidget);
      expect(find.text('Your field visits'), findsNothing);
    }
    expect(repository.listCalls, 0);
  });

  testWidgets('team visit pages use the server cursor and filter selection',
      (tester) async {
    final repository = FakeTeam();
    await tester.pumpWidget(MaterialApp(
        home: TeamHomeScreen(repository: repository, onSignOut: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Pune farm'), findsOneWidget);
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(repository.queries.last['cursor'], 'next-page');
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin reviewing report').last);
    await tester.pumpAndSettle();
    expect(
        repository.queries.last, {'status': 'awaiting_review', 'cursor': null});
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('starting a visit keeps already-entered readings',
      (tester) async {
    final repository = FakeTeam();
    await tester.pumpWidget(MaterialApp(
        home: TeamVisitScreen(
      visitId: 'visit-1',
      repository: repository,
      onSessionEnded: () {},
    )));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('moisture')));
    await tester.enterText(find.byKey(const ValueKey('moisture')), '45');
    await reveal(tester, find.text('Start visit'), delta: -250);
    await tester.tap(find.text('Start visit'));
    await tester.pumpAndSettle();
    expect(repository.status, 'in_progress');
    await reveal(tester, find.text('Visit in progress'), delta: -250);
    expect(find.text('Visit in progress'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('moisture')));
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('moisture')))
            .controller!
            .text,
        '45');
    expect(find.text('Start visit'), findsNothing);
  });

  testWidgets(
      'invalid readings stay local and a valid report submits all five values',
      (tester) async {
    final repository = FakeTeam()..status = 'in_progress';
    bool? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => TeamVisitScreen(
                                    visitId: 'visit-1',
                                    repository: repository,
                                    onSessionEnded: () {})));
                      },
                      child: const Text('Open visit')),
                ))));
    await tester.tap(find.text('Open visit'));
    await tester.pumpAndSettle();
    for (final entry in {
      'moisture': '101',
      'temperature': '28',
      'nitrogen': '400',
      'phosphorus': '200',
      'potassium': '150'
    }.entries) {
      final input = find.byKey(ValueKey(entry.key));
      await reveal(tester, input);
      await tester.enterText(input, entry.value);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Submit readings for review'));
    await tester.tap(find.text('Submit readings for review'));
    await tester.pumpAndSettle();
    expect(repository.submitted, isNull);
    expect(find.text('Use a value from 0 to 100'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('moisture')), delta: -250);
    await tester.enterText(find.byKey(const ValueKey('moisture')), '45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Submit readings for review'));
    await tester.tap(find.text('Submit readings for review'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(repository.submitted, {
      'moisture': 45.0,
      'temperature': 28.0,
      'nitrogen': 400.0,
      'phosphorus': 200.0,
      'potassium': 150.0,
      'notes': null
    });
  });

  testWidgets('submitted and released reports cannot be edited again',
      (tester) async {
    final repository = FakeTeam();
    for (final status in ['awaiting_review', 'completed', 'rejected']) {
      repository.status = status;
      await tester.pumpWidget(MaterialApp(
          home: TeamVisitScreen(
        key: ValueKey(status),
        visitId: 'visit-1',
        repository: repository,
        onSessionEnded: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Submit readings for review'), findsNothing);
      if (status == 'completed') expect(find.text('Wheat'), findsOneWidget);
    }
  });
}
