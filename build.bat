@echo off
setlocal
cd /d "%~dp0"
title Krishi Admin

if defined KRISHI_PYTHON (
    "%KRISHI_PYTHON%" "%~dp0scripts\start_admin.py" %*
    goto finished
)
if exist "%~dp0.venv\Scripts\python.exe" (
    "%~dp0.venv\Scripts\python.exe" "%~dp0scripts\start_admin.py" %*
    goto finished
)
if exist "%~dp0venv\Scripts\python.exe" (
    "%~dp0venv\Scripts\python.exe" "%~dp0scripts\start_admin.py" %*
    goto finished
)
where python >nul 2>nul
if not errorlevel 1 (
    python "%~dp0scripts\start_admin.py" %*
    goto finished
)
where py >nul 2>nul
if not errorlevel 1 (
    py -3 "%~dp0scripts\start_admin.py" %*
    goto finished
)
echo Python was not found. Install Python and the packages in requirements.txt.
exit /b 1

:finished
set "KRISHI_EXIT_CODE=%errorlevel%"
if not "%KRISHI_EXIT_CODE%"=="0" if "%~1"=="" pause
exit /b %KRISHI_EXIT_CODE%
