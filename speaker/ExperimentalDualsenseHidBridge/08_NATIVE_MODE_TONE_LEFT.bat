@echo off
setlocal
echo One-shot audio-haptics mode selection, then left actuator tone.
echo RE4R may immediately restore its native compatible-rumble mode.
echo.
"%~dp0dist\portable\DualSenseHapticsProbe.exe" --tone left --gain 0.20 --duration 0.7 --audio-haptics
echo.
pause
