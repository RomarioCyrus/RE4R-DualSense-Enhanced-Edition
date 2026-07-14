@echo off
setlocal
echo One-shot audio-haptics mode selection, then PS5-like live loopback.
echo Press Q, Escape, or Ctrl+C to stop.
echo.
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --loopback --preset ps5 --audio-haptics
echo.
pause
