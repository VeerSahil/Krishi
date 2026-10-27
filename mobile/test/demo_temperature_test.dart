import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishi/models/survey.dart';
import 'package:krishi/services/demo_temperature.dart';

void main() {
  test(
      'generated demo temperatures respect both transitions and the upper limit',
      () {
    final random = Random(42);
    for (final category in DemoTemperature.categories) {
      final values = List.generate(
          1000, (_) => DemoTemperature.generate(category, random: random));
      expect(values.every((value) => DemoTemperature.matches(category, value)),
          isTrue);
      expect(values.toSet().length, greaterThan(1));
    }
    expect(DemoTemperature.matches('low', 20), isFalse);
    expect(DemoTemperature.matches('moderate', 20), isTrue);
    expect(DemoTemperature.matches('moderate', 30), isFalse);
    expect(DemoTemperature.matches('high', 30), isTrue);
    expect(DemoTemperature.matches('high', 35), isTrue);
    expect(DemoTemperature.matches('high', 35.1), isFalse);
  });

  test('farmer survey parsing retains simulated input provenance', () {
    final survey = Survey.fromData('demo-visit', {
      'status': 'completed',
      'temperature': 32.4,
      'temperatureSource': 'simulated',
      'temperatureCategory': 'high',
      'recommendationIsDemo': true,
      'recommended_crop': 'Wheat',
    });
    expect(survey.isDemo, isTrue);
    expect(survey.temperatureSource, 'simulated');
    expect(survey.temperatureCategory, 'high');
    expect(survey.recommendedCrop, 'Wheat');
    expect(Survey.fromData('legacy-visit', {'status': 'completed'}).isDemo,
        isFalse);
  });
}
