@echo off
setlocal
set "APP=%~dp0bin\Release\net6.0-windows\win-x64\DualSenseEnhancedTransport.exe"
set "GAME_DIR=C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4"

echo Close DSX and disable Steam Input before native testing.
echo Start RE4R in Native Game API mode, then enable duaLib trigger IPC in the mod UI.
echo.
set /p "GAME_DIR=RE4R game folder [%GAME_DIR%]: "
set "COMMAND_FILE=%GAME_DIR%\reframework\data\trigger_command.json"

if not exist "%GAME_DIR%\reframework\data" (
    echo REFramework data directory not found:
    echo %GAME_DIR%\reframework\data
    pause
    exit /b 1
)

echo.
echo Watching %COMMAND_FILE%
echo Press Ctrl+C to stop; the watcher resets both triggers before exiting.
"%APP%" --watch "%COMMAND_FILE%" --acknowledge-output-conflict
echo.
pause
