@echo off
setlocal
echo PS5-LIKE preset - sharper transients and shorter reverb tails.
echo Press Q, Escape, or Ctrl+C to stop.
echo.
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --loopback --preset ps5
echo.
pause
