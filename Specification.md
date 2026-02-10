# Khaos Server

## Goal 

Provide a quick, easy way (with minimal downloads) to create a complete Linux server running under WSL for LLM development.

Build apps where a small LLM is aware of your business, language, and rules—capable of implementing processes or answers that include calling specific API methods.

---

## Technology Stack (Locked Versions)

| Component | Version | Notes |
|-----------|---------|-------|
| **Linux** | Ubuntu 24.04 LTS (Noble Numbat) | Best compatibility for AI/ML, large community, well-tested with WSL2 |
| **Ollama** | Latest | Self-updating, manages models |
| **Default Model** | Qwen 2.5 3B | Small, capable, good for business tasks |
| **Python** | 3.12.x | Stable, excellent library support |
| **.NET** | 10.0 | LTS, Minimal API backend |
| **Node.js** | 22 LTS | Current LTS |
| **Vue** | 3.x + Vite + TypeScript | With Vuetify 3, Vue Router, Pinia |
| **Redis** | Latest stable | Cache layer |
| **PostgreSQL** | 16.x | Persistent storage (fast, JSON support) |
| **Nginx** | Latest stable | Reverse proxy + SSL termination |

### Python Libraries (RAG/ML Stack)
- `langchain` + `langchain-community` - Orchestration
- `sentence-transformers` - Embeddings
- `chromadb` - Vector store (lightweight, pure Python)
- `httpx` - Async HTTP for Ollama API
- `redis` - Python Redis client

### Available LLM Models (User Selectable)
| Model | Size | Best For |
|-------|------|----------|
| `qwen2.5:3b` | ~2GB | **Default** - Balanced performance |
| `qwen2.5:1.5b` | ~1GB | Fastest, lowest memory |
| `qwen2.5:7b` | ~4.5GB | Better reasoning |
| `phi3:mini` | ~2.3GB | Microsoft, good for code |
| `llama3.2:3b` | ~2GB | Meta, general purpose |
| `mistral:7b` | ~4.1GB | Strong reasoning |

---

## Directory Structure

### Windows (Host)
```
C:\Users\{username}\.khaos\
├── cache\                    # Downloaded installers/images
│   ├── distros\              # WSL distro images
│   ├── ollama\               # Ollama installer
│   ├── models\               # Pre-pulled model files
│   ├── dotnet\               # .NET SDK installers
│   ├── node\                 # Node.js installers
│   └── python\               # Python packages (wheels)
├── logs\                     # PowerShell script logs
├── instances\                # Instance metadata/configs
└── scripts\                  # The Khaos scripts
```

### Linux (WSL Instance)
```
/opt/khaos/
├── apps/
│   ├── api/                  # .NET Minimal API project
│   └── web/                  # Vue 3 + Vuetify frontend
├── scripts/                  # Setup scripts
└── config/                   # Configuration files

/var/log/khaos/               # Linux-side logs
```

---

## WSL Instance Naming

**Pattern**: `khaos-{name}`

Examples:
- `khaos-dev`
- `khaos-prod`
- `khaos-test`

Multiple instances supported simultaneously. User provides the name during creation.

---

## Port Allocation

### Default Ports (BasePort = 3000)

| Service | Internal Port | Exposed Via Nginx |
|---------|---------------|-------------------|
| Vue Dev Server | 3000 | `/` (root) |
| .NET API | 5000 | `/api/*` |
| Ollama | 11434 | `/ollama/*` (optional) |
| Redis | 6379 | Not exposed externally |
| PostgreSQL | 5432 | Not exposed externally |
| Nginx HTTP | 80 | Redirects to HTTPS |
| Nginx HTTPS | 443 | Main entry point (SSL) |

### Multi-Instance Port Configuration

Each instance can use a different base port to avoid conflicts. Ports are calculated from the base:

| Service | Offset | BasePort=3000 | BasePort=4000 |
|---------|--------|---------------|---------------|
| Web (Vue) | +0 | 3000 | 4000 |
| API | +2000 | 5000 | 6000 |
| Ollama | +8434 | 11434 | 12434 |
| Redis | +3379 | 6379 | 7379 |
| PostgreSQL | +2432 | 5432 | 6432 |

