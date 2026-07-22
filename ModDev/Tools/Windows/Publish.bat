@echo off
setlocal
title Hoenn Reloaded - Publish
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RepositoryTool.ps1" -Action Publish -Kind "%~1" -GameRoot "%~dp0..\..\.."
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Publisher failed with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
