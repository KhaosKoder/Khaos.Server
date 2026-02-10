# 🚀 Khaos Server

> **A complete, self-contained AI development environment in a box**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![WSL2](https://img.shields.io/badge/WSL2-Required-green.svg)](https://docs.microsoft.com/en-us/windows/wsl/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Khaos Server spins up a fully-configured Linux AI development stack on Windows in under 20 minutes. No Docker. No cloud. Just pure WSL2 goodness with everything you need to build LLM-powered applications.

![Dashboard Preview](docs/images/dashboard-preview.png)

---

## 🎯 Why Khaos Server?

**The Problem**: Setting up a local AI development environment is painful. You need:
- An LLM runtime (Ollama)
- A vector database for RAG
- A fast cache layer (Redis)
- A persistent database (PostgreSQL)
- A backend API (.NET/Python)
- A frontend (Vue/React)
- Reverse proxy with SSL (Nginx)

That's 7+ technologies to install, configure, and wire together. Most tutorials skip the hard parts.

**The Solution**: Khaos Server does it all with two commands:

```powershell
.\00-download-all.ps1          # Download everything (once)
.\01-create-instance.ps1 -Name "dev"   # Create your environment
.\02-run-setup.ps1 -Name "dev"         # Install & configure everything
```

☕ Grab a coffee. Come back to a fully working AI development server.

**Please note:** Step 02 is going to take some time - it isn't broken, it just takes a good 15-20 minutes. Be patient - good things will happen. 

---

## ✨ What's Included

| Component | Version | Purpose |
|-----------|---------|---------|
| **Ubuntu** | 24.04 LTS | Solid Linux foundation |
| **Ollama** | Latest | Run LLMs locally (Qwen, Llama, Mistral, etc.) |
| **.NET** | 10.0 | Minimal API backend with Swagger |
| **Vue 3** | + Vuetify 3 | Beautiful, reactive frontend |
| **Python** | 3.12 | LangChain + RAG libraries |
| **Redis** | Latest | Lightning-fast cache |
| **PostgreSQL** | 16 | Persistent data storage |
| **Nginx** | Latest | Reverse proxy with SSL |

### Pre-installed AI Models

| Model | Size | Best For |
|-------|------|----------|
| `qwen2.5:3b` | ~2GB | **Default** - Fast, capable, great for business logic |
| `phi3:mini` | ~2.3GB | Code generation and analysis |
| `llama3.2:3b` | ~2GB | General purpose tasks |
| `mistral:7b` | ~4.1GB | Complex reasoning (requires more RAM) |

---

## 🚦 Quick Start

### Prerequisites

- Windows 10/11 with WSL2 enabled
- 16GB RAM recommended (8GB minimum)
- 20GB free disk space
- PowerShell 5.1+

### Installation

```powershell
# 1. Clone this repository
git clone https://github.com/your-org/khaos-server.git
cd khaos-server/scripts/powershell

# 2. Download all dependencies (offline-capable after this)
.\00-download-all.ps1

# 3. Create a new instance
.\01-create-instance.ps1 -Name "dev"

# 4. Run the full setup (~15-20 minutes)
.\02-run-setup.ps1 -Name "dev"
```

### Access Your Environment

| Application | URL | Description |
|-------------|-----|-------------|
| 🏠 **Dashboard** | http://localhost:3000 | Status overview & quick actions |
| 💬 **AI Chat** | http://localhost:3000/chat | Full-featured chat interface |
| 📦 **Redis Manager** | http://localhost:3000/redis | View/edit cached data |
| � **Data Manager** | http://localhost:3000/data | PostgreSQL persistent storage |
| 📁 **File Browser** | http://localhost:3000/filesystem | Browse & view server files |
| �📚 **API Docs** | http://localhost:5000/swagger | Interactive API explorer |

---

## 💡 Use Cases

### 1. Build a Business-Aware AI Assistant

Train an LLM on your company's documentation, APIs, and business rules. See the [Azure DevOps Use Case](docs/USE_CASE_AZURE_DEVOPS.md) for a detailed example where we build an AI that:

- Understands your project's work item types and workflows
- Creates properly formatted tickets from natural language
- Knows your team's coding standards and can review PRs
- Answers questions about your sprint planning

### 2. Create a Customer Support Bot

```python
# Example: Product FAQ bot with RAG
from langchain.vectorstores import Chroma
from langchain.embeddings import HuggingFaceEmbeddings

# Load your product documentation
docs = load_documents("./product_docs/")
vectorstore = Chroma.from_documents(docs, HuggingFaceEmbeddings())

# Query with context
response = chain.run("How do I reset my password?")
```

**Why Khaos?** All the infrastructure (vector store, embeddings, LLM) is pre-configured and running locally.

### 3. Prototype an Internal Tool

Build a quick proof-of-concept without waiting for cloud resources:

```csharp
// Add a custom endpoint in Program.cs
app.MapPost("/api/analyze-contract", async (ContractRequest req, IHttpClientFactory http) =>
{
    var client = http.CreateClient("Ollama");
    var prompt = $"Analyze this contract for red flags:\n\n{req.ContractText}";
    
    var response = await client.PostAsJsonAsync("/api/generate", new { 
        model = "qwen2.5:3b", 
        prompt 
    });
    
    return Results.Ok(await response.Content.ReadFromJsonAsync<OllamaResponse>());
});
```

**Why Khaos?** Hot-reload your API, test with real LLM responses, no API costs.

### 4. Document Analysis Pipeline

Process and analyze documents using local models:

```typescript
// Vue component to upload and analyze documents
const analyzeDocument = async (file: File) => {
  const text = await file.text();
  
  const response = await fetch('/api/chat', {
    method: 'POST',
    body: JSON.stringify({
      message: `Summarize this document in 3 bullet points:\n\n${text}`,
      model: 'qwen2.5:3b'
    })
  });
  
  return response.json();
};
```

### 5. Code Review Assistant

Let AI review your code changes:

```bash
# Get diff and pipe to the API
git diff HEAD~1 | curl -X POST http://localhost:5000/api/chat \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"Review this code diff for bugs and improvements:\n\n$(cat)\"}"
```

---

## 🛠️ Managing Your Environment

### Start/Stop Instance

```powershell
# Start (and verify all services)
.\04-start-instance.ps1 -Name "dev"

# Stop gracefully
.\05-stop-instance.ps1 -Name "dev"

# List all instances
.\03-list-instances.ps1

# Detailed status with ports and service health
.\07-instance-status.ps1
```

### Multiple Environments

Create separate instances for different projects:

```powershell
.\01-create-instance.ps1 -Name "project-alpha"
.\01-create-instance.ps1 -Name "project-beta"
.\01-create-instance.ps1 -Name "experiments"
```

Each instance is completely isolated with its own databases, models, and code.

### Add More Models

```bash
# Enter your instance
wsl -d khaos-dev

# Pull additional models
ollama pull llama3.1:8b
ollama pull codellama:7b
ollama pull mistral:7b
```

---

## 📁 Project Structure

```
khaos-server/
├── scripts/
│   ├── powershell/        # Windows management scripts
│   │   ├── 00-download-all.ps1
│   │   ├── 01-create-instance.ps1
│   │   └── ...
│   └── bash/              # Linux setup scripts
│       ├── 01-system-setup.sh
│       ├── 02-install-ollama.sh
│       └── ...
├── templates/             # App scaffolds
│   ├── api/               # .NET Minimal API
│   └── web/               # Vue 3 + Vuetify
├── docs/                  # Documentation
│   ├── GUIDE.md           # User guide
│   └── USE_CASE_*.md      # Detailed examples
└── tests/                 # Playwright E2E tests
```

---

## 🔌 API Reference

### Chat with AI
```bash
curl -X POST http://localhost:5000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Explain quantum computing simply", "model": "qwen2.5:3b"}'
```

### List Available Models
```bash
curl http://localhost:5000/api/chat/models
```

### Redis Cache Operations
```bash
# Get all keys
curl http://localhost:5000/api/redis

# Set a value
curl -X PUT http://localhost:5000/api/redis/my-key \
  -H "Content-Type: application/json" \
  -d '{"value": "my-data"}'
```

### Persistent Data (PostgreSQL)
```bash
# Store persistent data
curl -X POST http://localhost:5000/api/data/my-key \
  -H "Content-Type: application/json" \
  -d '{"value": {"name": "John", "active": true}}'

# Get persistent data
curl http://localhost:5000/api/data/my-key
```

### Filesystem Operations
```bash
# List files in a directory
curl "http://localhost:5000/api/filesystem/list?path=/opt/khaos"

# Get file info
curl "http://localhost:5000/api/filesystem/info?path=/opt/khaos/apps/api/Program.cs"

# Read file contents
curl "http://localhost:5000/api/filesystem/read?path=/etc/khaos/khaos.conf"
```

### PostgreSQL Connection
Connect directly to PostgreSQL for advanced queries:

| Parameter | Value |
|-----------|-------|
| Host | `localhost` |
| Port | `5432` (default) or `KHAOS_POSTGRES_PORT` |
| Database | `khaosdb` |
| Username | `khaos` |
| Password | `khaos` |

```bash
# Connect via psql inside WSL
wsl -d khaos-dev -u khaos
psql -h localhost -U khaos -d khaosdb
```

### Save/Load Conversations
```bash
# Save conversation
curl -X POST http://localhost:5000/api/conversations \
  -H "Content-Type: application/json" \
  -d '{"name": "Project Discussion", "messages": [...], "systemPrompt": "..."}'

# List conversations
curl http://localhost:5000/api/conversations
```

See [API Documentation](http://localhost:5000/swagger) for the complete reference.

---

## 📖 Documentation

- **[User Guide](GUIDE.md)** - Detailed usage instructions
- **[Specification](Specification.md)** - Technical architecture
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Azure DevOps Use Case](USECASE-DEVOPS.md)** - Real-world example

---

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <strong>Khaos Server</strong> - Your local AI development powerhouse
  <br>
  <em>Build smarter. Ship faster. Own your AI.</em>
</p>