Create instances with custom base ports:
```powershell
.\01-create-instance.ps1 -Name "Primary" -BasePort 3000
.\01-create-instance.ps1 -Name "Secondary" -BasePort 4000
```

Port configuration is stored in `/etc/khaos/khaos.conf` inside each WSL instance.

---

## Service Management (systemd)

WSL instances run with **systemd enabled** (`/etc/wsl.conf` has `systemd=true`).

### Systemd Services

| Service | Unit File | Description |
|---------|-----------|-------------|
| `redis-server` | System | Redis cache server |
| `postgresql` | System | PostgreSQL database |
| `nginx` | System | Reverse proxy + SSL |
| `khaos-api` | `/etc/systemd/system/khaos-api.service` | .NET Minimal API |
| `khaos-web` | `/etc/systemd/system/khaos-web.service` | Vue dev server |
| Ollama | Self-managed | Runs independently via its own service |

### Service Persistence

- All services are **enabled** (`systemctl enable`) and start automatically when WSL boots
- WSL stays running as long as services are active
- Use `04-start-instance.ps1` to start WSL and verify services
- Use `05-stop-instance.ps1` to gracefully stop all services and terminate WSL

---

## What To Build

### Phase 1: PowerShell Scripts (Windows Host)

| Script | Purpose |
|--------|---------|
| `config.ps1` | Central configuration (versions, paths, URLs) |
| `utils.ps1` | Logging, caching, error handling helpers |
| `00-download-all.ps1` | Pre-download everything for offline use |
| `01-create-instance.ps1` | Create named WSL instance from cached image |
| `02-run-setup.ps1` | Copy and execute bash scripts inside WSL |
| `03-list-instances.ps1` | List all khaos-* instances with their state |
| `04-start-instance.ps1` | Start instance and verify all services |
| `05-stop-instance.ps1` | Gracefully stop services and terminate WSL |
| `06-delete-instance.ps1` | Unregister WSL distribution (with confirmation) |

### Phase 2: Bash Scripts (Inside WSL)

| Script | Purpose |
|--------|---------|
| `01-system-setup.sh` | Update packages, install base tools |
| `02-install-ollama.sh` | Install Ollama, pull default model |
| `03-install-python.sh` | Python 3.12 + venv + RAG libraries |
| `04-install-dotnet.sh` | .NET 10 SDK + scaffold API |
| `05-install-node-vue.sh` | Node 22 + scaffold Vue/Vuetify app |
| `06-install-redis.sh` | Redis server |
| `07-install-postgres.sh` | PostgreSQL 16 + schema |
| `08-install-nginx.sh` | Nginx + SSL + reverse proxy config |
| `09-start-services.sh` | Manual service starter (legacy) |
| `10-setup-systemd.sh` | Enable systemd + create service files | |

---

## Script Writing Standards

### Logging Format
Every script must log:
```
[TIMESTAMP] [STEP] [STATUS] Message
[2026-02-08 10:30:15] [Install Python] [START] Installing Python 3.12...
[2026-02-08 10:30:45] [Install Python] [SUCCESS] Python 3.12.3 installed
[2026-02-08 10:30:46] [Install Python] [FAIL] pip install failed: <error>
```

### Error Handling
- **Partial Failure**: Log error, continue to next step, report summary at end
- **Critical Failure**: Stop execution, provide clear error message and remediation steps
- **Retry Logic**: Network operations retry 3 times with exponential backoff

### Caching Strategy
1. Check if file exists in cache
2. If exists + valid checksum → use cached
3. If missing or corrupt → download and cache
4. If offline mode + missing → fail with clear message

---

## User Workflow

### First Time (Online)
```powershell
# 1. Download everything
.\00-download-all.ps1

# 2. Create an instance
.\01-create-instance.ps1 -Name "dev"

# 3. Run setup (automatically runs all bash scripts)
.\02-run-setup.ps1 -Name "dev"
```

