@echo off
set "APP=%~dp0bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe"
echo Close DSX and disable Steam Input before testing.
echo This applies weak L2 resistance for 800 ms, then resets both triggers.
echo.
pause
"%APP%" --test-l2 --duration 800 --acknowledge-output-conflict
echo.
pause
