@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "TOKENSTEP_RESULT=%ERRORLEVEL%"
pause
exit /b %TOKENSTEP_RESULT%
