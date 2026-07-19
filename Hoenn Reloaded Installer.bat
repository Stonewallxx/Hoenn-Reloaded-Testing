@echo off
setlocal
title Hoenn Reloaded Installer
color 0A

set "INSTALLER_ROOT=%~dp0"
set "INSTALLER_ENGINE=%INSTALLER_ROOT%Hoenn Reloaded Installer.ps1"

if not exist "%INSTALLER_ENGINE%" (
  color 0C
  echo.
  echo  Hoenn Reloaded Installer.ps1 was not found beside this file.
  echo  Extract the installer package before running it.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER_ENGINE%" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  color 0C
  echo  Hoenn Reloaded installation failed.
) else (
  color 0A
  echo  Hoenn Reloaded installation finished successfully.
)
echo.
pause
exit /b %EXIT_CODE%