### Subsequent Instances (Offline Capable)
```powershell
.\01-create-instance.ps1 -Name "test"
.\02-run-setup.ps1 -Name "test"
```

### Model Selection
```powershell
# List available models (shows which are cached)
.\02-run-setup.ps1 -Name "dev" -ListModels

# Choose a specific model
.\02-run-setup.ps1 -Name "dev" -Model "phi3:mini"
```

---

## Deliverables Checklist

### Scripts
- [x] `config.ps1` - Configuration
- [x] `utils.ps1` - Helper functions
- [x] `00-download-all.ps1` - Download manager
- [x] `01-create-instance.ps1` - WSL instance creator
- [x] `02-run-setup.ps1` - Setup orchestrator
- [x] `03-list-instances.ps1` - List all instances
- [x] `04-start-instance.ps1` - Start instance
- [x] `05-stop-instance.ps1` - Stop instance
- [x] `06-delete-instance.ps1` - Delete instance
- [x] `bash/01-system-setup.sh`
- [x] `bash/02-install-ollama.sh`
- [x] `bash/03-install-python.sh`
- [x] `bash/04-install-dotnet.sh`
- [x] `bash/05-install-node-vue.sh`
- [x] `bash/06-install-redis.sh`
- [x] `bash/07-install-postgres.sh`
- [x] `bash/08-install-nginx.sh`
- [x] `bash/09-start-services.sh` (legacy manual starter)
- [x] `bash/10-setup-systemd.sh`

### App Scaffolds
- [x] .NET Minimal API with Redis + Ollama integration + Swagger
- [x] Vue 3 + Vuetify + Pinia with Redis UI + Chat interface

---

## App Scaffold Requirements

### .NET Minimal API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `GET /api/health` | GET | Health check (includes DB/Redis/Ollama status) |
| **Redis Operations (Cache)** |||
| `GET /api/redis/{key}` | GET | Get single value by key |
| `PUT /api/redis/{key}` | PUT | Set single key/value |
| `DELETE /api/redis/{key}` | DELETE | Remove single key |
| `GET /api/redis` | GET | Get all key/value pairs (bulk download) |
| `POST /api/redis/bulk` | POST | Set multiple key/value pairs (bulk upload) |
| `DELETE /api/redis` | DELETE | Clear all keys |
| **PostgreSQL Operations (Persistent)** |||
| `GET /api/data/{key}` | GET | Get single value by key |
| `PUT /api/data/{key}` | PUT | Set single key/value |
| `DELETE /api/data/{key}` | DELETE | Remove single key |
| `GET /api/data` | GET | Get all key/value pairs (bulk download) |
| `POST /api/data/bulk` | POST | Set multiple key/value pairs (bulk upload) |
| `DELETE /api/data` | DELETE | Clear all keys |
| **LLM Operations** |||
| `POST /api/chat` | POST | Send message to Ollama, return response |
| `GET /api/chat/models` | GET | List available Ollama models |

### PostgreSQL Schema
```sql
CREATE TABLE kv_store (
    key VARCHAR(255) PRIMARY KEY,
    value JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### Vue 3 + Vuetify Pages

| Route | Description |
|-------|-------------|
| `/` | Dashboard/home |
| `/redis` | Redis cache manager (ephemeral) |
| `/data` | PostgreSQL data manager (persistent) |
| `/chat` | LLM chat interface |

### Redis Manager Features (Vue)
- View all keys in a table
- Add new key/value pair (form)
- Edit existing value (inline or modal)
- Delete single key (with confirmation)
- Bulk export: Download all as JSON file
- Bulk import: Upload JSON file to set multiple keys

### Chat Interface Features (Vue)
- Simple message input
- Scrollable chat history
- Show model name being used
- Basic "thinking" indicator while waiting for response

---

## Development Workflow

### Prerequisites
- VS Code with the "WSL" extension (ms-vscode-remote.remote-wsl)
- Node.js 22+ on Windows (for running Vue dev tools)
- .NET 10 SDK on Windows (optional, for local debugging)

### Connecting to Your Instance

```bash
# From PowerShell, enter the WSL instance
wsl -d khaos-<name> -u khaos

