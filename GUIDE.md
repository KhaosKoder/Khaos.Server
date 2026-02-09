# Khaos Server - User Guide

> **A complete, self-contained Linux AI development environment running on WSL2**

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Managing the Linux Instance](#managing-the-linux-instance)
3. [Accessing the Applications](#accessing-the-applications)
4. [Chat Interface Guide](#chat-interface-guide)
5. [Extending the Code](#extending-the-code)
6. [API Reference](#api-reference)
7. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Installation (One-Time Setup)

1. **Open PowerShell as Administrator**

2. **Download all dependencies:**
   ```powershell
   cd scripts/powershell
   .\00-download-all.ps1
   ```
   This caches Ubuntu, templates, and scripts for offline use.

3. **Create a new instance:**
   ```powershell
   .\01-create-instance.ps1 -Name "dev"
   ```
   Creates a new WSL instance named `khaos-dev`.

4. **Run the setup (installs everything):**
   ```powershell
   .\02-run-setup.ps1 -Name "dev"
   ```
   This takes 10-20 minutes and installs:
   - Ollama with AI models
   - Python 3.12 with LangChain
   - .NET 10 API
   - Vue 3 + Vuetify web app
   - Redis cache
   - PostgreSQL database
   - Nginx reverse proxy

---

## Managing the Linux Instance

### Starting the Instance

```powershell
# From scripts/powershell folder:
.\04-start-instance.ps1 -Name "dev"
```

Or manually:
```powershell
wsl -d khaos-dev
```

### Stopping the Instance

```powershell
.\05-stop-instance.ps1 -Name "dev"
```

Or manually:
```powershell
wsl --terminate khaos-dev
```

### Listing All Instances

```powershell
.\03-list-instances.ps1
```

### Deleting an Instance

```powershell
.\06-delete-instance.ps1 -Name "dev"
```

### Keeping Linux Running (Background)

Linux services need WSL to keep running. The start script maintains a background process. Alternatively, with systemd enabled:

```bash
# Inside WSL - services start automatically
sudo systemctl status redis-server
sudo systemctl status khaos-api
```

---

## Accessing the Applications

Once the instance is running:

| Application | URL | Description |
|-------------|-----|-------------|
| **Web App** | http://localhost:3000 | Vue 3 + Vuetify dashboard |
| **API Swagger** | http://localhost:5000/swagger | API documentation |
| **Chat UI** | http://localhost:3000/chat | AI chat interface |
| **Redis Manager** | http://localhost:3000/redis | Redis cache viewer |

### Direct Access via WSL

```bash
# Enter the WSL instance
wsl -d khaos-dev

# Check services
sudo systemctl status redis-server
sudo systemctl status postgresql
sudo systemctl status nginx

# Start services manually if needed
sudo /opt/khaos/scripts/start-services.sh
```

### Accessing from Windows

All ports are automatically forwarded:
- **API**: http://localhost:5000
- **Web**: http://localhost:3000
- **Nginx**: http://localhost:80 (or https://localhost:443)
- **Redis**: localhost:6379
- **PostgreSQL**: localhost:5432
- **Ollama**: http://localhost:11434

---

## Chat Interface Guide

The Chat page (`/chat`) provides a full-featured AI conversation interface:

### Features

1. **Multiple Models**
   - Select from installed Ollama models (qwen2.5:3b, llama3.1:8b, etc.)
   - Models can be added via: `ollama pull <model-name>`

2. **Save Conversations**
   - Click "Save" to persist the current chat
   - Name your conversation for easy retrieval
   - Saved to Redis for persistence

3. **Load Conversations**
   - Click "Conversations" in the sidebar
   - Select any saved conversation to continue

4. **Prompt Library**
   - Save useful prompts for reuse
   - Click the bookmark icon on any message to save it
   - Access via "Prompts" tab in sidebar

5. **File Attachments**
   - Click the attachment icon to upload documents
   - Supported: .txt, .md, .json files
   - Content is appended to your message

6. **Keyboard Shortcuts**
   - **Ctrl+Enter**: Send message
   - Large textarea for complex prompts

### System Prompts

Set a system prompt to guide the AI's behavior:
1. Click "Settings" in the sidebar
2. Enter your system prompt (e.g., "You are a helpful coding assistant")
3. All messages will use this context

---

## Extending the Code

### Project Structure

```
/opt/khaos/
├── apps/
│   ├── api/          # .NET 10 API
│   │   ├── Program.cs
│   │   └── KhaosApi.csproj
│   └── web/          # Vue 3 frontend
│       ├── src/
│       │   ├── views/
│       │   │   ├── Home.vue
│       │   │   ├── Chat.vue
│       │   │   └── Redis.vue
│       │   ├── App.vue
│       │   └── main.ts
│       └── package.json
├── scripts/          # Service scripts
└── config/           # Configuration files
```

### Modifying the API (.NET)

1. **Enter WSL:**
   ```bash
   wsl -d khaos-dev
   cd /opt/khaos/apps/api
   ```

2. **Edit Program.cs:**
   ```bash
   nano Program.cs
   # Or use VS Code:
   code .
   ```

3. **Add a new endpoint:**
   ```csharp
   app.MapGet("/api/custom", () => Results.Ok("Hello!"));
   ```

4. **Rebuild and run:**
   ```bash
   dotnet build
   dotnet run
   ```

5. **For permanent changes, restart the service:**
   ```bash
   sudo systemctl restart khaos-api
   ```

### Modifying the Frontend (Vue)

1. **Enter WSL:**
   ```bash
   wsl -d khaos-dev
   cd /opt/khaos/apps/web
   ```

2. **Edit Vue files:**
   ```bash
   nano src/views/Chat.vue
   ```

3. **Run development server:**
   ```bash
   npm run dev
   ```

4. **Build for production:**
   ```bash
   npm run build
   ```

### Adding New Vue Pages

1. **Create the view:**
   ```bash
   nano src/views/MyPage.vue
   ```

2. **Register the route in `main.ts`:**
   ```typescript
   import MyPage from './views/MyPage.vue'
   
   const router = createRouter({
     routes: [
       // ... existing routes
       { path: '/mypage', component: MyPage }
     ]
   })
   ```

3. **Add navigation in `App.vue`:**
   ```vue
   <v-btn to="/mypage" variant="text">My Page</v-btn>
   ```

### Adding NuGet Packages

```bash
cd /opt/khaos/apps/api
dotnet add package <PackageName>
dotnet build
```

### Adding npm Packages

```bash
cd /opt/khaos/apps/web
npm install <package-name>
```

---

## API Reference

### Health Check
```
GET /api/health
```
Returns status of Redis and Ollama connections.

### Chat
```
POST /api/chat
{
  "message": "Hello, AI!",
  "model": "qwen2.5:3b"  // optional
}
```

### List Models
```
GET /api/chat/models
```

### Redis Cache
```
GET    /api/redis           # List all keys
GET    /api/redis/{key}     # Get single key
PUT    /api/redis/{key}     # Set key (body: { "value": "..." })
DELETE /api/redis/{key}     # Delete key
DELETE /api/redis           # Clear all keys
POST   /api/redis/bulk      # Bulk import (body: { "key1": "val1", ... })
```

### Conversations
```
GET    /api/conversations      # List all
GET    /api/conversations/{id} # Get one
POST   /api/conversations      # Create new
PUT    /api/conversations/{id} # Update
DELETE /api/conversations/{id} # Delete
```

### Prompts
```
GET    /api/prompts      # List all
POST   /api/prompts      # Create (body: { "name": "...", "content": "..." })
DELETE /api/prompts/{id} # Delete
```

---

## Troubleshooting

### Services Not Starting

```bash
# Check service status
sudo systemctl status khaos-api
sudo systemctl status redis-server

# View logs
sudo journalctl -u khaos-api -f
sudo journalctl -u redis-server -f

# Restart services
sudo systemctl restart khaos-api
```

### WSL Keeps Shutting Down

Enable WSL keepalive:
```powershell
# Start with keepalive (already in start script)
.\04-start-instance.ps1 -Name "dev"
```

Or inside WSL:
```bash
sudo systemctl enable wsl-keepalive
sudo systemctl start wsl-keepalive
```

### API Returns Errors

```bash
# Check if API is running
curl http://localhost:5000/api/health

# Check Ollama
curl http://localhost:11434/api/tags

# Check Redis
redis-cli ping
```

### Models Not Responding

```bash
# Check Ollama status
sudo systemctl status ollama

# List models
ollama list

# Pull a model if missing
ollama pull qwen2.5:3b
```

### Port Conflicts

If another application uses the same port:
```bash
# Find what's using port 5000
sudo netstat -tulpn | grep 5000

# Change port in Program.cs
app.Run("http://0.0.0.0:5001");  # Use different port
```

### Redis Connection Failed

```bash
# Check Redis is running
sudo systemctl status redis-server

# Test connection
redis-cli ping

# Check config
cat /etc/redis/redis.conf | grep bind
```

### Viewing Logs

```bash
# Khaos setup logs
cat /var/log/khaos/setup.log

# System journal
sudo journalctl -xe

# Nginx logs
sudo tail -f /var/log/nginx/error.log
```

---

## Tips & Best Practices

1. **Save frequently used prompts** - Build a library of effective prompts
2. **Export conversations** - Use the export feature for backup
3. **Use system prompts** - Define AI behavior once, use everywhere
4. **Edit locally with VS Code** - `code /opt/khaos/apps/api` works from WSL
5. **Keep models small** - 3B models are fastest; 7B-8B for better quality
6. **Clear Redis periodically** - Free up memory with the Redis manager

---

*Khaos Server - Your local all-in-one AI development server*
