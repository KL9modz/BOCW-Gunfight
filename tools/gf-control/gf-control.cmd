@echo off
rem Gunfight Host Control - launcher. Double-click to open the app.
rem   gf-control.cmd          LIVE  - drives the game via the bridge
rem   gf-control.cmd --dry    dry-run - shows the commands, sends nothing
setlocal
cd /d "%~dp0"

rem Prefer the real pythonw (windowless); fall back to the py launcher, then PATH.
set "PYW=C:\Users\KL9mo\AppData\Local\Programs\Python\Python312\pythonw.exe"
if not exist "%PYW%" set "PYW=pythonw"

if /i "%~1"=="--dry" (
    start "" "%PYW%" gf_control.py
) else (
    start "" "%PYW%" gf_control.py --live
)
