# RAG (Retrieval Augmented Generation) Guide

## What is RAG?

RAG (Retrieval Augmented Generation) is a technique that enhances Large Language Models (LLMs) by providing them with relevant context from your own documents **at query time**. Instead of fine-tuning or retraining a model (which is expensive and complex), RAG allows you to:

1. **Index your documents** - Store file contents in a searchable format
2. **Retrieve relevant content** - When a question is asked, find the most relevant documents
3. **Augment the prompt** - Include the retrieved content as context for the LLM
4. **Generate an answer** - The LLM answers based on YOUR data, not just its training

## Why RAG Instead of Training?

| Approach | Pros | Cons |
|----------|------|------|
| **Fine-tuning** | Permanent knowledge, faster inference | Expensive, complex, needs retraining for updates |
| **RAG** | Easy updates, no retraining, uses any LLM | Slightly slower, context limits |

For most use cases, **RAG is the better choice** because:
- You can update your knowledge base instantly
- No specialized ML infrastructure needed
- Works with any Ollama model
- No risk of catastrophic forgetting

## How Khaos RAG Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INDEXING PHASE                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Files on Disk          POST /api/rag/index           Redis        │
│   ┌─────────┐           ┌──────────────────┐        ┌─────────┐    │
│   │ .cs     │           │ Read file content│        │ Store   │    │
│   │ .md     │  ───────► │ Chunk if needed  │ ─────► │ with    │    │
│   │ .py     │           │ Add metadata     │        │ metadata│    │
│   │ .json   │           └──────────────────┘        └─────────┘    │
│   └─────────┘                                                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                          QUERY PHASE                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   User Question         POST /api/rag/query          Answer         │
│   ┌─────────────┐      ┌──────────────────┐      ┌─────────────┐   │
│   │ "What does  │      │ 1. Get indexed   │      │ Based on    │   │
│   │  this code  │ ───► │    files         │ ───► │ Program.cs, │   │
│   │  do?"       │      │ 2. Build context │      │ the code... │   │
│   └─────────────┘      │ 3. Query Ollama  │      └─────────────┘   │
│                        └──────────────────┘                        │
│                              │                                      │
│                              ▼                                      │
│                        ┌──────────────────┐                        │
│                        │ Ollama + Context │                        │
│                        │ (llama3.2, etc)  │                        │
│                        └──────────────────┘                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## API Reference

### Index Files

Index files for RAG querying:

```bash
POST /api/rag/index
Content-Type: application/json

{
  "path": "/home/khaos/app",
  "indexName": "my-project",
  "extensions": [".cs", ".md", ".py"],
  "recursive": true,
  "maxFiles": 100
}
```

**Parameters:**
| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| path | string | Yes | - | Directory or file to index |
| indexName | string | No | "default" | Name for this index |
| extensions | string[] | No | [".txt", ".md", ".cs", ".py", ".js", ".ts", ".json", ".xml", ".yaml", ".yml", ".html", ".css", ".vue"] | File types to index |
| recursive | boolean | No | true | Search subdirectories |
| maxFiles | integer | No | 100 | Maximum files to index |

**Response:**
```json
{
  "indexName": "my-project",
  "filesIndexed": 15,
  "files": [
    { "path": "/home/khaos/app/Program.cs", "name": "Program.cs", "size": 12345 }
  ]
}
```

### Query Indexed Files

Ask questions about indexed files:

```bash
POST /api/rag/query
Content-Type: application/json

{
  "question": "What API endpoints are defined in this project?",
  "indexName": "my-project",
  "model": "llama3.2",
  "maxContext": 30000
}
```

**Parameters:**
| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| question | string | Yes | - | Your question about the indexed files |
| indexName | string | No | "default" | Which index to query |
| model | string | No | "llama3.2" | Ollama model to use |
| maxContext | integer | No | 30000 | Max characters of context |

**Response:**
```json
{
  "question": "What API endpoints are defined?",
  "answer": "Based on Program.cs, the following endpoints are defined...",
  "model": "llama3.2",
  "indexName": "my-project",
  "sourcesUsed": [
    { "path": "/home/khaos/app/Program.cs", "name": "Program.cs", "relevance": 5 }
  ],
  "contextLength": 15234
}
```

### List Indexes

```bash
GET /api/rag/indexes
```

**Response:**
```json
{
  "indexes": [
    { "name": "default", "fileCount": 10 },
    { "name": "my-project", "fileCount": 25 }
  ]
}
```

### Delete Index

```bash
DELETE /api/rag/index/my-project
```

**Response:**
```json
{
  "deleted": true,
  "indexName": "my-project",
  "filesRemoved": 25
}
```

## Example Use Cases

