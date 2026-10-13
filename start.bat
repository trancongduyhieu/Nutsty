@echo off
chcp 65001 >nul
title Nutsty Music Player
echo ====================================================
echo        Nutsty Desktop Music Player (Windows)
echo ====================================================
echo.

:: Detect working Python executable or fallback to standard install paths
python -c "import sys; exit(0)" >nul 2>nul
if %errorlevel% neq 0 (
    if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" (
        set "PATH=%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts;%PATH%"
    ) else if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
        set "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%"
    ) else if exist "%LOCALAPPDATA%\Programs\Python\Python310\python.exe" (
        set "PATH=%LOCALAPPDATA%\Programs\Python\Python310;%LOCALAPPDATA%\Programs\Python\Python310\Scripts;%PATH%"
    ) else if exist "%ProgramFiles%\Python311\python.exe" (
        set "PATH=%ProgramFiles%\Python311;%ProgramFiles%\Python311\Scripts;%PATH%"
    ) else (
        for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul') do (
            set "PATH=%%b;%PATH%"
        )
    )
)

python -c "import sys; exit(0)" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Python 3.10+ is not found or not working!
    echo Please install Python 3.10+ from https://www.python.org/
    echo Make sure to check "Add Python to PATH" during installation.
    pause
    exit /b 1
)

:: Create Python virtual environment if not exists
if not exist "venv" (
    echo [1/3] Setting up Python virtual environment...
    python -m venv venv
    if %errorlevel% neq 0 (
        echo [WARN] Could not create virtual environment. Running with system Python.
        goto run_system
    )
)

:: Activate venv and install dependencies
call venv\Scripts\activate.bat
if not exist "venv\.installed" (
    echo [2/3] Installing required packages from requirements_win.txt...
    pip install -r requirements_win.txt
    if %errorlevel% equ 0 (
        type nul > venv\.installed
    )
)

:run_app
echo [3/3] Starting Nutsty...
python launcher_win.py
goto end

:run_system
pip install -r requirements_win.txt
python launcher_win.py

:end
