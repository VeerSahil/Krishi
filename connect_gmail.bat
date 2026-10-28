@echo off
setlocal
cd /d "%~dp0"
title Connect Krishi Gmail Sender
echo Krishi Gmail Sender - one-time connection
echo No email will be sent by this setup.
echo.
set "KRISHI_PYTHON=python"
if exist "%USERPROFILE%\anaconda3\python.exe" set "KRISHI_PYTHON=%USERPROFILE%\anaconda3\python.exe"
if not exist ".tool-state\gmail\client_secret.json" (
  echo The Desktop OAuth client JSON is missing from .tool-state\gmail\client_secret.json
  pause
  exit /b 1
)
if not exist ".tool-state\gmail\venv\Scripts\python.exe" (
  echo Preparing the private setup environment...
  "%KRISHI_PYTHON%" -m venv --system-site-packages ".tool-state\gmail\venv"
  if errorlevel 1 goto failed
)
".tool-state\gmail\venv\Scripts\python.exe" -c "import google_auth_oauthlib" >nul 2>&1
if errorlevel 1 (
  echo Installing Google's OAuth setup library...
  ".tool-state\gmail\venv\Scripts\python.exe" -m pip install --disable-pip-version-check --no-input -r requirements-gmail-setup.txt
  if errorlevel 1 goto failed
)
echo Complete Google sign-in in your browser using the selected college account.
".tool-state\gmail\venv\Scripts\python.exe" scripts\connect_gmail.py --connect
if errorlevel 1 goto failed
echo.
echo Connection completed. Return to the chat and say done.
pause
exit /b 0
:failed
echo.
echo Setup could not finish. Share the error text, not any credentials.
pause
exit /b 1