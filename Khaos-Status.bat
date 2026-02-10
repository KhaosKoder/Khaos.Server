@echo off
REM ============================================================================
REM Khaos Server Status Check (Windows)
REM ============================================================================

echo.
echo Khaos Server Status
echo ═══════════════════════════════════════════════════════
echo.

wsl -d khaos-fraud -u root bash -c "source /etc/khaos/khaos.conf 2>/dev/null; echo 'Checking ports...'; netstat -tuln 2>/dev/null | grep -E ':3000|:5000|:11434|:6379|:5432' || echo 'No services listening'"

echo.
pause
