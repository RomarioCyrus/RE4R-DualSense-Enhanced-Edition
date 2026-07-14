@echo off
setlocal
echo RAW preset - original confirmed v0.1-style processing.
echo Press Q, Escape, or Ctrl+C to stop.
echo.
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --loopback --preset raw
echo.
pause
