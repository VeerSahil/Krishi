import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishi/screens/farmer/chatbot_screen.dart';
import 'package:krishi/main.dart';

void main() {
  testWidgets('assistant renders without Firebase before a message is sent',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatbotScreen()));
    expect(find.text('Agro Assistant'), findsOneWidget);
    expect(find.text('Ask me anything about farming!'), findsOneWidget);
  });

  testWidgets(
      'administrator accounts are directed to the separate web workspace',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminAccountNotice()));
    expect(find.text('Your admin workspace is on the web.'), findsOneWidget);
    expect(find.text('Copy dashboard link'), findsOneWidget);
  });
}
