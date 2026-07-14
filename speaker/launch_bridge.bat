@echo off
:: DualSense Audio Bridge Launcher for RE4R
:: Place this in the RE4R game root folder
:: Run BEFORE launching the game

title DualSense Audio Bridge

echo ============================================
echo  DualSense Speaker Bridge for RE4R
echo ============================================
echo.

:: Check Python
where python >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found in PATH.
    echo Install Python from https://python.org
    pause
    exit /b 1
)

:: Install dependencies if needed
echo Checking dependencies...
python -m pip install sounddevice soundfile numpy --quiet

echo.
echo Starting bridge...
echo Press Ctrl+C to stop.
echo.

:: Run bridge from game root
:: Adjust paths if needed
python reframework\autorun\DualSenseEnhanced\audio_bridge.py ^
    --sounds-dir "reframework\data\DualSenseEnhanced\sounds" ^
    --events-file "reframework\data\audio_events.json" ^
    --volume 0.85

pause
