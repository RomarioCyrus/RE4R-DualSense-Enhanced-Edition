@echo off
setlocal
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --tone left --gain 0.20 --duration 0.7
echo.
pause
