import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'private_store.dart';
import 'translations.dart';

class AppLanguage extends ValueNotifier<String> {
  AppLanguage._() : super('en');
  static final instance = AppLanguage._();
  final LocalStore store = PrivateStore();
  bool preferenceSaved = true;
  Future<void> load() async {
    try {
      final saved = await store.read('language');
      if (['en', 'hi', 'mr'].contains(saved)) value = saved!;
    } catch (_) {/* New install or non-Android test host. */}
  }

  Future<void> select(String code) async {
    try {
      await store.write('language', code);
      preferenceSaved = true;
    } catch (_) {
      preferenceSaved = false;
    }
    value = code;
  }
}

String tr(String text, {BuildContext? context}) {
  if (context != null) Localizations.localeOf(context);
  final lang = AppLanguage.instance.value;
  if (lang == 'en') return text;
  final pair = translations[text];
  if (pair != null) return pair[lang == 'hi' ? 0 : 1];
  for (final key in ['Page ', 'Reports waiting to sync: ', 'Hello, ']) {
    if (text.startsWith(key)) return tr(key) + text.substring(key.length);
  }
  final seasonWords = ['Summer', 'Monsoon', 'Winter'];
  for (final word in seasonWords) {
    if (text.startsWith('$word '))
      return tr(word) + text.substring(word.length);
  }
  if (text.startsWith('Use a value from '))
    return lang == 'hi'
        ? 'मान की सीमा: ' + text.substring(17)
        : 'मूल्याची मर्यादा: ' + text.substring(17);
  return text;
}

class LanguageApp extends StatelessWidget {
  final Widget Function(Locale locale, TransitionBuilder builder) create;
  const LanguageApp({super.key, required this.create});
  static const delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate
  ];
  static const locales = [Locale('en'), Locale('hi'), Locale('mr')];
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
      valueListenable: AppLanguage.instance,
      builder: (context, code, _) => create(
          Locale(code),
          (context, child) => Column(children: [
                Material(
                    color: const Color(0xFFF6F7F1),
                    child: SafeArea(
                        bottom: false,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              const Icon(Icons.translate, size: 18),
                              const SizedBox(width: 10),
                              Text(tr(AppLanguage.instance.preferenceSaved
                                  ? 'Language'
                                  : 'Language (session only)')),
                              const Spacer(),
                              for (final entry in const {
                                'en': 'English',
                                'hi': 'हिन्दी',
                                'mr': 'मराठी'
                              }.entries)
                                TextButton(
                                  style: TextButton.styleFrom(
                                      backgroundColor: code == entry.key
                                          ? const Color(0xFFD9E7BA)
                                          : null,
                                      minimumSize: const Size(44, 44),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8)),
                                  onPressed: () async {
                                    try {
                                      await AppLanguage.instance
                                          .select(entry.key);
                                    } catch (_) {
                                      AppLanguage.instance.value = entry.key;
                                    }
                                  },
                                  child: Text(entry.value),
                                ),
                            ])))),
                Expanded(child: child ?? const SizedBox.shrink()),
              ])));
}
