@echo off
setlocal
echo Diagnostic only: start a 1.5 second left tone, then send five
echo audio-haptics selections over 200 ms.
echo.
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --tone left --gain 0.25 --duration 1.5 --audio-haptics-burst
echo.
pause
