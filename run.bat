@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title gamyy-core

echo ============================================
echo   gamyy-core
echo ============================================
echo.

REM ============================================================
REM  Step 1: Find or install Node.js
REM ============================================================
set "NODE_CMD="

REM --- Check if node works on PATH ---
node -v >nul 2>&1
if errorlevel 1 goto :node_not_on_path

REM Node is on PATH; resolve full path so we can find npm next to it
for /f "tokens=*" %%v in ('node -v 2^>nul') do set "NODE_VER=%%v"
for /f "tokens=*" %%p in ('where node 2^>nul') do (
    if "!NODE_CMD!"=="" set "NODE_CMD=%%p"
)
if "!NODE_CMD!"=="" set "NODE_CMD=node"
echo [OK] Node.js !NODE_VER! ^(!NODE_CMD!^)
goto :node_done

:node_not_on_path
REM --- Check common install directories ---
echo Node.js not on PATH. Searching...
for %%d in (
    "C:\Program Files\nodejs"
    "C:\Program Files (x86)\nodejs"
) do (
    if not defined NODE_CMD (
        if exist "%%~d\node.exe" (
            for /f "tokens=*" %%v in ('"%%~d\node.exe" -v 2^>nul') do set "NODE_VER=%%v"
            set "NODE_CMD=%%~d\node.exe"
            echo [OK] Node.js !NODE_VER! ^(%%~d^)
        )
    )
)

REM --- Still not found? Install ---
if not defined NODE_CMD (
    echo.
    echo Node.js not found. Installing Node.js 22 LTS...
    echo.
    call :do_install
    if errorlevel 1 (
        echo.
        echo [FAIL] Installation failed.
        echo Install Node.js 22 from: https://nodejs.org/en/download
        echo Then re-run run.bat
        echo.
        pause
        exit /b 1
    )
)

:node_done
echo.
echo Node: !NODE_VER!
echo Path: !NODE_CMD!

REM ============================================================
REM  Step 2: Find npm (same directory as node.exe)
REM ============================================================
for %%d in ("!NODE_CMD!") do set "NODE_DIR=%%~dpd"

if exist "!NODE_DIR!\npm.cmd" (
    set "NPM_CMD=!NODE_DIR!\npm.cmd"
) else if exist "!NODE_DIR!\npm" (
    set "NPM_CMD=!NODE_DIR!\npm"
) else (
    REM Fallback: hope npm is on PATH
    set "NPM_CMD=npm"
)

for /f "tokens=*" %%v in ('"!NPM_CMD!" -v 2^>nul') do set "NPM_VER=%%v"
echo [OK] npm: !NPM_VER! ^(!NPM_CMD!^)

REM --- Ensure node directory is on PATH (required for node-gyp native builds) ---
if defined NODE_DIR (
    set "PATH=!NODE_DIR!;%PATH%"
)
echo.

REM ============================================================
REM  Step 3: Dependencies
REM ============================================================
echo [3/5] Dependencies...
if not exist "node_modules" (
    echo Installing dependencies...
    echo.
    call "!NPM_CMD!" install --omit=dev --legacy-peer-deps
    if errorlevel 1 (
        echo.
        echo [FAIL] npm install failed.
        echo Try: npm config set registry https://registry.npmmirror.com
        echo Then re-run run.bat
        echo.
        pause
        exit /b 1
    )
    echo.
    echo [OK] Dependencies installed.
) else (
    echo [OK] node_modules exists.
    call "!NPM_CMD!" rebuild better-sqlite3 sqlite3 >nul 2>&1
)
echo.

REM ============================================================
REM  Step 4: Port check
REM ============================================================
echo [4/5] Port 3000...
netstat -ano 2>nul | find ":3000" | find "LISTENING" >nul
if errorlevel 1 (
    echo [OK] Port 3000 available.
) else (
    echo [WARN] Port 3000 is in use:
    netstat -ano 2>nul | find ":3000" | find "LISTENING"
    echo.
    echo Stop the existing process or change port in config.
    echo.
    pause
    exit /b 1
)
echo.

