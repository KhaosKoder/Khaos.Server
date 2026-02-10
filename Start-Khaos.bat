@echo off
REM ============================================================================
REM Khaos Server Startup Script (Windows)
REM ============================================================================
REM This script starts the khaos-fraud WSL instance and runs all services.
REM Services will remain running as long as this window stays open.
REM ============================================================================

title Khaos Server - %~n0
echo.
echo ╔═══════════════════════════════════════════════════════════════════════╗
echo ║               KHAOS SERVER - STARTING SERVICES                        ║
echo ╚═══════════════════════════════════════════════════════════════════════╝
echo.
echo This window must stay open for services to keep running.
echo Press Ctrl+C to stop all services.
echo.

REM Run the startup script and then keep bash alive
wsl -d khaos-fraud -u root bash -c "/opt/khaos/scripts/00-khaos-startup.sh; echo; echo 'Services running. Press Ctrl+C to stop.'; while true; do sleep 3600; done"

echo.
echo Khaos services stopped.
pause
