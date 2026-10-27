import 'dart:math';

class DemoTemperature {
  static const categories = ['low', 'moderate', 'high'];

  static double generate(String category, {Random? random}) {
    final lower = category == 'low'
        ? 150
        : category == 'moderate'
            ? 200
            : 300;
    final upper = category == 'low'
        ? 200
        : category == 'moderate'
            ? 300
            : 351;
    if (!categories.contains(category)) throw ArgumentError.value(category);
    return (lower + (random ?? Random()).nextInt(upper - lower)) / 10;
  }

  static bool matches(String category, double value) {
    if (!value.isFinite) return false;
    return category == 'low'
        ? value >= 15 && value < 20
        : category == 'moderate'
            ? value >= 20 && value < 30
            : category == 'high' && value >= 30 && value <= 35;
  }

  static const notice =
      'Demo recommendation: temperature was simulated, not measured.';
}
