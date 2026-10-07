@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
set "TOKENSTEP_RESULT=%ERRORLEVEL%"
pause
exit /b %TOKENSTEP_RESULT%
