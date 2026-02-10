# 🔧 Khaos Server Troubleshooting Guide

This guide covers common issues and solutions when working with Khaos Server.

---

## Table of Contents

1. [Installation Issues](#installation-issues)
2. [WSL Issues](#wsl-issues)
3. [Service Issues](#service-issues)
4. [Port Conflicts](#port-conflicts)
5. [Database Issues](#database-issues)
6. [API Issues](#api-issues)
7. [Frontend Issues](#frontend-issues)
8. [Performance Issues](#performance-issues)

---

## Installation Issues

### Download fails or times out

**Symptoms**: `00-download-all.ps1` fails with network errors

**Solutions**:
1. Check your internet connection
2. Retry with `-Force` flag to re-download failed files:
   ```powershell
   .\00-download-all.ps1 -Force
   ```
3. If behind a corporate proxy, configure it:
   ```powershell
   $env:HTTP_PROXY = "http://proxy.company.com:8080"
   $env:HTTPS_PROXY = "http://proxy.company.com:8080"
   .\00-download-all.ps1
   ```

### WSL2 not installed or outdated

**Symptoms**: Error "WSL 2 requires an update to its kernel component"

**Solutions**:
```powershell
# Update WSL
wsl --update

# Set WSL2 as default
wsl --set-default-version 2
```

### Setup script hangs or takes very long

**Symptoms**: `02-run-setup.ps1` appears stuck

**This is normal!** The setup:
- Downloads ~2GB of packages and models
- Compiles dependencies
- Takes 15-25 minutes on a typical machine

**If truly stuck** (no output for 10+ minutes):
1. Check logs: `~\.khaos\logs\setup-<name>.log`
2. Cancel and retry the specific failed step

---

## WSL Issues

### Instance won't start

**Symptoms**: "Error 0x80370102" or similar when starting instance

**Solutions**:
1. Ensure virtualization is enabled in BIOS
2. Enable Hyper-V features:
   ```powershell
   dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
   dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
   ```
3. Restart your computer

### Systemd not working

**Symptoms**: Services don't start automatically, `systemctl` commands fail

**Solutions**:
1. Ensure `/etc/wsl.conf` has systemd enabled:
   ```bash
   wsl -d khaos-<name> -u root -- cat /etc/wsl.conf
   # Should contain: [boot] systemd=true
   ```
2. Restart WSL to activate systemd:
   ```powershell
   wsl --shutdown
   wsl -d khaos-<name>
   ```

### Instance corrupted

**Symptoms**: Random errors, file system issues

**Solutions**:
1. Delete and recreate the instance:
   ```powershell
   .\06-delete-instance.ps1 -Name "<name>"
   .\01-create-instance.ps1 -Name "<name>"
   .\02-run-setup.ps1 -Name "<name>"
   ```

---

## Service Issues

### Check service status

```bash
# Enter the WSL instance
wsl -d khaos-<name> -u khaos

# Check all services
systemctl status khaos-api
systemctl status redis-server
systemctl status postgresql
systemctl status ollama

# View logs
journalctl -u khaos-api -f
```

### API service won't start

**Symptoms**: `http://localhost:5000` not responding

**Solutions**:
1. Check if service is running:
   ```bash
   systemctl status khaos-api
   ```
2. Check logs:
   ```bash
   journalctl -u khaos-api --no-pager -n 50
   ```
3. Try starting manually:
   ```bash
   cd /opt/khaos/apps/api
   dotnet run --urls http://0.0.0.0:5000
   ```

### Redis won't start

**Symptoms**: "Redis disconnected" in health check

**Solutions**:
1. Check Redis status:
   ```bash
   systemctl status redis-server
   redis-cli ping
   ```
2. Check Redis logs:
   ```bash
   cat /var/log/redis/redis-server.log
   ```
3. Restart Redis:
   ```bash
   sudo systemctl restart redis-server
   ```

### Ollama not responding

**Symptoms**: Chat fails, "Ollama disconnected"

**Solutions**:
1. Check Ollama status:
   ```bash
   systemctl status ollama
   ollama list
   ```
2. Restart Ollama:
   ```bash
   sudo systemctl restart ollama
   ```
3. Verify model is loaded:
   ```bash
   ollama run qwen2.5:3b "Hello"
   ```

---

## Port Conflicts

### Port already in use

**Symptoms**: "Address already in use" or services fail to bind

**Solutions**:
1. Find what's using the port (from PowerShell):
   ```powershell
   netstat -ano | findstr ":5000"
   ```
2. Kill the conflicting process:
   ```powershell
   taskkill /PID <pid> /F
   ```
3. Or use a different base port when creating the instance:
   ```powershell
   .\01-create-instance.ps1 -Name "dev2" -BasePort 4000
   ```

### Check which ports an instance uses

```powershell
.\07-instance-status.ps1 -Name "dev"
```

---

## Database Issues

### PostgreSQL won't connect

**Symptoms**: "postgres disconnected" in health check

**Solutions**:
1. Check PostgreSQL status:
   ```bash
   systemctl status postgresql
   ```
2. Verify connection:
   ```bash
   psql -h localhost -U khaos -d khaosdb -c "SELECT 1"
   # Password: khaos
   ```
3. Check logs:
   ```bash
   cat /var/log/postgresql/postgresql-16-main.log
   ```

### PostgreSQL Connection Details

| Parameter | Value |
|-----------|-------|
| Host | `localhost` or `127.0.0.1` |
| Port | Default `5432` (check `KHAOS_POSTGRES_PORT`) |
| Database | `khaosdb` |
| Username | `khaos` |
| Password | `khaos` |

### Reset PostgreSQL data

**Warning**: This deletes all persistent data!

```bash
sudo -u postgres psql -c "DROP DATABASE khaosdb;"
sudo -u postgres psql -c "CREATE DATABASE khaosdb OWNER khaos;"
sudo -u khaos psql -d khaosdb -c "
CREATE TABLE kv_store (
    key VARCHAR(255) PRIMARY KEY,
    value JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);"
```

---

## API Issues

### Health check fails

Check individual services:
```bash
curl http://localhost:5000/api/health
```

Expected response:
```json
{
  "status": "healthy",
  "redis": "connected",
  "postgres": "connected",
  "ollama": "connected"
}
```

### Swagger not loading

**Solutions**:
1. Ensure API is running: `curl http://localhost:5000/api/health`
2. Access Swagger directly: `http://localhost:5000/swagger/index.html`
3. Check browser console for JavaScript errors

### CORS errors

**Symptoms**: Browser console shows "Access-Control-Allow-Origin" errors

**Solutions**:
1. CORS is configured to allow all origins by default
2. If issues persist, check `Program.cs` CORS configuration

---

## Frontend Issues

### Vue app not loading

**Symptoms**: Blank page or 404 errors

**Solutions**:
1. Verify static files exist:
   ```bash
   ls -la /opt/khaos/publish/web/
   ```
2. Check nginx is serving them:
   ```bash
   systemctl status nginx
   cat /etc/nginx/sites-enabled/khaos
   ```

### UI shows "disconnected" status

**Solutions**:
1. Check API is reachable from browser
2. Verify nginx reverse proxy is working:
   ```bash
   curl http://localhost/api/health
   ```

---

## Performance Issues

### Slow LLM responses

**Causes**: Limited RAM, no GPU

**Solutions**:
1. Use a smaller model:
   ```bash
   ollama pull qwen2.5:1.5b
   ```
2. Close other memory-intensive applications
3. Check available memory:
   ```bash
   free -h
   ```

### High memory usage

**Symptoms**: System slowdown, OOM errors

**Solutions**:
1. Limit WSL memory in `~/.wslconfig`:
   ```ini
   [wsl2]
   memory=8GB
   ```
2. Restart WSL: `wsl --shutdown`

### Disk space issues

**Solutions**:
1. Check disk usage:
   ```bash
   df -h /
   du -sh /opt/khaos/*
   ```
2. Clean up old models:
   ```bash
   ollama rm <model-name>
   ```
3. Clear package caches:
   ```bash
   sudo apt clean
   ```

---

## Getting Help

### Collect diagnostics

Run this to gather diagnostic info:
```bash
echo "=== System ===" && uname -a
echo "=== Memory ===" && free -h
echo "=== Disk ===" && df -h /
echo "=== Services ===" && systemctl list-units --type=service | grep -E "khaos|redis|postgres|ollama|nginx"
echo "=== Ports ===" && ss -tlnp | grep -E "5000|6379|5432|11434"
echo "=== Env ===" && cat /etc/khaos/khaos.conf
```

### Check logs

```powershell
# PowerShell setup logs
Get-Content ~\.khaos\logs\setup-<name>.log -Tail 100
```

```bash
# Linux logs
journalctl -u khaos-api -n 100
journalctl -u ollama -n 100
tail -100 /var/log/nginx/error.log
```

---

## Common Error Messages

| Error | Meaning | Fix |
|-------|---------|-----|
| `Connection refused` | Service not running | Start the service |
| `Address in use` | Port conflict | Find/kill conflicting process |
| `Permission denied` | File permission issue | Check ownership with `ls -la` |
| `No such file` | Missing file/path | Verify installation completed |
| `OOM killed` | Out of memory | Increase WSL memory limit |

---

<p align="center">
  <em>Still stuck? Open an issue on GitHub with your diagnostic info.</em>
</p>
