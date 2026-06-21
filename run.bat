@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

echo ============================================
echo   gamyy-core Setup ^& Launch
echo ============================================
echo.

REM ============================================================
REM  1. Find or install Node.js
REM ============================================================
echo [1/5] Checking Node.js...
set "NODE_EXE="
set "NODE_DIR="

REM 1a. Try node on PATH
call :try_path node.exe
if "!NODE_EXE!"=="" call :try_path node

REM 1b. Try common install directories
if "!NODE_EXE!"=="" (
    for %%d in (
        "C:\Program Files\nodejs"
        "C:\Program Files (x86)\nodejs"
    ) do (
        if exist "%%~d\node.exe" (
            set "NODE_EXE=%%~d\node.exe"
            set "NODE_DIR=%%~d"
        )
    )
)

REM 1c. Check version if found
if not "!NODE_EXE!"=="" (
    call :check_node_version
)

REM 1d. Install if missing
if "!NODE_EXE!"=="" (
    call :install_nodejs
    if errorlevel 1 (
        pause
        exit /b 1
    )
)

echo     Node.js version: !NODE_VER!
echo.

REM ============================================================
REM  2. Locate npm
REM ============================================================
echo [2/5] Checking npm...
set "NPM_EXE="
if not "!NODE_DIR!"=="" (
    if exist "!NODE_DIR!\npm.cmd" set "NPM_EXE=!NODE_DIR!\npm.cmd"
    if exist "!NODE_DIR!\npm"    set "NPM_EXE=!NODE_DIR!\npm"
)
if "!NPM_EXE!"=="" call :try_path npm.cmd
if "!NPM_EXE!"=="" call :try_path npm
if "!NPM_EXE!"=="" set "NPM_EXE=npm"

echo     npm: !NPM_EXE!
echo.

REM ============================================================
REM  3. Install or rebuild dependencies
REM ============================================================
echo [3/5] Checking dependencies...

if not exist "node_modules" (
    echo     node_modules missing, running npm install...
    echo.
    call "!NPM_EXE!" install --omit=dev --legacy-peer-deps
    if errorlevel 1 (
        echo.
        echo     [ERROR] npm install failed. Check network or try:
        echo             npm config set registry https://registry.npmmirror.com
        echo             then re-run run.bat
        pause
        exit /b 1
    )
    echo.
) else (
    echo     node_modules exists, checking native modules...
    call "!NPM_EXE!" rebuild better-sqlite3 sqlite3 >nul 2>&1
)

echo.

REM ============================================================
REM  4. Check port
REM ============================================================
echo [4/5] Checking port 3000...
set "PORT_BUSY=0"
netstat -ano 2>nul | findstr ":3000 " | findstr "LISTENING" >nul
if not errorlevel 1 (
    set "PORT_BUSY=1"
    echo     [WARN] Port 3000 is already in use:
    netstat -ano 2>nul | findstr ":3000 " | findstr "LISTENING"
) else (
    echo     Port 3000 is available
)

echo.

REM ============================================================
REM  5. Launch
REM ============================================================
if "!PORT_BUSY!"=="1" (
    echo     Port 3000 is busy. Stop the existing process first.
    echo     Or change port in config before starting.
    pause
    exit /b 1
)

echo [5/5] Starting gamyy-core...
echo.
echo ============================================
echo   gamyy-core Web Management Service
echo   URL:  http://localhost:3000
echo   Press Ctrl+C to stop.
echo ============================================
echo.

"!NODE_EXE!" web/server.js

echo.
echo Service stopped.
pause
endlocal
exit /b 0


REM ============================================================
REM  SUBROUTINES
REM ============================================================

:try_path
REM Usage: call :try_path <executable_name>
REM Sets NODE_EXE if found and valid
set "_TRY=%1"
for /f "delims=" %%p in ('where "!_TRY!" 2^>nul') do (
    if "!NODE_EXE!"=="" (
        set "NODE_EXE=%%p"
    )
)
exit /b

:check_node_version
REM Uses NODE_EXE; sets NODE_VER and clears NODE_EXE if too old
set "NODE_VER=unknown"
for /f "tokens=*" %%v in ('"!NODE_EXE!" -v 2^>nul') do set "NODE_VER=%%v"
set "NODE_VER_NUM=!NODE_VER:v=!"
for /f "tokens=1 delims=." %%a in ("!NODE_VER_NUM!") do set "NODE_MAJOR=%%a"
if !NODE_MAJOR! LSS 18 (
    echo     Node.js !NODE_VER! too old (need ^>= 18)
    set "NODE_EXE="
)
exit /b

:install_nodejs
echo     Node.js not found, installing...

REM Try winget first (with explicit --source to avoid msstore cert issue)
call :try_path winget.exe
if not "!NODE_EXE!"=="" set "HAS_WINGET=1"
set "NODE_EXE="

if "!HAS_WINGET!"=="1" (
    echo     Installing via winget...
    winget install --id OpenJS.NodeJS.LTS --source winget --silent --accept-source-agreements --accept-package-agreements
    if not errorlevel 1 (
        REM Success; locate node.exe
        for %%d in (
            "C:\Program Files\nodejs"
            "C:\Program Files (x86)\nodejs"
        ) do (
            if exist "%%~d\node.exe" (
                if "!NODE_EXE!"=="" (
                    set "NODE_EXE=%%~d\node.exe"
                    set "NODE_DIR=%%~d"
                )
            )
        )
        if not "!NODE_EXE!"=="" (
            call :check_node_version
            if not "!NODE_EXE!"=="" exit /b 0
        )
    )
    echo     winget failed, trying MSI download...
    set "HAS_WINGET=0"
)

if "!HAS_WINGET!"=="0" (
    echo     Downloading Node.js 22 LTS MSI...
    set "MSI_URL=https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi"
    set "MSI_PATH=%TEMP%\node-v22.14.0-x64.msi"

    powershell -Command "Invoke-WebRequest -Uri '!MSI_URL!' -OutFile '!MSI_PATH!'" 2>nul
    if not exist "!MSI_PATH!" (
        curl -L --fail -o "!MSI_PATH!" "!MSI_URL!" 2>nul
    )

    if not exist "!MSI_PATH!" (
        echo     [ERROR] Download failed.
        echo     Install Node.js 22 LTS from: https://nodejs.org/en/download
        echo     Then re-run run.bat
        exit /b 1
    )

    echo     Running silent install (may take a minute)...
    msiexec /i "!MSI_PATH!" /qn /norestart 2>nul
    if errorlevel 1 msiexec /i "!MSI_PATH!" 2>nul
    del "!MSI_PATH!" 2>nul

    REM Locate installed node.exe
    for %%d in (
        "C:\Program Files\nodejs"
        "C:\Program Files (x86)\nodejs"
    ) do (
        if exist "%%~d\node.exe" (
            if "!NODE_EXE!"=="" (
                set "NODE_EXE=%%~d\node.exe"
                set "NODE_DIR=%%~d"
            )
        )
    )
)

if "!NODE_EXE!"=="" (
    echo     [ERROR] Could not find node.exe after install.
    echo     Install Node.js 22 LTS from: https://nodejs.org/en/download
    echo     Then re-run run.bat
    exit /b 1
)

call :check_node_version
exit /b 0
