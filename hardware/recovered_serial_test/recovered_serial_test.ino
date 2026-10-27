// Recovered from an unsaved local IDE file. This is NOT established as the firmware running on the board.
void setup() {
  Serial.begin(9600);
}

void loop() {
  int reading = analogRead(A0);
  Serial.print("Moisture raw reading: ");
  Serial.println(reading);
  delay(1000);
}