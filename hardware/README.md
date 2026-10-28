# Krishi Arduino field gadget

The supplied photo identifies an Uno-compatible board and a black capacitive
soil moisture probe marked v2.0 / HW-390. Its connector is labelled AOUT, VCC,
GND. The user confirmed the 16x2 LCD has GND, VCC, SDA, SCL pins, so its I2C
mode is enabled by default.
The blue LM393 potentiometer/comparator board is unnecessary for this capacitive
probe. The user confirmed that no separate temperature sensor is available.

Disconnect USB/power before changing wires. Use printed pin labels, not wire
colours. Place the Uno and bare modules on a dry, non-conductive surface.

| Capacitive probe pin | Arduino Uno pin |
| --- | --- |
| VCC | 5V |
| GND | GND |
| AOUT | A0 |

Only if the LCD has an I2C backpack with these four labelled pins:

| LCD backpack pin | Arduino Uno pin |
| --- | --- |
| VCC | 5V |
| GND | GND |
| SDA | A4 |
| SCL | A5 |

Both modules share 5V/GND through a breadboard rail or proper splitter; do not
force multiple jumper plugs into one Uno socket. Do not connect sensor power
to VIN. The black probe goes directly to the Uno, without the blue comparator.
If the LCD only has a 16-pin header, leave it disconnected for now: that needs
different wiring and code. Four wires in a photo do not establish pin order.

## Run

1. Open `krishi_field_monitor/krishi_field_monitor.ino` in Arduino IDE.
2. `USE_I2C_LCD` defaults to `1`. Install **hd44780 by Bill Perry** from Library Manager.
   The sketch discovers compatible backpack addresses automatically.
3. For a sensor-only test, set `USE_I2C_LCD` to `0`. No LCD library is needed
   in that mode.
4. Choose **Arduino Uno**, the actual connected COM port, then Upload.
5. Open Serial Monitor at **9600 baud**. Initial output has a raw ADC value
   (0–1023), `moisture_percent: null`, and `temperature_c: null`.

## Calibrate before using a percentage

1. With the sensing blade clean and dry in air, wait for the raw reading to
   settle and record the typical value as `DRY_RAW`.
2. Put only the sensing blade in water, below the upper electronics/connector
   and any marked insertion limit. Keep the upper circuit dry. Wait for a stable
   reading and record it as `WET_RAW`.
3. Replace the two `-1` constants in the sketch with your measured values and
   upload again. References must differ by at least 20 ADC counts; if they
   barely change, inspect wiring/probe before proceeding.
4. Insert the sensing blade into soil at a consistent depth, keep good contact,
   and wait for a stable reading. The result is clamped to 0–100.

This air/water calibration gives a **relative moisture index**. It is not a
validated measurement of volumetric soil water percentage. A comparable
physical moisture scale and suitable calibration are needed before using the
readings as validated crop-model inputs. The current crop dataset is a demo.

## Temperature and the apps

The `krishi_field_monitor` sketch reports temperature as unavailable. It is
the measurement-only version. At the user's request, `krishi_field_demo` adds
an explicitly labelled simulated temperature so the existing LM393 module can
be retained for the college demonstration.

### Current LM393 demo version

Open `krishi_field_demo/krishi_field_demo.ino`. Keep probe AOUT -> A0 and the
LCD's SDA -> A4 / SCL -> A5. The blue module can use VCC -> 5V, GND -> shared
GND, and **D0/DO -> D2**. Its A0/AO pin is unused; do not connect it to the
black probe's A0 signal. Disconnect USB before changing wires.

| Demo category | Generated temperature |
| --- | --- |
| Low | 15.0–19.9 °C |
| Moderate | 20.0–29.9 °C |
| High | 30.0–35.0 °C |

The program starts in manual moderate demo mode. Serial Monitor at 9600 baud:

- `F`: follow the wired module after a stable 500 ms signal. D2 HIGH selects
  high demo; D2 LOW selects moderate demo. These are software assumptions.
- `L`, `M`, `H`: manually select low, moderate or high demo and stop following
  the module. D0 has only two states, so it cannot distinguish all three bands.
- `R`: generate another value in the current band.
- `S`: pause/resume the automatic changes when copying a value into the team app.

By default the generated value moves up/down by 0.1–1.0 °C every two seconds,
remaining inside its selected band. It reflects at the edges instead of getting
stuck there. `S` pauses this movement; `R` explicitly resamples the full band.
Only the numeric value entered for a report is used by the backend; an already
submitted report is not changed by later Arduino display updates. LCD
temperature is marked `DEMO`; Serial includes `temperatureSource: simulated`
and its category. The module does **not** detect the physical 20/30 °C
boundaries. Its potentiometer is not calibrated in degrees. D2 uses a pull-up;
only enable F after wiring because a disconnected module is not automatically
detected and can read HIGH. Startup does not follow the module.

In the Team app or website, enable **Use simulated temperature (demo)**,
choose the matching category and copy the LCD value or press Generate. Enter
actual calibrated moisture and manual N/P/K. Switching back to measured mode
clears the generated temperature. The backend checks the selected band's
limits, uses that exact numeric value for prediction, and saves provenance in
both the report and private draft. Admin, farmer results, chatbot context and
optional email retain the demo label after publication. This is a demo
recommendation, not one based on a measured temperature.

