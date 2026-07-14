@echo off
set "APP=%~dp0bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe"
"%APP%" --reset --acknowledge-output-conflict
echo.
pause
