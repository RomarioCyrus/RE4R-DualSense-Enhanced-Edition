@echo off
cd /d "%~dp0"
set SIDE=%1
if "%SIDE%"=="" set SIDE=both
echo ============================================================
echo   STEP B: Play 80 Hz test tone on channels 3/4 (side=%SIDE%)
echo ============================================================
echo   Run this WHILE HAPTICS_TEST_A_HOLD_MODE.bat is running to
echo   test the "haptics mode ON" condition (expect vibration).
echo   Run this AFTER test A's window has closed to test the
echo   "control / OFF" condition (expect silence).
echo ============================================================
echo.
DualsenseAudioBridge.exe --test-haptic %SIDE%
echo.
echo Tone finished. Feel the controller now.
pause