This firmware displays local measurements on USB Serial and the optional LCD.
It does not upload automatically to Firebase or the team app. The current
workflow uses manual entry by the field team. N/P/K remain manually supplied.

## If the LCD is blank

Confirm an actual I2C backpack, labelled SDA/SCL, common ground and 5V. Adjust
the backpack contrast potentiometer gently. For further diagnosis use Arduino
IDE: File > Examples > hd44780 > ioClass > hd44780_I2Cexp > I2CexpDiag.
Do not use the blue sensor-board potentiometer to adjust LCD contrast.

## References

- [Official Uno pinout](https://docs.arduino.cc/resources/datasheets/A000066-datasheet.pdf)
- [Capacitive probe calibration reference](https://wiki.dfrobot.com/sen0193/docs/18037)
- [LCD library and examples](https://github.com/duinoWitchery/hd44780)

The DFRobot page is a reference for this class of analog capacitive probe;
the photographed HW-390 board is not established to be a DFRobot product.

## Verification

Both the serial-only and I2C LCD configurations compiled for `arduino:avr:uno`
using Arduino AVR core 1.8.7 and hd44780 1.3.2. The LCD build uses 7,890 bytes
of flash and 495 bytes of static RAM. That measurement-only version was not
uploaded. The current demo version was uploaded to Uno COM7 on 28 October
2026; its LCD initialized successfully and Serial verified generated low
19.6, high 33.1, module-follow moderate 27.0, and stable manual moderate 27.1.
The board was left in manual moderate demo mode. These were simulated
temperatures. Moisture was uncalibrated (`moisture: null`), so no physical
moisture percentage has been verified. The demo build uses 11,346 flash bytes
and 544 bytes of static RAM.

The subsequent changing-temperature build was uploaded and verified live:
28.4, 28.6, 28.6, 28.6, 28.0, 28.0, 27.1, 27.1, 28.1 °C (all simulated).
Automatic steps stayed within 1.0 °C; S pause/resume passed and automatic
changes were left enabled. Dry-air raw samples were 551–552 (median 551).
The user prefers soil references for final calibration, so the air baseline
does not substitute for a dry-soil reference. Soil calibration is complete only
after both user-confirmed dry-soil and wet-soil samples are captured.

## Existing Uno firmware recovered on 28 October 2026

The USB Uno was detected on COM7. A read-only avrdude flash backup was saved
under Git-ignored `.tool-state/hardware-backups/`. No replacement sketch was
uploaded during recovery; the labelled demo was uploaded subsequently. The
cached `sketch_apr27a` application image matched all 4,110
application bytes against the flash read from the board. Readable source was
recovered from its generated build-cache C++ file into
`recovered_original/recovered_original.ino` by removing IDE-generated line
markers and prototypes. This preserves the legacy logic as a reference.

That program alternates LCD pages and implements:

- `digitalRead(2) == LOW` -> `Temperature: NORMAL`.
- `digitalRead(2) == HIGH` -> `Temperature: HIGH`.
- `analogRead(A0)` mapped from fixed dry/wet references 600/300 to 0–100%.

It has no degrees-C temperature measurement and no temperature threshold in
degrees. An unconnected D2 input has no reliable state. The LM393 module's
output state alone cannot establish a real temperature with the available
hardware. An unconnected A0 can also float and produce a misleading moisture
percentage. Changing the display threshold cannot validate either reading.

Keep the working LCD wiring. With USB unplugged, connect the black probe
directly: VCC -> 5V, GND -> GND, AOUT -> A0, sharing power properly with the
LCD. Use one sensor output on A0 and leave the blue comparator module out of
this test. Once wired, the prepared `krishi_field_monitor` sketch reports
temperature unavailable and raw moisture until actual dry/wet calibration.

An additional simple serial-only `.ino` found in an unsaved IDE folder was
preserved separately in `recovered_serial_test/`; it is not the program that
produces the legacy LCD pages.


## Prepared percentage / degree-C display update

The current demo source uses provisional user-reported references: dry **air** approximately 525 and wet **soil** 255-272. `WET_RAW=264` is the rounded midpoint of that reported range; it is a derived provisional reference, not a measured median and not a dry-soil/wet-soil calibration. The displayed `Rel moist: ...%` maps air to 0 and that wet-soil reference to 100, clamped to 0-100. It is not volumetric soil-water content. Replace these references after a controlled calibration if using the gadget beyond a demonstration.

The second LCD line keeps `DEMO` and displays its simulated temperature with a custom degree glyph followed by C. No actual temperature sensor was added.

Double-click `update_arduino_display.bat` from the project root with the Uno on COM7 and all Serial Monitors closed. It compiles the exact source with the local hd44780 library, reads a unique backup of existing flash, uploads with verification enabled, and checks the serial startup for `LCD ready.` plus a report. A failed backup prevents uploading. The file does not update the phone apps or the backend.

This update has been prepared locally. In-session serial access was denied and the sandboxed AVR compiler reported an Illegal System DLL Relocation error; upload and physical LCD verification are pending execution on the user's PC. Earlier hardware verification results above refer to the earlier firmware, not this prepared update.
