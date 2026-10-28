import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishi/services/app_language.dart';
import 'package:krishi/services/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? saved;
  setUp(() {
    AppLanguage.instance.value = 'en';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('krishi/private_store'),
            (call) async {
      if (call.method == 'write') {
        saved = call.arguments['value'];
        return null;
      }
      return saved;
    });
  });
  testWidgets('language picker changes an open route and persists selection',
      (tester) async {
    await tester.pumpWidget(LanguageApp(
        create: (locale, builder) => MaterialApp(
            locale: locale,
            supportedLocales: LanguageApp.locales,
            localizationsDelegates: LanguageApp.delegates,
            builder: builder,
            home: const TestPage())));
    expect(find.text('Check my crop plan'), findsOneWidget);
    await tester.tap(find.text('मराठी'));
    await tester.pumpAndSettle();
    expect(find.text('माझे पीक नियोजन तपासा'), findsOneWidget);
    expect(saved, 'mr');
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect(find.text('मेरी फसल योजना जांचें'), findsOneWidget);
    expect(saved, 'hi');
  });
  test('safety notices and offline controls exist in both languages', () {
    for (final key in [
      'Historical rainfall is not a live weather forecast.',
      'Save draft on phone',
      'Demo recommendation: temperature was simulated, not measured.',
      'The crop model uses demonstration data and has not been validated for farm decisions.'
    ]) {
      expect(translations[key]!.length, 2);
      expect(translations[key]!.every((v) => v.isNotEmpty && v != key), isTrue);
    }
  });
}

class TestPage extends StatelessWidget {
  const TestPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(tr('Check my crop plan', context: context)));
}
