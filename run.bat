@echo off
setlocal EnableDelayedExpansion

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

:: 1a. Try PATH first
where node >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('node -v 2^>nul') do set NODE_VER=%%i
    echo     Found Node.js !NODE_VER! on PATH
    set "NODE_EXE=node"
)

:: 1b. Try common install paths (handles the "just installed, PATH not refreshed" case)
if not defined NODE_EXE (
    for %%d in (
        "%ProgramFiles%\nodejs"
        "%ProgramFiles(x86)%\nodejs"
        "%LOCALAPPDATA%\Programs\nodejs"
    ) do (
        if exist "%%d\node.exe" (
            for /f "tokens=*" %%i in ('"%%d\node.exe" -v 2^>nul') do set NODE_VER=%%i
            echo     Found Node.js !NODE_VER! at %%d
            set "NODE_EXE=%%d\node.exe"
            :: Add to PATH for this session
            set "PATH=%%d;!PATH!"
        )
    )
)

:: 1c. Check version
if defined NODE_EXE (
    :: Re-extract version with the found node
    for /f "tokens=*" %%i in ('"!NODE_EXE!" -v 2^>nul') do set NODE_VER=%%i
    set NODE_VER_NUM=!NODE_VER:v=!
    for /f "tokens=1 delims=." %%a in ("!NODE_VER_NUM!") do set NODE_MAJOR=%%a
    if !NODE_MAJOR! LSS 18 (
        echo     Node.js !NODE_VER! is too old (need ^>= 18)
        set "NODE_EXE="
    )
)

:: 1d. Install if missing
if not defined NODE_EXE (
    echo     Node.js not found or too old, installing...
    echo.

    set "NPM_EXE="

    :: --- Try winget ---
    where winget >nul 2>&1
    if not errorlevel 1 (
        echo     winget install --id OpenJS.NodeJS.LTS --source winget --silent --accept-source-agreements --accept-package-agreements
        winget install --id OpenJS.NodeJS.LTS --source winget --silent --accept-source-agreements --accept-package-agreements
        if not errorlevel 1 (
            :: winget succeeded; find the installed node.exe
            for %%d in (
                "%ProgramFiles%\nodejs"
                "%ProgramFiles(x86)%\nodejs"
                "%LOCALAPPDATA%\Programs\nodejs"
            ) do (
                if exist "%%d\node.exe" (
                    set "NODE_EXE=%%d\node.exe"
                    set "NPM_EXE=%%d\npm.cmd"
                    set "PATH=%%d;!PATH!"
                    for /f "tokens=*" %%i in ('"%%d\node.exe" -v 2^>nul') do set NODE_VER=%%i
                    echo     Installed Node.js !NODE_VER!
                )
            )
        ) else (
            echo     winget failed, trying MSI download...
        )
    )

    :: --- Fallback: direct MSI download ---
    if not defined NODE_EXE (
        echo     Downloading Node.js 22 LTS MSI...
        set "MSI_URL=https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi"
        set "MSI_PATH=%TEMP%\node-v22.14.0-x64.msi"
        curl -L --fail -o "!MSI_PATH!" "!MSI_URL!"
        if errorlevel 1 (
            echo     [ERROR] Download failed. Install Node.js 22 LTS manually:
            echo             https://nodejs.org/en/download
            echo     Then re-run this script.
            pause
            exit /b 1
        )
        echo     Running installer (this may take a minute)...
        msiexec /i "!MSI_PATH!" /qn /norestart
        if errorlevel 1 (
            echo     Silent install failed, launching GUI installer...
            msiexec /i "!MSI_PATH!"
        )
        del "!MSI_PATH!" >nul 2>&1

        :: Find the newly installed node
        for %%d in (
            "%ProgramFiles%\nodejs"
            "%ProgramFiles(x86)%\nodejs"
            "%LOCALAPPDATA%\Programs\nodejs"
        ) do (
            if exist "%%d\node.exe" (
                set "NODE_EXE=%%d\node.exe"
                set "NPM_EXE=%%d\npm.cmd"
                set "PATH=%%d;!PATH!"
            )
        )
    )

    if not defined NODE_EXE (
        echo.
        echo     [ERROR] Could not find node.exe after installation.
        echo     Please install Node.js 22 LTS manually:
        echo             https://nodejs.org/en/download
        echo     Then re-run this script.
        pause
        exit /b 1
    )

    for /f "tokens=*" %%i in ('"!NODE_EXE!" -v 2^>nul') do set NODE_VER=%%i
    echo     Node.js !NODE_VER! installed successfully.
    echo.

    :: npm path (alongside node.exe)
    if not defined NPM_EXE (
        for %%d in ("!NODE_EXE!") do set "NODE_DIR=%%~dpd"
        set "NPM_EXE=!NODE_DIR!npm.cmd"
    )
)

echo.

REM ============================================================
REM  2. Check Node.js version (re-evaluate after install)
REM ============================================================
echo [2/5] Verifying environment...

for /f "tokens=*" %%i in ('"!NODE_EXE!" -v 2^>nul') do echo     node: %%i
if defined NPM_EXE (
    for /f "tokens=*" %%i in ('"!NPM_EXE!" -v 2^>nul') do echo     npm:  %%i
) else (
    for /f "tokens=*" %%i in ('where npm 2^>nul') do set "NPM_EXE=%%i"
    for /f "tokens=*" %%i in ('"!NPM_EXE!" -v 2^>nul') do echo     npm:  %%i
)

echo.

REM ============================================================
REM  3. Install / rebuild dependencies
REM ============================================================
echo [3/5] Checking dependencies...

:: Use whichever npm we found (prefer the one alongside node.exe if possible)
if not defined NPM_EXE (
    for /f "tokens=*" %%i in ('where npm.cmd 2^>nul') do set "NPM_EXE=%%i"
)
if not defined NPM_EXE set "NPM_EXE=npm"

if not exist "node_modules" (
    echo     node_modules missing, running npm install...
    call "!NPM_EXE!" install --omit=dev --legacy-peer-deps
    if errorlevel 1 (
        echo     [ERROR] npm install failed. Check your network and retry.
        pause
        exit /b 1
    )
) else (
    echo     node_modules exists
    echo     Checking native modules compatibility...
    call "!NPM_EXE!" rebuild better-sqlite3 sqlite3 >nul 2>&1
)

echo.

REM ============================================================
REM  4. Check port 3000
REM ============================================================
echo [4/5] Checking port 3000...

netstat -ano | findstr ":3000 " | findstr "LISTENING" >nul
if not errorlevel 1 (
    echo     [WARN] Port 3000 is in use:
    netstat -ano | findstr ":3000 " | findstr "LISTENING"
    echo.
) else (
    echo     Port 3000 is available
)

echo.

REM ============================================================
REM  5. Launch
REM ============================================================
echo [5/5] Starting gamyy-core...
echo.
echo ============================================
echo   gamyy-core Web Management Service
echo   URL: http://localhost:3000
echo   Press Ctrl+C to stop.
echo ============================================
echo.

"!NODE_EXE!" web/server.js

echo.
echo Service stopped.
pause
endlocal
