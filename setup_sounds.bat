@echo off
setlocal enableextensions enabledelayedexpansion
title DualSense Enhanced Edition - Sound Setup
chcp 65001 >nul 2>&1

echo ============================================================
echo  DualSense Enhanced Edition ^| Sound Setup
echo ============================================================
echo.
echo This runs once. After that, sounds work automatically.
echo.

:: This bat lives in the game root (next to re_chunk_000.pak).
:: All tools are in DualSenseEnhanced\tools\extract_sounds\.
set "GAME_DIR=%~dp0"
set "TOOLS_DIR=%GAME_DIR%DualSenseEnhanced\tools\extract_sounds"
set "CHUNK_PAK=%GAME_DIR%re_chunk_000.pak"

set "REEPAK=%TOOLS_DIR%\ree-pak-cli.exe"
set "HASHLIST=%TOOLS_DIR%\DSE_Required_Banks.list"
set "VGMSTREAM=%TOOLS_DIR%\vgmstream\vgmstream-cli.exe"

:: Verify bundled tools
set "MISSING="
if not exist "%REEPAK%"    set "MISSING=!MISSING!  - DualSenseEnhanced\tools\extract_sounds\ree-pak-cli.exe^
"
if not exist "%HASHLIST%"  set "MISSING=!MISSING!  - DualSenseEnhanced\tools\extract_sounds\DSE_Required_Banks.list^
"
if not exist "%VGMSTREAM%" set "MISSING=!MISSING!  - DualSenseEnhanced\tools\extract_sounds\vgmstream\vgmstream-cli.exe^
"
if defined MISSING (
    echo [ERROR] Missing bundled files:
    echo !MISSING!
    echo Re-download the mod from Nexus Mods.
    goto :fail
)

:: Verify game pak
if not exist "%CHUNK_PAK%" (
    echo [ERROR] re_chunk_000.pak not found at:
    echo   %CHUNK_PAK%
    echo.
    echo Make sure setup_sounds.bat is in the RE4R game folder.
    goto :fail
)

echo Game folder : %GAME_DIR%
echo.
echo Starting extraction...
echo.

powershell -ExecutionPolicy Bypass -File "%TOOLS_DIR%\setup_sounds.ps1" ^
    -ReePakPath    "%REEPAK%"      ^
    -HashListPath  "%HASHLIST%"    ^
    -VGMStreamPath "%VGMSTREAM%"   ^
    -ChunkPakPath  "%CHUNK_PAK%"   ^
    -GamePath      "%GAME_DIR%"

if %ERRORLEVEL% neq 0 goto :fail

echo.
echo Generating haptic feedback tones from your own extracted sounds...
echo.

powershell -ExecutionPolicy Bypass -File "%TOOLS_DIR%\generate_haptics.ps1"

if %ERRORLEVEL% neq 0 goto :fail

echo.
echo ============================================================
echo  Done! Launch RE4R with the mod active.
echo ============================================================
echo.
pause
exit /b 0

:fail
echo.
echo ============================================================
echo  Setup failed. See errors above.
echo  If you use Fluffy Mod Manager with audio replacement mods,
echo  temporarily disable them and re-run this script.
echo  For help: [Nexus Mods page URL]
echo ============================================================
echo.
pause
exit /b 1