### 1. Code Documentation Q&A

Index your project and ask questions about the code:

```bash
# Index the API project
curl -X POST http://localhost:7000/api/rag/index \
  -H "Content-Type: application/json" \
  -d '{"path": "/home/khaos/app", "indexName": "khaos-api"}'

# Ask about the code
curl -X POST http://localhost:7000/api/rag/query \
  -H "Content-Type: application/json" \
  -d '{"question": "How does the Redis caching work?", "indexName": "khaos-api"}'
```

### 2. Configuration File Analysis

```bash
# Index config files
curl -X POST http://localhost:7000/api/rag/index \
  -H "Content-Type: application/json" \
  -d '{
    "path": "/etc",
    "indexName": "system-config",
    "extensions": [".conf", ".cfg", ".ini", ".yaml", ".json"],
    "maxFiles": 50
  }'

# Query
curl -X POST http://localhost:7000/api/rag/query \
  -H "Content-Type: application/json" \
  -d '{"question": "What nginx configuration is being used?", "indexName": "system-config"}'
```

### 3. Log File Analysis

```bash
# Index recent logs
curl -X POST http://localhost:7000/api/rag/index \
  -H "Content-Type: application/json" \
  -d '{
    "path": "/var/log",
    "indexName": "logs",
    "extensions": [".log"],
    "maxFiles": 20
  }'

# Ask about errors
curl -X POST http://localhost:7000/api/rag/query \
  -H "Content-Type: application/json" \
  -d '{"question": "What errors occurred recently?", "indexName": "logs"}'
```

## Tips for Better RAG Results

### 1. Index Strategically
- Index only relevant files, not everything
- Use specific extensions for your use case
- Create separate indexes for different purposes

### 2. Ask Specific Questions
- ❌ "Tell me about the code"
- ✅ "What does the `/api/health` endpoint return?"

### 3. Reference File Names When Known
- ✅ "What is the purpose of `Program.cs`?"
- ✅ "How is Redis configured in this project?"

### 4. Use Appropriate Models
- `llama3.2` - Good balance of speed and quality
- `llama3.2:1b` - Faster, simpler answers
- `codellama` - Better for code analysis

### 5. Re-index After Changes
If you update files, re-index to get current content:
```bash
# Delete old index
curl -X DELETE http://localhost:7000/api/rag/index/my-project

# Re-index
curl -X POST http://localhost:7000/api/rag/index \
  -H "Content-Type: application/json" \
  -d '{"path": "/home/khaos/app", "indexName": "my-project"}'
```

## Disk Info API (Companion Feature)

RAG often needs to know about disk space. Use these endpoints:

### Get Disk Space

```bash
GET /api/disk/info
```

**Response:**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "drives": [
    {
      "name": "/",
      "type": "Fixed",
      "totalBytes": 107374182400,
      "freeBytes": 53687091200,
      "usedBytes": 53687091200,
      "totalFormatted": "100 GB",
      "freeFormatted": "50 GB",
      "usedFormatted": "50 GB",
      "percentUsed": 50.00
    }
  ]
}
```

### Get Folder Sizes

Find which folders use the most space:

```bash
GET /api/disk/folders?path=/home&depth=2&limit=10
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| path | string | "/" | Directory to analyze |
| depth | integer | 1 | How deep to calculate sizes |
| limit | integer | 20 | Number of folders to return |

**Response:**
```json
{
  "path": "/home",
  "timestamp": "2024-01-15T10:30:00Z",
  "totalFilesSize": 1048576,
  "totalFilesSizeFormatted": "1 MB",
  "folders": [
    {
      "path": "/home/khaos",
      "name": "khaos",
      "sizeBytes": 524288000,
      "sizeFormatted": "500 MB",
      "itemCount": 150
    }
  ]
}
```

## Architecture Notes

### Storage
- File contents stored in **Redis** with hash sets
- Each index is a Redis set containing file keys
- Files are stored with metadata (path, name, indexed date, size)

### Query Processing
1. Load all files from the specified index
2. Simple keyword relevance scoring
3. Build context string from files (respecting maxContext limit)
4. Send to Ollama with RAG-specific prompt template
5. Return answer with source attribution

### Limitations
- Context window limit depends on Ollama model
- Large files are truncated at 50KB
- No semantic vector search (keyword-based relevance only)
- Files must be re-indexed after changes

## Future Enhancements

Potential improvements for production use:
- **Vector embeddings** - Use sentence-transformers for semantic search
- **ChromaDB** - Persistent vector database for large document sets
- **Chunking** - Split large files into smaller, overlapping chunks
- **Incremental updates** - Only re-index changed files
- **Caching** - Cache frequent query results
