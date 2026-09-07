@echo off
setlocal
rem Rebuild discord_game_sdk.dll (the loader shim).
rem Zig is used only as a self-contained C toolchain - no MSVC, no Windows SDK.
rem Install it with:  winget install -e --id zig.zig

set "ZIG="
where zig >nul 2>&1 && set "ZIG=zig"

if not defined ZIG (
  for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\zig.zig_*") do (
    for /d %%E in ("%%~fD\zig-*") do if exist "%%~fE\zig.exe" set "ZIG=%%~fE\zig.exe"
  )
)

if not defined ZIG (
  echo Could not find zig. Install it with:  winget install -e --id zig.zig
  exit /b 1
)

pushd "%~dp0"
"%ZIG%" cc -target x86_64-windows-gnu -shared -Os -o discord_game_sdk.dll shim.c -lkernel32 -luser32
set RC=%ERRORLEVEL%
if exist shim.lib del shim.lib
popd

if not "%RC%"=="0" (echo BUILD FAILED & exit /b 1)
echo Built discord_game_sdk.dll
