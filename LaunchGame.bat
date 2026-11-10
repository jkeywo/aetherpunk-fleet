@echo off
setlocal
title Aetherpunk Fleet

rem Use the project beside this launcher, or the installed local checkout.
set "GAME_DIR=%~dp0"
if not exist "%GAME_DIR%project.godot" set "GAME_DIR=C:\coding\aetherpunk-fleet\"
set "GODOT_EXE=%GAME_DIR%..\the-usual-godot\.tools\Godot_v4.7.2-stable_win64.exe"

if not exist "%GAME_DIR%project.godot" (
    echo Cannot find Aetherpunk Fleet at "%GAME_DIR%".
    pause
    exit /b 1
)
if not exist "%GODOT_EXE%" (
    echo Cannot find Godot at "%GODOT_EXE%".
    pause
    exit /b 1
)

start "" "%GODOT_EXE%" --path "%GAME_DIR%." %*
exit /b 0
