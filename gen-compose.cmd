@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gen-compose.ps1" %*
exit /b %ERRORLEVEL%
