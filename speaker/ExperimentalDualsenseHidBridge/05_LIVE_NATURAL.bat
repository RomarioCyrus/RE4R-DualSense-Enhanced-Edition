@echo off
setlocal
echo NATURAL preset - mild filtering and transient shaping.
echo Press Q, Escape, or Ctrl+C to stop.
echo.
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --loopback --preset natural
echo.
pause
