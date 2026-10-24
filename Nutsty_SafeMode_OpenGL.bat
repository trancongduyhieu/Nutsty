@echo off
chcp 65001 >nul
title Nutsty (Safe Mode - OpenGL)
echo ====================================================
echo    Nutsty Music Player - Safe Mode (OpenGL Backend)
echo ====================================================
echo.
echo Setting QSG_RHI_BACKEND=opengl to prevent VirtualBox Direct3D 11 driver crash...
set "QSG_RHI_BACKEND=opengl"

if exist "%~dp0Nutsty.exe" (
    echo Launching Nutsty.exe...
    start "" "%~dp0Nutsty.exe" %*
) else if exist "%~dp0start.bat" (
    call "%~dp0start.bat" %*
) else (
    python "%~dp0launcher_win.py" %*
)