# Inside WSL, you're now in the Linux environment
cd /opt/khaos/apps
```

### Working on the C# API

```bash
# Navigate to the API project
cd /opt/khaos/apps/api

# Run with hot reload (development mode)
dotnet watch run --urls http://0.0.0.0:5000

# Or just run normally
dotnet run --urls http://0.0.0.0:5000
```

With VS Code Remote-WSL:
1. Press F1 → "WSL: Connect to WSL"
2. Select your instance (khaos-<name>)
3. Open folder `/opt/khaos/apps/api`
4. Use F5 to debug with breakpoints

### Working on the Vue Frontend

```bash
# Navigate to the web project
cd /opt/khaos/apps/web

# Run with hot reload
npm run dev -- --host 0.0.0.0 --port 3000

# Build for production
npm run build

# Run linting
npm run lint
```

With VS Code Remote-WSL:
1. Connect to your WSL instance
2. Open folder `/opt/khaos/apps/web`
3. Use the integrated terminal for npm commands
4. Vue DevTools browser extension works with the dev server

### Environment Variables

All Khaos configuration is available via environment variables, loaded from `/etc/khaos/khaos.conf`:

| Variable | Description | Default |
|----------|-------------|---------|
| `KHAOS_INSTANCE_NAME` | Display name | "Khaos Server" |
| `KHAOS_API_PORT` | .NET API port | 5000 |
| `KHAOS_WEB_PORT` | Vue dev server port | 3000 |
| `KHAOS_OLLAMA_PORT` | Ollama server port | 11434 |
| `KHAOS_REDIS_PORT` | Redis port | 6379 |
| `KHAOS_POSTGRES_PORT` | PostgreSQL port | 5432 |
| `KHAOS_CACHE_PATH` | Windows cache mount | /mnt/khaos-cache |

### Viewing Logs

```bash
# API logs
tail -f /var/log/khaos/api.log

# Frontend logs  
tail -f /var/log/khaos/web.log

# Ollama logs
tail -f /var/log/khaos/ollama.log

# Startup log
tail -f /var/log/khaos/startup.log
```

### Restarting Services

```bash
# Using the startup script
sudo /opt/khaos/scripts/00-khaos-startup.sh

# Or restart individual services (if using systemd)
sudo systemctl restart khaos-api
sudo systemctl restart khaos-web
sudo systemctl restart ollama
```

---

## Documentation TODO
- [x] Development workflow documentation
- [ ] TROUBLESHOOTING.md

---

## Resolved Decisions

| Question | Decision |
|----------|----------|
| **HTTPS** | Self-signed certificates (generated during setup) |
| **Persistence** | PostgreSQL 16 for persistent data; Redis remains ephemeral cache |
| **GPU Support** | Auto-detect NVIDIA GPU; enable if available, graceful fallback to CPU (expect most users: 16GB RAM laptops, no GPU) |
| **Shared Folders** | **Yes** - Mount Windows cache folder into WSL for offline installs |

---

## Shared Folder Configuration

The Windows cache folder is mounted into WSL for offline installation capability.

| Windows Path | WSL Mount Point |
|--------------|-----------------|
| `C:\Users\{username}\.khaos\cache` | `/mnt/khaos-cache` |

This allows bash scripts to access pre-downloaded installers:
```bash
# Example: Install from cached .deb file
dpkg -i /mnt/khaos-cache/packages/some-package.deb

# Example: Copy cached model to Ollama
cp /mnt/khaos-cache/models/qwen2.5-3b.gguf /usr/share/ollama/.ollama/models/
```

### Mount Setup (handled by PowerShell during instance creation)
```powershell
# In 01-create-instance.ps1
wsl -d khaos-$Name --mount --type drvfs "\\?\C:\Users\$env:USERNAME\.khaos\cache" /mnt/khaos-cache
```

Or via `/etc/fstab` inside WSL:
```
C:\Users\{username}\.khaos\cache /mnt/khaos-cache drvfs defaults 0 0
``` 

