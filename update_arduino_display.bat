@echo off
setlocal
cd /d "%~dp0"
echo Krishi LCD display update - Arduino Uno on COM7
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update_arduino.ps1"
if errorlevel 1 (
  echo.
  echo UPDATE FAILED. Please share the error above; do not assume the board was updated.
  pause
  exit /b 1
)
echo.
echo Check the physical LCD before copying readings to Krishi Team.
pause
