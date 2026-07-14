@echo off
cd /d "%~dp0"
echo ============================================================
echo   STEP A: Hold audio-haptics mode for 60 seconds
echo ============================================================
echo   While this window is running, open HAPTICS_TEST_B_PLAY_TONE.bat
echo   in another window to play the test tone -- that is the
echo   "haptics mode ON" condition.
echo.
echo   After this window closes on its own (mode restored to
echo   compatible rumble), run HAPTICS_TEST_B_PLAY_TONE.bat again
echo   WITHOUT this window running -- that is the "control / OFF"
echo   condition. It should be silent.
echo ============================================================
echo.
DualSenseEnhancedTransport.exe --test-haptics-mode --acknowledge-output-conflict --duration 60000
echo.
echo Done. Compatible-rumble mode restored.
pause
