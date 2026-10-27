// Arduino Uno + capacitive moisture probe (AOUT -> A0).
// Confirmed four-pin I2C LCD. Set to 0 for a sensor-only Serial test.
#ifndef USE_I2C_LCD
#define USE_I2C_LCD 1
#endif

#if USE_I2C_LCD
#include <Wire.h>
#include <hd44780.h>
#include <hd44780ioClass/hd44780_I2Cexp.h>
hd44780_I2Cexp lcd;  // Finds compatible I2C backpack address and pin mapping.
bool lcdReady = false;
#endif

// Replace -1 with YOUR stable dry and wet reference readings, then upload again.
// Leave at -1 for initial calibration: only the raw reading will be shown.
const int DRY_RAW = -1;
const int WET_RAW = -1;
const uint8_t MOISTURE_PIN = A0;

bool calibrated() {
  return DRY_RAW >= 0 && DRY_RAW <= 1023 &&
         WET_RAW >= 0 && WET_RAW <= 1023 && abs(DRY_RAW - WET_RAW) >= 20;
}

int readMoistureRaw() {
  unsigned long total = 0;
  for (uint8_t i = 0; i < 20; i++) {
    total += analogRead(MOISTURE_PIN);
    delay(5);
  }
  return (total + 10) / 20;
}

int relativeMoisture(int raw, int dry, int wet) {
  if (dry == wet) return -1;
  return constrain(((long)raw - dry) * 100L / (wet - dry), 0L, 100L);
}

void setup() {
  Serial.begin(9600);
  pinMode(MOISTURE_PIN, INPUT);
#if USE_I2C_LCD
  lcdReady = (lcd.begin(16, 2) == 0);
  if (!lcdReady) Serial.println(F("LCD not found. Serial readings will continue."));
#endif
  Serial.println(F("Krishi: capacitive moisture on A0. No temperature sensor configured."));
  if (!calibrated()) Serial.println(F("Record dry and wet raw values; update DRY_RAW and WET_RAW."));
  delay(1000);
}

void loop() {
  const int raw = readMoistureRaw();
  const bool ready = calibrated();
  // This is a relative two-point index, not validated volumetric water content.
  const int moisture = ready ? relativeMoisture(raw, DRY_RAW, WET_RAW) : -1;

  Serial.print(F("{\"moisture_raw\":"));
  Serial.print(raw);
  Serial.print(F(",\"moisture_percent\":"));
  if (ready) Serial.print(moisture);
  else Serial.print(F("null"));
  Serial.println(F(",\"temperature_c\":null,\"basis\":\"relative_two_point\"}"));

#if USE_I2C_LCD
  if (lcdReady) {
    lcd.setCursor(0, 0);
    lcd.print(F("                "));
    lcd.setCursor(0, 0);
    if (ready) {
      lcd.print(F("Moist idx: "));
      lcd.print(moisture);
      lcd.print('%');
    } else {
      lcd.print(F("Raw A0: "));
      lcd.print(raw);
    }
    lcd.setCursor(0, 1);
    lcd.print(F("Temp: no sensor "));
  }
#endif
  delay(1000);
}
