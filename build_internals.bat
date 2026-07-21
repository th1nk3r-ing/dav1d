@echo off
setlocal enabledelayedexpansion

rem ============================================================================
rem build_internals.bat - Build dav1d with analyzer (internals) extension
rem
rem Produces dav1d.dll (with dav1d_set_analyzer_flags exported) and optionally
rem deploys it as dav1d-internals.dll next to YUViewApp.
rem
rem Environment variables (all optional):
rem   DAV1D_VCVARS64   - path to vcvars64.bat (default: auto-detect via vswhere)
rem   DAV1D_DEPLOY_DIR - destination dir for dav1d-internals.dll (default: skip)
rem   PYTHON, NASM     - expected to be on PATH (or set them before calling)
rem
rem Usage:
rem   build_internals.bat
rem   set DAV1D_DEPLOY_DIR=E:\github\yuview\YUViewTest\build\YUViewApp && build_internals.bat
rem ============================================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

rem --- locate vcvars64.bat ---
if defined DAV1D_VCVARS64 (
    set "VCVARS=%DAV1D_VCVARS64%"
) else (
    for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -prerelease -property installationPath 2^>nul`) do set "VSINSTALL=%%i"
    if not defined VSINSTALL (
        for /f "usebackq tokens=*" %%i in (`"%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -prerelease -property installationPath 2^>nul`) do set "VSINSTALL=%%i"
    )
    if not defined VSINSTALL (
        echo [ERROR] Could not locate Visual Studio via vswhere. Set DAV1D_VCVARS64 explicitly.
        exit /b 1
    )
    set "VCVARS=!VSINSTALL!\VC\Auxiliary\Build\vcvars64.bat"
)

if not exist "%VCVARS%" (
    echo [ERROR] vcvars64.bat not found: %VCVARS%
    exit /b 1
)

call "%VCVARS%"
if errorlevel 1 (
    echo [ERROR] vcvars64.bat failed
    exit /b 1
)

rem --- ensure python/meson/nasm reachable (vcvars may have overwritten PATH) ---
rem     Python main dir may already be on PATH while Scripts (meson/ninja) is not,
rem     so check each independently.
set "PY_BASE=%LOCALAPPDATA%\Programs\Python\Python314"
set "PY_SCRIPTS=%PY_BASE%\Scripts"
where python >nul 2>&1 || set "PATH=%PATH%;%PY_BASE%"
where meson  >nul 2>&1 || set "PATH=%PATH%;%PY_SCRIPTS%"
where ninja  >nul 2>&1 || set "PATH=%PATH%;%PY_SCRIPTS%"
where nasm   >nul 2>&1 || set "PATH=%PATH%;%ProgramFiles%\NASM"

where meson >nul 2>&1 || (
    echo [ERROR] meson not found on PATH. Install: pip install meson
    exit /b 1
)
where ninja >nul 2>&1 || (
    echo [ERROR] ninja not found on PATH. pip install meson typically provides it.
    exit /b 1
)
where nasm >nul 2>&1 || (
    echo [WARNING] nasm not found; ASM optimizations will be disabled.
)

cd /d "%SCRIPT_DIR%"

if exist build-internals rd /s /q build-internals

echo === meson setup ===
meson setup build-internals --default-library=shared --buildtype=release -Denable_asm=true -Denable_tools=false -Denable_tests=false
if errorlevel 1 (
    echo [ERROR] meson setup failed
    exit /b 1
)

echo === ninja build ===
ninja -C build-internals
if errorlevel 1 (
    echo [ERROR] ninja build failed
    exit /b 1
)

echo === verify analyzer exports ===
dumpbin /exports build-internals\src\dav1d.dll | findstr /i "analyzer"
if errorlevel 1 (
    echo [ERROR] dav1d_set_analyzer_flags not exported; build is not the internals variant.
    exit /b 1
)

if defined DAV1D_DEPLOY_DIR (
    if not exist "%DAV1D_DEPLOY_DIR%" (
        echo [WARNING] DAV1D_DEPLOY_DIR does not exist, skipping deploy: %DAV1D_DEPLOY_DIR%
    ) else (
        echo === deploy to %DAV1D_DEPLOY_DIR% ===
        copy /Y build-internals\src\dav1d.dll "%DAV1D_DEPLOY_DIR%\dav1d-internals.dll"
        if errorlevel 1 (
            echo [ERROR] deploy failed
            exit /b 1
        )
    )
) else (
    echo === deploy skipped (set DAV1D_DEPLOY_DIR to enable) ===
)

echo === done: build-internals\src\dav1d.dll ===
endlocal
