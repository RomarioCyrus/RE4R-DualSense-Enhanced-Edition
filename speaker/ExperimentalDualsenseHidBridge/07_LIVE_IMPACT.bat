@echo off
setlocal
echo IMPACT preset - strongest and shortest experimental response.
echo Stop immediately if it feels excessive.
echo Press Q, Escape, or Ctrl+C to stop.
echo.
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --loopback --preset impact
echo.
pause
