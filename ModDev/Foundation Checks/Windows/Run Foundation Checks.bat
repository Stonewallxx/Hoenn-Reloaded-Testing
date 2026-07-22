@echo off
setlocal
title Hoenn Reloaded Foundation Checks
cd /d "%~dp0..\..\.."
ruby "%~dp0FoundationChecks.rb"
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
