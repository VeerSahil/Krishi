export const DEMO_NOTICE = 'Demo recommendation: temperature was simulated, not measured.';
const ranges = { low: [150, 200], moderate: [200, 300], high: [300, 351] };

export function generateDemoTemperature(category, random = Math.random) {
  if (!Object.hasOwn(ranges, category)) throw new Error('Choose a demo temperature range.');
  const [lower, upper] = ranges[category];
  return (lower + Math.floor(random() * (upper - lower))) / 10;
}

export function matchesDemoTemperature(category, value) {
  if (!Number.isFinite(value)) return false;
  return category === 'low' ? value >= 15 && value < 20
    : category === 'moderate' ? value >= 20 && value < 30
      : category === 'high' && value >= 30 && value <= 35;
}
