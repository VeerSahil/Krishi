// DEMO ONLY: LM393 D0 -> D2 selects synthetic temperature bands.
// This module does not measure degrees C. Every temperature is marked simulated.
#ifndef USE_I2C_LCD
#define USE_I2C_LCD 1
#endif
#if USE_I2C_LCD
#include <Wire.h>
#include <hd44780.h>
#include <hd44780ioClass/hd44780_I2Cexp.h>
hd44780_I2Cexp lcd;
bool lcdReady = false;
#endif

const uint8_t MOISTURE_PIN = A0;
const uint8_t MODULE_PIN = 2;
// Replace only after recording your probe's actual dry/wet readings.
const int DRY_RAW = -1;
const int WET_RAW = -1;

enum DemoBand { DEMO_LOW, DEMO_MODERATE, DEMO_HIGH };
DemoBand band = DEMO_MODERATE;
int temperatureTenths = 250;
bool followModule = false;  // Explicit F command enables it after wiring.
int lastSignal = HIGH;
unsigned long signalChangedAt = 0;
unsigned long lastReportAt = 0;
unsigned long lastTemperatureChangeAt = 0;
bool holdTemperature = false;
const unsigned long TEMPERATURE_CHANGE_MS = 2000;

const char* bandName() {
  return band == DEMO_LOW ? "low" : band == DEMO_HIGH ? "high" : "moderate";
}

void chooseBand(DemoBand next, bool resample = false) {
  if (next == band && !resample) return;
  band = next;
  // random's upper bound is exclusive.
  if (band == DEMO_LOW) temperatureTenths = random(150, 200);
  else if (band == DEMO_HIGH) temperatureTenths = random(300, 351);
  else temperatureTenths = random(200, 300);
  lastTemperatureChangeAt = millis();
}

void driftTemperature() {
  const int lower = band == DEMO_LOW ? 150 : band == DEMO_HIGH ? 300 : 200;
  const int upper = band == DEMO_LOW ? 199 : band == DEMO_HIGH ? 350 : 299;
  const int step = random(1, 11) * (random(0, 2) ? 1 : -1);
  int next = temperatureTenths + step;
  // Reflect at the band's edge so the value does not stick at a limit.
  if (next < lower) next = lower + (lower - next);
  if (next > upper) next = upper - (next - upper);
  if (next == temperatureTenths) next += next == upper ? -1 : 1;
  temperatureTenths = constrain(next, lower, upper);
  lastTemperatureChangeAt = millis();
}

int readMoisture() {
  unsigned long sum = 0;
  for (uint8_t i = 0; i < 20; ++i) { sum += analogRead(MOISTURE_PIN); delay(5); }
  return (sum + 10) / 20;
}

bool moistureCalibrated() {
  return DRY_RAW >= 0 && DRY_RAW <= 1023 && WET_RAW >= 0 && WET_RAW <= 1023 &&
         abs(DRY_RAW - WET_RAW) >= 20;
}

int moistureIndex(int raw, int dry, int wet) {
  if (dry == wet) return -1;
  return constrain(((long)raw - dry) * 100L / (wet - dry), 0L, 100L);
}

void handleCommands() {
  while (Serial.available()) {
    char command = Serial.read();
    if (command >= 'a' && command <= 'z') command -= 'a' - 'A';
    if (command == 'L' || command == 'M' || command == 'H') {
      followModule = false;
      chooseBand(command == 'L' ? DEMO_LOW : command == 'H' ? DEMO_HIGH : DEMO_MODERATE, true);
    } else if (command == 'F') {
      followModule = true;
      lastSignal = digitalRead(MODULE_PIN);
      signalChangedAt = millis();
    } else if (command == 'R') chooseBand(band, true);
    else if (command == 'S') {
      holdTemperature = !holdTemperature;
      lastTemperatureChangeAt = millis();
    }
  }
}

void setup() {
  Serial.begin(9600);
  pinMode(MOISTURE_PIN, INPUT);
  pinMode(MODULE_PIN, INPUT_PULLUP);
  randomSeed(analogRead(A3) ^ micros());
  chooseBand(DEMO_MODERATE, true);
  Serial.println(F("Starting Krishi DEMO. Temperatures are simulated."));
#if USE_I2C_LCD
  Wire.begin();
  Wire.setWireTimeout(25000, true);
  lcdReady = lcd.begin(16, 2) == 0;
  Serial.println(lcdReady ? F("LCD ready.") : F("LCD unavailable; Serial demo continues."));
#endif
  Serial.println(F("DEMO: generated temperature, NOT a temperature measurement."));
  Serial.println(F("Commands: L=low, M=moderate, H=high, R=resample, F=follow wired LM393 D0 on D2."));
  Serial.println(F("Temperature drifts 0.1-1.0 C every 2 seconds. S pauses/resumes drift for copying."));
  Serial.println(F("F: signal HIGH -> demo 30-35; LOW -> demo 20-29.9. Low demo is selected with L."));
  Serial.println(F("Startup is manual moderate demo. Wire probe AOUT to A0; calibrate moisture separately."));
}

void loop() {
  handleCommands();
  if (followModule) {
    const int signal = digitalRead(MODULE_PIN);
    if (signal != lastSignal) { lastSignal = signal; signalChangedAt = millis(); }
    if (millis() - signalChangedAt >= 500) {
      chooseBand(signal == HIGH ? DEMO_HIGH : DEMO_MODERATE);
    }
  }
  if (!holdTemperature && millis() - lastTemperatureChangeAt >= TEMPERATURE_CHANGE_MS) {
    driftTemperature();
  }
  if (millis() - lastReportAt < 1000) return;
  lastReportAt = millis();
  const int raw = readMoisture();
  const int moisture = moistureCalibrated() ? moistureIndex(raw, DRY_RAW, WET_RAW) : -1;
  const float temperature = temperatureTenths / 10.0f;
  Serial.print(F("{\"moisture_raw\":")); Serial.print(raw);
  Serial.print(F(",\"moisture\":"));
  if (moisture >= 0) Serial.print(moisture); else Serial.print(F("null"));
  Serial.print(F(",\"temperature\":")); Serial.print(temperature, 1);
  Serial.print(F(",\"temperatureSource\":\"simulated\",\"temperatureCategory\":\""));
  Serial.print(bandName());
  Serial.print(F("\",\"temperatureChanging\":")); Serial.print(holdTemperature ? F("false") : F("true"));
  Serial.print(F(",\"mode\":\"")); Serial.print(followModule ? F("module_demo") : F("manual_demo"));
  Serial.println(F("\"}"));
#if USE_I2C_LCD
  if (lcdReady) {
    lcd.setCursor(0, 0); lcd.print(F("                ")); lcd.setCursor(0, 0);
    if (moisture >= 0) { lcd.print(F("Moist idx: ")); lcd.print(moisture); lcd.print('%'); }
    else { lcd.print(F("Raw A0: ")); lcd.print(raw); }
    lcd.setCursor(0, 1); lcd.print(F("                ")); lcd.setCursor(0, 1);
    lcd.print(F("DEMO ")); lcd.print(band == DEMO_LOW ? 'L' : band == DEMO_HIGH ? 'H' : 'M');
    lcd.print(' '); lcd.print(temperature, 1); lcd.print('C');
  }
#endif
}
