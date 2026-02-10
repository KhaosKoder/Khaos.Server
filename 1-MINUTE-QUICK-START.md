# ⚡ 1-Minute Quick Start

Get a Khaos instance running in under a minute.

## Prerequisites

- Windows 10/11 with WSL2 enabled
- PowerShell (run as Administrator for first-time WSL setup)

## Step 1: Create an Instance (30 seconds)

```powershell
cd scripts\powershell

# Create a new instance named "myapp" with base port 9000
.\01-create-instance.ps1 -Name myapp -BasePort 9000
```

This downloads Ubuntu, creates user `khaos`, and configures everything.

## Step 2: Start the Instance (10 seconds)

```powershell
.\04-start-instance.ps1 -Name myapp
```

Wait for "Setup complete!" message.

## Step 3: Access Your Services (10 seconds)

Open in browser:
- **Web UI**: http://localhost:9000
- **API Docs**: http://localhost:11000/swagger
- **Chat**: http://localhost:9000/chat

## Step 4: Test It Works (10 seconds)

```powershell
# Check health
curl http://localhost:11000/api/health

# Chat with AI
curl -X POST http://localhost:11000/api/chat -H "Content-Type: application/json" -d '{"message": "Hello!"}'
```

## That's It! 🎉

---

## Quick Reference

### Port Layout (BasePort = 9000)

| Service | Port | URL |
|---------|------|-----|
| Web UI | 9000 | http://localhost:9000 |
| API | 11000 | http://localhost:11000 |
| Redis | 15379 | localhost:15379 |
| PostgreSQL | 13432 | localhost:13432 |
| Ollama | 19434 | localhost:19434 |

### Common Commands

```powershell
# List all instances
.\03-list-instances.ps1

# Check instance status with ports
.\07-instance-status.ps1 -Name myapp

# Stop instance
.\05-stop-instance.ps1 -Name myapp

# Delete instance
.\06-delete-instance.ps1 -Name myapp
```

### Inside WSL (Optional)

```bash
# Connect to your instance
wsl -d khaos-myapp

# Check service status
sudo systemctl status khaos-api

# View logs
journalctl -u khaos-api -f
```

---

## Troubleshooting

**Instance won't start?**
```powershell
# Check if WSL is running
wsl --list --verbose

# Restart WSL if needed
wsl --shutdown
.\04-start-instance.ps1 -Name myapp
```

**Services not responding?**
```powershell
# Check status
.\07-instance-status.ps1 -Name myapp

# Or inside WSL
wsl -d khaos-myapp sudo systemctl status khaos-api
```

**Port already in use?**
Create instance with different base port:
```powershell
.\01-create-instance.ps1 -Name myapp2 -BasePort 10000
```

---

For detailed documentation, see:
- [README.md](README.md) - Full documentation
- [GUIDE.md](GUIDE.md) - Architecture guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [RAG-GUIDE.md](RAG-GUIDE.md) - AI file Q&A setup
