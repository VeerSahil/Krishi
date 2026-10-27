// Recovered from the Arduino build cache on 28 October 2026.
// Its cached compiled application matches the firmware read from Uno COM7.
// Legacy reference only: NORMAL/HIGH uses digital pin D2, not measured degrees C.

#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// I2C LCD address (0x27 most common, if blank then try 0x3F)
LiquidCrystal_I2C lcd(0x27, 16, 2);

// Pins
int tempPin = 2;     // OLD temp sensor DO pin
int moistPin = A0;   // Moisture sensor AOUT pin

void setup() {
  pinMode(tempPin, INPUT);

  lcd.init();
  lcd.backlight();

  lcd.setCursor(0, 0);
  lcd.print("KRISHI SYSTEM");
  lcd.setCursor(0, 1);
  lcd.print("Starting...");
  delay(2000);
  lcd.clear();
}

void loop() {

  // =========================
  // 1) SHOW TEMPERATURE (5 sec)
  // LOW = NORMAL
  // HIGH = HIGH
  // =========================

  for (int i = 0; i < 5; i++) {
    int tempVal = digitalRead(tempPin);

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Temperature:");

    lcd.setCursor(0, 1);

    if (tempVal == LOW) {
      lcd.print("NORMAL");
    } else {
      lcd.print("HIGH");
    }

    delay(1000);
  }


  // =========================
  // 2) SHOW MOISTURE (5 sec)
  // =========================

  for (int i = 0; i < 5; i++) {

    int raw = analogRead(moistPin);

    // adjust values after testing
    int moisture = map(raw, 600, 300, 0, 100);
    moisture = constrain(moisture, 0, 100);

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Soil Moisture:");

    lcd.setCursor(0, 1);
    lcd.print(moisture);
    lcd.print("%");

    delay(1000);
  }
}
