@echo off
REM Khaos Test - Start Services
title Khaos Test (Port 4000)
echo Starting Khaos Test services...
wsl -d khaos-Test -u root bash -c "/opt/khaos/scripts/00-khaos-startup.sh; echo; echo 'Services running. Press Ctrl+C to stop.'; while true; do sleep 3600; done"
pause
