@echo off
title Khaos Vue Dev Server
wsl -d khaos-fraud -u root bash -c "cd /opt/khaos/apps/web && npm run dev -- --host 0.0.0.0 --port 3000"
pause