REM ============================================================
REM  Step 5: Launch
REM ============================================================
echo [5/5] Starting...
echo.
echo ============================================
echo   URL: http://localhost:3000
echo   Press Ctrl+C to stop
echo ============================================
echo.

"!NODE_CMD!" web/server.js

echo.
echo Service stopped.
pause
exit /b 0


REM ============================================================
REM  Install Node.js subroutine
REM ============================================================
:do_install

REM --- Try winget ---
winget --version >nul 2>&1
if errorlevel 1 goto :install_msi

echo Trying winget...

REM Uninstall any partial Node.js first (clean slate)
winget uninstall --id OpenJS.NodeJS.LTS --source winget --silent >nul 2>&1

winget install --id OpenJS.NodeJS.LTS --source winget --silent --accept-source-agreements --accept-package-agreements
if errorlevel 1 goto :install_msi

REM Wait a moment for install to finish
echo Waiting for install to complete...
timeout /t 10 /nobreak >nul

REM Locate node.exe
for %%d in (
    "C:\Program Files\nodejs"
    "C:\Program Files (x86)\nodejs"
) do (
    if not defined NODE_CMD (
        if exist "%%~d\node.exe" (
            set "NODE_CMD=%%~d\node.exe"
        )
    )
)

if defined NODE_CMD (
    for /f "tokens=*" %%v in ('"!NODE_CMD!" -v 2^>nul') do set "NODE_VER=%%v"
    echo [OK] winget installed Node.js !NODE_VER!
    exit /b 0
)

echo winget completed but node.exe not found at expected paths.
echo Checking %ProgramFiles%\nodejs...

REM Try one more time after a longer wait
timeout /t 10 /nobreak >nul
dir "C:\Program Files\nodejs" 2>nul
for %%d in (
    "C:\Program Files\nodejs"
    "C:\Program Files (x86)\nodejs"
) do (
    if not defined NODE_CMD (
        if exist "%%~d\node.exe" (
            set "NODE_CMD=%%~d\node.exe"
        )
    )
)

if defined NODE_CMD (
    for /f "tokens=*" %%v in ('"!NODE_CMD!" -v 2^>nul') do set "NODE_VER=%%v"
    echo [OK] Found Node.js !NODE_VER!
    exit /b 0
)

echo winget succeeded but cannot locate node.exe.
goto :install_msi


:install_msi
echo Downloading Node.js 22 LTS installer...
set "MSI_URL=https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi"
set "MSI_FILE=%TEMP%\nodejs-installer.msi"

REM Delete old download if exists
del "%MSI_FILE%" 2>nul

REM Try PowerShell first, then curl
echo Trying PowerShell download...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%MSI_URL%' -OutFile '%MSI_FILE%' -UseBasicParsing" 2>nul

if not exist "%MSI_FILE%" (
    echo Trying curl...
    curl -L -o "%MSI_FILE%" "%MSI_URL%" 2>nul
)

if not exist "%MSI_FILE%" (
    echo.
    echo [FAIL] Could not download Node.js installer.
    echo Download manually from: https://nodejs.org/en/download
    echo Save to: %MSI_FILE%
    echo Then re-run run.bat
    echo.
    exit /b 1
)

echo Running installer...
msiexec /i "%MSI_FILE%" /qn /norestart 2>nul
if errorlevel 1 (
    echo Silent mode failed, launching GUI installer...
    msiexec /i "%MSI_FILE%"
    echo.
    echo After installation completes, re-run run.bat
    echo.
    pause
)

REM Clean up
del "%MSI_FILE%" 2>nul

REM Locate node.exe
for %%d in (
    "C:\Program Files\nodejs"
    "C:\Program Files (x86)\nodejs"
) do (
    if not defined NODE_CMD (
        if exist "%%~d\node.exe" (
            set "NODE_CMD=%%~d\node.exe"
        )
    )
)

if defined NODE_CMD (
    for /f "tokens=*" %%v in ('"!NODE_CMD!" -v 2^>nul') do set "NODE_VER=%%v"
    echo [OK] Node.js !NODE_VER! installed.
    exit /b 0
)

echo [FAIL] Installed but cannot find node.exe.
echo Look in: "C:\Program Files\nodejs"
exit /b 1
