@echo off
setlocal
cd /d "%~dp0"
echo Building the latest Krishi Farmer and Krishi Team apps...
echo Keep your existing apps installed. Sync any pending team reports before updating.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_android.ps1" -Audience both -SkipChecks
if errorlevel 1 (
  echo.
  echo BUILD FAILED. Do not reinstall an older APK from the output folder.
  echo Share the error shown above. Your existing installed apps have not been changed.
  pause
  exit /b 1
)
echo.
echo BUILD COMPLETE. Install these NEW APKs over your existing apps:
echo   mobile\build\apks\krishi-farmer.apk
echo   mobile\build\apks\krishi-team.apk
echo Choose Update on your phone. No uninstall is required when the signing key matches.
start "" "%~dp0mobile\build\apks"
pause
