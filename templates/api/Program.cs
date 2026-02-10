using System.Text.Json;
using System.Net.Http.Json;
using StackExchange.Redis;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

// Configure default URL if not set via command line
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(int.Parse(Environment.GetEnvironmentVariable("KHAOS_API_PORT") ?? "5000"));
});

// Add services
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});

// Redis connection
builder.Services.AddSingleton<IConnectionMultiplexer>(sp =>
{
    var redisPort = Environment.GetEnvironmentVariable("KHAOS_REDIS_PORT") ?? "6379";
    var config = ConfigurationOptions.Parse($"localhost:{redisPort}");
    config.AbortOnConnectFail = false;
    config.AllowAdmin = true;
    return ConnectionMultiplexer.Connect(config);
});

// HttpClient for Ollama
builder.Services.AddHttpClient("Ollama", client =>
{
    var ollamaPort = Environment.GetEnvironmentVariable("KHAOS_OLLAMA_PORT") ?? "11434";
    client.BaseAddress = new Uri($"http://localhost:{ollamaPort}");
    client.Timeout = TimeSpan.FromMinutes(5);
});

// PostgreSQL connection string factory
builder.Services.AddSingleton<Func<NpgsqlConnection>>(sp =>
{
    var postgresPort = Environment.GetEnvironmentVariable("KHAOS_POSTGRES_PORT") ?? "5432";
    var connectionString = $"Host=127.0.0.1;Port={postgresPort};Database=khaosdb;Username=khaos;Password=khaos";
    return () => new NpgsqlConnection(connectionString);
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();
app.UseCors();

// ============================================================================
// Instance Info - provides instance name, ports, and paths
// ============================================================================
app.MapGet("/api/instance", () =>
{
    var apiPort = Environment.GetEnvironmentVariable("KHAOS_API_PORT") ?? "5000";
    var webPort = Environment.GetEnvironmentVariable("KHAOS_WEB_PORT") ?? "3000";
    var ollamaPort = Environment.GetEnvironmentVariable("KHAOS_OLLAMA_PORT") ?? "11434";
    var redisPort = Environment.GetEnvironmentVariable("KHAOS_REDIS_PORT") ?? "6379";
    var postgresPort = Environment.GetEnvironmentVariable("KHAOS_POSTGRES_PORT") ?? "5432";
    
    return Results.Ok(new
    {
        name = Environment.GetEnvironmentVariable("KHAOS_INSTANCE_NAME") ?? "Khaos Server",
        ports = new
        {
            api = int.Parse(apiPort),
            web = int.Parse(webPort),
            ollama = int.Parse(ollamaPort),
            redis = int.Parse(redisPort),
            postgres = int.Parse(postgresPort)
        },
        paths = new
        {
            models = "/usr/share/ollama/.ollama/models",
            apps = "/opt/khaos/apps",
            cache = Environment.GetEnvironmentVariable("KHAOS_CACHE_PATH") ?? "/mnt/khaos-cache",
            logs = "/var/log/khaos"
        },
        urls = new
        {
            swagger = $"http://localhost:{apiPort}/swagger",
            web = $"http://localhost:{webPort}"
        }
    });
});

// ============================================================================
// Health Check
// ============================================================================
app.MapGet("/api/health", async (IConnectionMultiplexer redis, IHttpClientFactory httpFactory, Func<NpgsqlConnection> createConnection) =>
{
    var health = new Dictionary<string, object>
    {
        ["status"] = "healthy",
        ["timestamp"] = DateTime.UtcNow,
        ["instance"] = Environment.GetEnvironmentVariable("KHAOS_INSTANCE_NAME") ?? "Khaos Server"
    };

    // Check Redis
    try
    {
        var db = redis.GetDatabase();
        await db.PingAsync();
        health["redis"] = "connected";
    }
    catch
    {
        health["redis"] = "disconnected";
    }

    // Check PostgreSQL
    try
    {
        await using var conn = createConnection();
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("SELECT 1", conn);
        await cmd.ExecuteScalarAsync();
        health["postgres"] = "connected";
    }
    catch
    {
        health["postgres"] = "disconnected";
    }

    // Check Ollama
    try
    {
        var client = httpFactory.CreateClient("Ollama");
        var response = await client.GetAsync("/api/tags");
        health["ollama"] = response.IsSuccessStatusCode ? "connected" : "error";
    }
    catch
    {
        health["ollama"] = "disconnected";
    }

    return Results.Ok(health);
});

// ============================================================================
// Redis Operations (Cache)
// ============================================================================
app.MapGet("/api/redis/{key}", async (string key, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var value = await db.StringGetAsync(key);
    return value.HasValue ? Results.Ok(new { key, value = value.ToString() }) : Results.NotFound();
});

app.MapPut("/api/redis/{key}", async (string key, JsonElement body, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var value = body.GetProperty("value").GetString();
    await db.StringSetAsync(key, value);
    return Results.Ok(new { key, value });
});

app.MapDelete("/api/redis/{key}", async (string key, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    await db.KeyDeleteAsync(key);
    return Results.NoContent();
});

app.MapGet("/api/redis", async (IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var server = redis.GetServer(redis.GetEndPoints().First());
    var keys = server.Keys(pattern: "*").ToList();

    var result = new Dictionary<string, string?>();
    foreach (var key in keys)
    {
        var value = await db.StringGetAsync(key);
        result[key.ToString()] = value.HasValue ? value.ToString() : null;
    }
    return Results.Ok(result);
});

app.MapPost("/api/redis/bulk", async (Dictionary<string, string> items, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    foreach (var item in items)
    {
        await db.StringSetAsync(item.Key, item.Value);
    }
    return Results.Ok(new { count = items.Count });
});

app.MapDelete("/api/redis", async (IConnectionMultiplexer redis) =>
{
    var server = redis.GetServer(redis.GetEndPoints().First());
    await server.FlushDatabaseAsync();
    return Results.NoContent();
});

// ============================================================================
// Chat Operations (Ollama)
// ============================================================================
app.MapPost("/api/chat", async (JsonElement body, IHttpClientFactory httpFactory) =>
{
    var client = httpFactory.CreateClient("Ollama");

    var message = body.GetProperty("message").GetString();
    var model = body.TryGetProperty("model", out var m) ? m.GetString() : "qwen2.5:3b";

    var request = new
    {
        model,
        prompt = message,
        stream = false
    };

    var response = await client.PostAsJsonAsync("/api/generate", request);
    var result = await response.Content.ReadFromJsonAsync<JsonElement>();

    return Results.Ok(new
    {
        model,
        message,
        response = result.GetProperty("response").GetString()
    });
});

app.MapGet("/api/chat/models", async (IHttpClientFactory httpFactory) =>
{
    var client = httpFactory.CreateClient("Ollama");
    var response = await client.GetFromJsonAsync<JsonElement>("/api/tags");
    return Results.Ok(response);
});

// ============================================================================
// Conversations API (for saving/loading chat history)
// ============================================================================
app.MapGet("/api/conversations", async (IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var server = redis.GetServer(redis.GetEndPoints().First());
    var keys = server.Keys(pattern: "conversation:*").ToList();

    var conversations = new List<dynamic>();
    foreach (var key in keys)
    {
        var data = await db.StringGetAsync(key);
        if (data.HasValue)
        {
            var conv = JsonSerializer.Deserialize<JsonElement>(data.ToString());
            var createdAtStr = conv.TryGetProperty("createdAt", out var c) ? c.GetString() : null;
            conversations.Add(new
            {
                id = key.ToString().Replace("conversation:", ""),
                name = conv.TryGetProperty("name", out var n) ? n.GetString() : "Untitled",
                createdAt = createdAtStr,
                messageCount = conv.TryGetProperty("messages", out var msgs) ? msgs.GetArrayLength() : 0
            });
        }
    }
    return Results.Ok(conversations.OrderByDescending(c => c.createdAt));
});

app.MapGet("/api/conversations/{id}", async (string id, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var data = await db.StringGetAsync($"conversation:{id}");
    if (!data.HasValue) return Results.NotFound();
    return Results.Ok(JsonSerializer.Deserialize<JsonElement>(data.ToString()));
});

app.MapPost("/api/conversations", async (JsonElement body, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var id = Guid.NewGuid().ToString("N")[..8];
    var conversation = new
    {
        id,
        name = body.TryGetProperty("name", out var n) ? n.GetString() : "Untitled",
        createdAt = DateTime.UtcNow.ToString("o"),
        messages = body.TryGetProperty("messages", out var m) ? m : JsonSerializer.Deserialize<JsonElement>("[]"),
        systemPrompt = body.TryGetProperty("systemPrompt", out var s) ? s.GetString() : ""
    };
    await db.StringSetAsync($"conversation:{id}", JsonSerializer.Serialize(conversation));
    return Results.Ok(conversation);
});

app.MapPut("/api/conversations/{id}", async (string id, JsonElement body, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var existing = await db.StringGetAsync($"conversation:{id}");
    if (!existing.HasValue) return Results.NotFound();
    
    await db.StringSetAsync($"conversation:{id}", body.GetRawText());
    return Results.Ok(body);
});

app.MapDelete("/api/conversations/{id}", async (string id, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    await db.KeyDeleteAsync($"conversation:{id}");
    return Results.NoContent();
});

// ============================================================================
// Prompts Library API
// ============================================================================
app.MapGet("/api/prompts", async (IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var server = redis.GetServer(redis.GetEndPoints().First());
    var keys = server.Keys(pattern: "prompt:*").ToList();

    var prompts = new List<JsonElement>();
    foreach (var key in keys)
    {
        var data = await db.StringGetAsync(key);
        if (data.HasValue)
        {
            prompts.Add(JsonSerializer.Deserialize<JsonElement>(data.ToString()));
        }
    }
    return Results.Ok(prompts);
});

app.MapPost("/api/prompts", async (JsonElement body, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var id = Guid.NewGuid().ToString("N")[..8];
    var prompt = new
    {
        id,
        name = body.GetProperty("name").GetString(),
        content = body.GetProperty("content").GetString(),
        category = body.TryGetProperty("category", out var c) ? c.GetString() : "general",
        createdAt = DateTime.UtcNow.ToString("o")
    };
    await db.StringSetAsync($"prompt:{id}", JsonSerializer.Serialize(prompt));
    return Results.Ok(prompt);
});

app.MapDelete("/api/prompts/{id}", async (string id, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    await db.KeyDeleteAsync($"prompt:{id}");
    return Results.NoContent();
});

// ============================================================================
// System Prompts Library API (for saving/loading reusable system prompts)
// ============================================================================
app.MapGet("/api/system-prompts", async (IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var server = redis.GetServer(redis.GetEndPoints().First());
    var keys = server.Keys(pattern: "systemprompt:*").ToList();

    var prompts = new List<JsonElement>();
    foreach (var key in keys)
    {
        var data = await db.StringGetAsync(key);
        if (data.HasValue)
        {
            prompts.Add(JsonSerializer.Deserialize<JsonElement>(data.ToString()));
        }
    }
    // Return unsorted - avoid LINQ OrderBy issues with JsonElement
    return Results.Ok(prompts);
});

app.MapPost("/api/system-prompts", async (JsonElement body, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    var id = Guid.NewGuid().ToString("N")[..8];
    var prompt = new
    {
        id,
        name = body.GetProperty("name").GetString(),
        content = body.GetProperty("content").GetString(),
        createdAt = DateTime.UtcNow.ToString("o")
    };
    await db.StringSetAsync($"systemprompt:{id}", JsonSerializer.Serialize(prompt));
    return Results.Ok(prompt);
});

app.MapDelete("/api/system-prompts/{id}", async (string id, IConnectionMultiplexer redis) =>
{
    var db = redis.GetDatabase();
    await db.KeyDeleteAsync($"systemprompt:{id}");
    return Results.NoContent();
});

// ============================================================================
// Persistent Data Operations (PostgreSQL + Redis Cache)
// ============================================================================
// PostgreSQL is the source of truth, Redis is the cache
// Pattern: Read from cache first, write to DB and update cache

// GET /api/data - List all keys from PostgreSQL
app.MapGet("/api/data", async (Func<NpgsqlConnection> createConnection) =>
{
    await using var conn = createConnection();
    await conn.OpenAsync();
    
    await using var cmd = new NpgsqlCommand(
        "SELECT key, value, created_at, updated_at FROM kv_store ORDER BY key", conn);
    await using var reader = await cmd.ExecuteReaderAsync();
    
    var items = new List<object>();
    while (await reader.ReadAsync())
    {
        items.Add(new
        {
            key = reader.GetString(0),
            value = JsonSerializer.Deserialize<JsonElement>(reader.GetString(1)),
            createdAt = reader.GetDateTime(2),
            updatedAt = reader.GetDateTime(3)
        });
    }
    
    return Results.Ok(new { count = items.Count, items });
});

// GET /api/data/{key} - Read with cache
app.MapGet("/api/data/{key}", async (string key, IConnectionMultiplexer redis, Func<NpgsqlConnection> createConnection) =>
{
    var db = redis.GetDatabase();
    var cacheKey = $"data:{key}";
    
    // Try cache first
    var cached = await db.StringGetAsync(cacheKey);
    if (cached.HasValue)
    {
        return Results.Ok(new
        {
            key,
            value = JsonSerializer.Deserialize<JsonElement>(cached.ToString()),
            source = "cache"
        });
    }
    
    // Cache miss - read from PostgreSQL
    await using var conn = createConnection();
    await conn.OpenAsync();
    
    await using var cmd = new NpgsqlCommand(
        "SELECT value, created_at, updated_at FROM kv_store WHERE key = @key", conn);
    cmd.Parameters.AddWithValue("key", key);
    
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        return Results.NotFound(new { error = $"Key '{key}' not found" });
    }
    
    var value = reader.GetString(0);
    var createdAt = reader.GetDateTime(1);
    var updatedAt = reader.GetDateTime(2);
    
    // Update cache (expire in 5 minutes)
    await db.StringSetAsync(cacheKey, value, TimeSpan.FromMinutes(5));
    
    return Results.Ok(new
    {
        key,
        value = JsonSerializer.Deserialize<JsonElement>(value),
        createdAt,
        updatedAt,
        source = "database"
    });
});

// POST /api/data/{key} - Create or update (write-through cache)
app.MapPost("/api/data/{key}", async (string key, JsonElement body, IConnectionMultiplexer redis, Func<NpgsqlConnection> createConnection) =>
{
    var valueJson = body.GetProperty("value").GetRawText();
    var cacheKey = $"data:{key}";
    
    await using var conn = createConnection();
    await conn.OpenAsync();
    
    // Upsert to PostgreSQL
    await using var cmd = new NpgsqlCommand(@"
        INSERT INTO kv_store (key, value) VALUES (@key, @value::jsonb)
        ON CONFLICT (key) DO UPDATE SET value = @value::jsonb, updated_at = NOW()
        RETURNING created_at, updated_at", conn);
    cmd.Parameters.AddWithValue("key", key);
    cmd.Parameters.AddWithValue("value", valueJson);
    
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    var createdAt = reader.GetDateTime(0);
    var updatedAt = reader.GetDateTime(1);
    
    // Update cache
    var db = redis.GetDatabase();
    await db.StringSetAsync(cacheKey, valueJson, TimeSpan.FromMinutes(5));
    
    return Results.Ok(new
    {
        key,
        value = JsonSerializer.Deserialize<JsonElement>(valueJson),
        createdAt,
        updatedAt,
        persisted = true
    });
});

// PUT /api/data/{key} - Update (same as POST for upsert)
app.MapPut("/api/data/{key}", async (string key, JsonElement body, IConnectionMultiplexer redis, Func<NpgsqlConnection> createConnection) =>
{
    var valueJson = body.GetProperty("value").GetRawText();
    var cacheKey = $"data:{key}";
    
    await using var conn = createConnection();
    await conn.OpenAsync();
    
    // Check if exists
    await using var checkCmd = new NpgsqlCommand("SELECT 1 FROM kv_store WHERE key = @key", conn);
    checkCmd.Parameters.AddWithValue("key", key);
    var exists = await checkCmd.ExecuteScalarAsync() != null;
    
    if (!exists)
    {
        return Results.NotFound(new { error = $"Key '{key}' not found. Use POST to create." });
    }
    
    // Update in PostgreSQL
    await using var cmd = new NpgsqlCommand(@"
        UPDATE kv_store SET value = @value::jsonb, updated_at = NOW() 
        WHERE key = @key
        RETURNING created_at, updated_at", conn);
    cmd.Parameters.AddWithValue("key", key);
    cmd.Parameters.AddWithValue("value", valueJson);
    
    await using var reader = await cmd.ExecuteReaderAsync();
    await reader.ReadAsync();
    var createdAt = reader.GetDateTime(0);
    var updatedAt = reader.GetDateTime(1);
    
    // Update cache
    var db = redis.GetDatabase();
    await db.StringSetAsync(cacheKey, valueJson, TimeSpan.FromMinutes(5));
    
    return Results.Ok(new
    {
        key,
        value = JsonSerializer.Deserialize<JsonElement>(valueJson),
        createdAt,
        updatedAt,
        persisted = true
    });
});

// POST /api/data/bulk - Bulk import to PostgreSQL
app.MapPost("/api/data/bulk", async (Dictionary<string, JsonElement> items, IConnectionMultiplexer redis, Func<NpgsqlConnection> createConnection) =>
{
    await using var conn = createConnection();
    await conn.OpenAsync();
    
    var db = redis.GetDatabase();
    var count = 0;
    
    foreach (var item in items)
    {
        var valueJson = item.Value.GetRawText();
        
        // Upsert to PostgreSQL
        await using var cmd = new NpgsqlCommand(@"
            INSERT INTO kv_store (key, value) VALUES (@key, @value::jsonb)
            ON CONFLICT (key) DO UPDATE SET value = @value::jsonb, updated_at = NOW()", conn);
        cmd.Parameters.AddWithValue("key", item.Key);
        cmd.Parameters.AddWithValue("value", valueJson);
        await cmd.ExecuteNonQueryAsync();
        
        // Update cache
        await db.StringSetAsync($"data:{item.Key}", valueJson, TimeSpan.FromMinutes(5));
        count++;
    }
    
    return Results.Ok(new { count, persisted = true });
});

// DELETE /api/data/{key} - Delete from both
app.MapDelete("/api/data/{key}", async (string key, IConnectionMultiplexer redis, Func<NpgsqlConnection> createConnection) =>
{
    var cacheKey = $"data:{key}";
    
    await using var conn = createConnection();
    await conn.OpenAsync();
    
    // Delete from PostgreSQL
    await using var cmd = new NpgsqlCommand("DELETE FROM kv_store WHERE key = @key", conn);
    cmd.Parameters.AddWithValue("key", key);
    var deleted = await cmd.ExecuteNonQueryAsync();
    
    // Invalidate cache
    var db = redis.GetDatabase();
    await db.KeyDeleteAsync(cacheKey);
    
    if (deleted == 0)
    {
        return Results.NotFound(new { error = $"Key '{key}' not found" });
    }
    
    return Results.Ok(new { key, deleted = true });
});

// DELETE /api/data - Clear all persistent data
app.MapDelete("/api/data", async (IConnectionMultiplexer redis, Func<NpgsqlConnection> createConnection) =>
{
    await using var conn = createConnection();
    await conn.OpenAsync();
    
    // Count and delete from PostgreSQL
    await using var countCmd = new NpgsqlCommand("SELECT COUNT(*) FROM kv_store", conn);
    var count = (long)(await countCmd.ExecuteScalarAsync() ?? 0);
    
    await using var deleteCmd = new NpgsqlCommand("DELETE FROM kv_store", conn);
    await deleteCmd.ExecuteNonQueryAsync();
    
    // Clear data cache keys from Redis
    var db = redis.GetDatabase();
    var server = redis.GetServer(redis.GetEndPoints().First());
    var cacheKeys = server.Keys(pattern: "data:*").ToArray();
    foreach (var cacheKey in cacheKeys)
    {
        await db.KeyDeleteAsync(cacheKey);
    }
    
    return Results.Ok(new { deleted = count, cacheCleared = cacheKeys.Length });
});

// ============================================================================
// Filesystem Operations
// ============================================================================

// GET /api/filesystem/list - List files in a directory
app.MapGet("/api/filesystem/list", (string path, bool? recursive) =>
{
    try
    {
        if (string.IsNullOrEmpty(path))
        {
            return Results.BadRequest(new { error = "Path parameter is required" });
        }

        if (!Directory.Exists(path))
        {
            return Results.NotFound(new { error = $"Directory not found: {path}" });
        }

        var searchOption = recursive == true ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;
        var entries = new List<object>();

        // Get directories
        foreach (var dir in Directory.GetDirectories(path, "*", searchOption))
        {
            try
            {
                var dirInfo = new DirectoryInfo(dir);
                entries.Add(new
                {
                    name = dirInfo.Name,
                    path = dir,
                    type = "directory",
                    createdAt = dirInfo.CreationTimeUtc,
                    modifiedAt = dirInfo.LastWriteTimeUtc,
                    size = (long?)null
                });
            }
            catch { /* Skip inaccessible directories */ }
        }

        // Get files
        foreach (var file in Directory.GetFiles(path, "*", searchOption))
        {
            try
            {
                var fileInfo = new FileInfo(file);
                entries.Add(new
                {
                    name = fileInfo.Name,
                    path = file,
                    type = "file",
                    createdAt = fileInfo.CreationTimeUtc,
                    modifiedAt = fileInfo.LastWriteTimeUtc,
                    size = fileInfo.Length
                });
            }
            catch { /* Skip inaccessible files */ }
        }

        return Results.Ok(new
        {
            path,
            recursive = recursive ?? false,
            count = entries.Count,
            entries
        });
    }
    catch (UnauthorizedAccessException)
    {
        return Results.Forbid();
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// GET /api/filesystem/info - Get file or directory metadata
app.MapGet("/api/filesystem/info", (string path) =>
{
    try
    {
        if (string.IsNullOrEmpty(path))
        {
            return Results.BadRequest(new { error = "Path parameter is required" });
        }

        if (File.Exists(path))
        {
            var fileInfo = new FileInfo(path);
            return Results.Ok(new
            {
                name = fileInfo.Name,
                path = fileInfo.FullName,
                type = "file",
                extension = fileInfo.Extension,
                size = fileInfo.Length,
                sizeFormatted = FormatFileSize(fileInfo.Length),
                createdAt = fileInfo.CreationTimeUtc,
                modifiedAt = fileInfo.LastWriteTimeUtc,
                accessedAt = fileInfo.LastAccessTimeUtc,
                isReadOnly = fileInfo.IsReadOnly,
                exists = true
            });
        }
        else if (Directory.Exists(path))
        {
            var dirInfo = new DirectoryInfo(path);
            var fileCount = 0;
            var dirCount = 0;
            long totalSize = 0;
            
            try
            {
                fileCount = Directory.GetFiles(path, "*", SearchOption.AllDirectories).Length;
                dirCount = Directory.GetDirectories(path, "*", SearchOption.AllDirectories).Length;
                totalSize = Directory.GetFiles(path, "*", SearchOption.AllDirectories)
                    .Sum(f => new FileInfo(f).Length);
            }
            catch { /* Ignore access errors */ }

            return Results.Ok(new
            {
                name = dirInfo.Name,
                path = dirInfo.FullName,
                type = "directory",
                createdAt = dirInfo.CreationTimeUtc,
                modifiedAt = dirInfo.LastWriteTimeUtc,
                fileCount,
                directoryCount = dirCount,
                totalSize,
                totalSizeFormatted = FormatFileSize(totalSize),
                exists = true
            });
        }
        else
        {
            return Results.NotFound(new { error = $"Path not found: {path}", exists = false });
        }
    }
    catch (UnauthorizedAccessException)
    {
        return Results.Forbid();
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// GET /api/filesystem/read - Read file contents
app.MapGet("/api/filesystem/read", async (string path, int? maxSize) =>
{
    try
    {
        if (string.IsNullOrEmpty(path))
        {
            return Results.BadRequest(new { error = "Path parameter is required" });
        }

        if (!File.Exists(path))
        {
            return Results.NotFound(new { error = $"File not found: {path}" });
        }

        var fileInfo = new FileInfo(path);
        var maxBytes = maxSize ?? 1024 * 1024; // Default 1MB limit

        if (fileInfo.Length > maxBytes)
        {
            return Results.BadRequest(new { 
                error = $"File too large. Size: {fileInfo.Length} bytes, limit: {maxBytes} bytes",
                size = fileInfo.Length,
                limit = maxBytes
            });
        }

        // Detect if binary
        var isBinary = IsBinaryFile(path);
        
        if (isBinary)
        {
            var bytes = await File.ReadAllBytesAsync(path);
            return Results.Ok(new
            {
                path,
                name = fileInfo.Name,
                size = fileInfo.Length,
                encoding = "base64",
                isBinary = true,
                content = Convert.ToBase64String(bytes)
            });
        }
        else
        {
            var content = await File.ReadAllTextAsync(path);
            var lines = content.Split('\n').Length;
            return Results.Ok(new
            {
                path,
                name = fileInfo.Name,
                size = fileInfo.Length,
                encoding = "utf-8",
                isBinary = false,
                lineCount = lines,
                content
            });
        }
    }
    catch (UnauthorizedAccessException)
    {
        return Results.Forbid();
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// POST /api/filesystem/copy - Copy a file
app.MapPost("/api/filesystem/copy", (JsonElement body) =>
{
    try
    {
        if (!body.TryGetProperty("source", out var sourceEl) || string.IsNullOrEmpty(sourceEl.GetString()))
        {
            return Results.BadRequest(new { error = "Source path is required" });
        }
        if (!body.TryGetProperty("destination", out var destEl) || string.IsNullOrEmpty(destEl.GetString()))
        {
            return Results.BadRequest(new { error = "Destination path is required" });
        }

        var source = sourceEl.GetString()!;
        var destination = destEl.GetString()!;
        var overwrite = body.TryGetProperty("overwrite", out var ow) && ow.GetBoolean();

        if (!File.Exists(source))
        {
            return Results.NotFound(new { error = $"Source file not found: {source}" });
        }

        if (File.Exists(destination) && !overwrite)
        {
            return Results.Conflict(new { error = $"Destination file already exists: {destination}. Set overwrite=true to replace." });
        }

        // Ensure destination directory exists
        var destDir = Path.GetDirectoryName(destination);
        if (!string.IsNullOrEmpty(destDir) && !Directory.Exists(destDir))
        {
            Directory.CreateDirectory(destDir);
        }

        File.Copy(source, destination, overwrite);

        var destInfo = new FileInfo(destination);
        return Results.Ok(new
        {
            source,
            destination,
            size = destInfo.Length,
            copied = true,
            overwritten = overwrite && File.Exists(destination)
        });
    }
    catch (UnauthorizedAccessException)
    {
        return Results.Forbid();
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// Helper function to format file size
static string FormatFileSize(long bytes)
{
    string[] sizes = { "B", "KB", "MB", "GB", "TB" };
    double len = bytes;
    int order = 0;
    while (len >= 1024 && order < sizes.Length - 1)
    {
        order++;
        len /= 1024;
    }
    return $"{len:0.##} {sizes[order]}";
}

// Helper function to detect binary files
static bool IsBinaryFile(string path)
{
    var binaryExtensions = new[] { ".exe", ".dll", ".so", ".bin", ".zip", ".tar", ".gz", ".7z", ".rar", 
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".pdf", ".doc", ".docx", ".xls", ".xlsx",
        ".ppt", ".pptx", ".mp3", ".mp4", ".avi", ".mov", ".wmv", ".wasm" };
    
    var ext = Path.GetExtension(path).ToLowerInvariant();
    if (binaryExtensions.Contains(ext)) return true;

    // Check first few bytes for null characters
    try
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read);
        var buffer = new byte[8000];
        var bytesRead = stream.Read(buffer, 0, buffer.Length);
        for (int i = 0; i < bytesRead; i++)
        {
            if (buffer[i] == 0) return true;
        }
    }
    catch { }
    
    return false;
}

// ============================================================================
// Disk Info - Get disk space information
// ============================================================================

// GET /api/disk/info - Get overall disk space information
app.MapGet("/api/disk/info", () =>
{
    try
    {
        var drives = DriveInfo.GetDrives()
            .Where(d => d.IsReady)
            .Select(d => new
            {
                name = d.Name,
                label = d.VolumeLabel,
                type = d.DriveType.ToString(),
                format = d.DriveFormat,
                totalBytes = d.TotalSize,
                freeBytes = d.AvailableFreeSpace,
                usedBytes = d.TotalSize - d.AvailableFreeSpace,
                totalFormatted = FormatFileSize(d.TotalSize),
                freeFormatted = FormatFileSize(d.AvailableFreeSpace),
                usedFormatted = FormatFileSize(d.TotalSize - d.AvailableFreeSpace),
                percentUsed = Math.Round((double)(d.TotalSize - d.AvailableFreeSpace) / d.TotalSize * 100, 2)
            })
            .ToList();

        return Results.Ok(new
        {
            timestamp = DateTime.UtcNow,
            drives
        });
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// GET /api/disk/folders - Get folder sizes for a directory
app.MapGet("/api/disk/folders", (string? path, int? depth, int? limit) =>
{
    try
    {
        var targetPath = string.IsNullOrEmpty(path) ? "/" : path;
        var maxDepth = depth ?? 1;
        var maxResults = limit ?? 20;

        if (!Directory.Exists(targetPath))
        {
            return Results.NotFound(new { error = "Directory not found", path = targetPath });
        }

        var folders = new List<object>();
        var dirInfo = new DirectoryInfo(targetPath);

        foreach (var subDir in dirInfo.EnumerateDirectories())
        {
            try
            {
                var size = GetDirectorySize(subDir.FullName, maxDepth);
                folders.Add(new
                {
                    path = subDir.FullName,
                    name = subDir.Name,
                    sizeBytes = size,
                    sizeFormatted = FormatFileSize(size),
                    itemCount = TryGetItemCount(subDir.FullName)
                });
            }
            catch (UnauthorizedAccessException)
            {
                folders.Add(new
                {
                    path = subDir.FullName,
                    name = subDir.Name,
                    sizeBytes = (long)-1,
                    sizeFormatted = "Access Denied",
                    itemCount = -1
                });
            }
            catch { }
        }

        // Sort by size descending and take top N
        var sortedFolders = folders
            .OrderByDescending(f => ((dynamic)f).sizeBytes)
            .Take(maxResults)
            .ToList();

        // Calculate total size of files in the target directory
        long filesSize = 0;
        try
        {
            filesSize = dirInfo.EnumerateFiles().Sum(f => f.Length);
        }
        catch { }

        return Results.Ok(new
        {
            path = targetPath,
            timestamp = DateTime.UtcNow,
            totalFilesSize = filesSize,
            totalFilesSizeFormatted = FormatFileSize(filesSize),
            folders = sortedFolders
        });
    }
    catch (UnauthorizedAccessException)
    {
        return Results.Forbid();
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// Helper function to get directory size
static long GetDirectorySize(string path, int maxDepth)
{
    if (maxDepth <= 0) return 0;

    long size = 0;
    var dirInfo = new DirectoryInfo(path);

    try
    {
        foreach (var file in dirInfo.EnumerateFiles())
        {
            try { size += file.Length; } catch { }
        }

        foreach (var subDir in dirInfo.EnumerateDirectories())
        {
            try { size += GetDirectorySize(subDir.FullName, maxDepth - 1); } catch { }
        }
    }
    catch { }

    return size;
}

// Helper function to get item count
static int TryGetItemCount(string path)
{
    try
    {
        var dirInfo = new DirectoryInfo(path);
        return dirInfo.EnumerateFileSystemInfos().Count();
    }
    catch { return -1; }
}

// ============================================================================
// RAG (Retrieval Augmented Generation) - File-based Q&A with Ollama
// ============================================================================

// POST /api/rag/index - Index files for RAG querying
app.MapPost("/api/rag/index", async (HttpRequest request, IConnectionMultiplexer redis, IHttpClientFactory httpClientFactory) =>
{
    try
    {
        var body = await request.ReadFromJsonAsync<RagIndexRequest>();
        if (body == null || string.IsNullOrEmpty(body.Path))
        {
            return Results.BadRequest(new { error = "Path is required" });
        }

        if (!Directory.Exists(body.Path) && !File.Exists(body.Path))
        {
            return Results.NotFound(new { error = "Path not found", path = body.Path });
        }

        var db = redis.GetDatabase();
        var files = new List<string>();
        var extensions = body.Extensions ?? new[] { ".txt", ".md", ".cs", ".py", ".js", ".ts", ".json", ".xml", ".yaml", ".yml", ".html", ".css", ".vue" };

        // Collect files to index
        if (File.Exists(body.Path))
        {
            files.Add(body.Path);
        }
        else
        {
            var searchOption = body.Recursive ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;
            foreach (var ext in extensions)
            {
                try
                {
                    files.AddRange(Directory.GetFiles(body.Path, $"*{ext}", searchOption));
                }
                catch { }
            }
        }

        // Limit number of files
        var maxFiles = body.MaxFiles ?? 100;
        files = files.Take(maxFiles).ToList();

        var indexed = new List<object>();
        var indexKey = $"rag:index:{body.IndexName ?? "default"}";

        foreach (var file in files)
        {
            try
            {
                var content = await File.ReadAllTextAsync(file);
                if (content.Length > 50000) content = content.Substring(0, 50000) + "\n...[truncated]";

                // Store file content in Redis for RAG queries
                var fileKey = $"rag:file:{Path.GetFileName(file)}:{Guid.NewGuid():N}";
                await db.HashSetAsync(fileKey, new HashEntry[]
                {
                    new("path", file),
                    new("name", Path.GetFileName(file)),
                    new("content", content),
                    new("indexed", DateTime.UtcNow.ToString("o")),
                    new("size", content.Length)
                });

                // Add to index set
                await db.SetAddAsync(indexKey, fileKey);

                indexed.Add(new
                {
                    path = file,
                    name = Path.GetFileName(file),
                    size = content.Length
                });
            }
            catch (Exception ex)
            {
                indexed.Add(new
                {
                    path = file,
                    name = Path.GetFileName(file),
                    error = ex.Message
                });
            }
        }

        return Results.Ok(new
        {
            indexName = body.IndexName ?? "default",
            filesIndexed = indexed.Count(i => !((dynamic)i).GetType().GetProperty("error")?.GetValue(i, null) != null),
            files = indexed
        });
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// POST /api/rag/query - Query indexed files using RAG
app.MapPost("/api/rag/query", async (HttpRequest request, IConnectionMultiplexer redis, IHttpClientFactory httpClientFactory) =>
{
    try
    {
        var body = await request.ReadFromJsonAsync<RagQueryRequest>();
        if (body == null || string.IsNullOrEmpty(body.Question))
        {
            return Results.BadRequest(new { error = "Question is required" });
        }

        var db = redis.GetDatabase();
        var indexKey = $"rag:index:{body.IndexName ?? "default"}";

        // Get all indexed files
        var fileKeys = await db.SetMembersAsync(indexKey);
        if (fileKeys.Length == 0)
        {
            return Results.NotFound(new { error = "No files indexed. Use POST /api/rag/index first." });
        }

        // Build context from indexed files
        var contextBuilder = new System.Text.StringBuilder();
        var sources = new List<object>();
        var maxContextLength = body.MaxContext ?? 30000;

        foreach (var fileKey in fileKeys)
        {
            var fileData = await db.HashGetAllAsync(fileKey.ToString());
            if (fileData.Length == 0) continue;

            var fileDict = fileData.ToDictionary(x => x.Name.ToString(), x => x.Value.ToString());
            var fileName = fileDict.GetValueOrDefault("name", "unknown");
            var filePath = fileDict.GetValueOrDefault("path", "unknown");
            var content = fileDict.GetValueOrDefault("content", "");

            // Simple keyword matching to prioritize relevant files
            var questionLower = body.Question.ToLower();
            var relevanceScore = 0;
            if (fileName.ToLower().Contains(questionLower) || questionLower.Contains(fileName.ToLower())) relevanceScore += 10;
            foreach (var word in questionLower.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                if (word.Length > 2 && content.ToLower().Contains(word)) relevanceScore++;
            }

            sources.Add(new { path = filePath, name = fileName, relevance = relevanceScore, size = content.Length });

            if (contextBuilder.Length + content.Length < maxContextLength)
            {
                contextBuilder.AppendLine($"=== File: {fileName} ===");
                contextBuilder.AppendLine($"Path: {filePath}");
                contextBuilder.AppendLine(content);
                contextBuilder.AppendLine();
            }
        }

        var context = contextBuilder.ToString();

        // Query Ollama with context
        var client = httpClientFactory.CreateClient("Ollama");
        var model = body.Model ?? "llama3.2";

        var prompt = $@"You are a helpful assistant that answers questions based on the provided file contents.

CONTEXT (indexed files):
{context}

USER QUESTION: {body.Question}

Instructions:
- Answer based ONLY on the information in the provided files
- If the answer is not in the files, say so clearly
- Quote relevant parts of the files when appropriate
- Mention which file(s) contain the relevant information

ANSWER:";

        var ollamaRequest = new
        {
            model,
            prompt,
            stream = false,
            options = new { temperature = 0.3 }
        };

        var response = await client.PostAsJsonAsync("/api/generate", ollamaRequest);
        
        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return Results.BadRequest(new { error = $"Ollama error: {error}" });
        }

        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        var answer = result.GetProperty("response").GetString();

        return Results.Ok(new
        {
            question = body.Question,
            answer,
            model,
            indexName = body.IndexName ?? "default",
            sourcesUsed = sources.OrderByDescending(s => ((dynamic)s).relevance).Take(10),
            contextLength = context.Length
        });
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// GET /api/rag/indexes - List all RAG indexes
app.MapGet("/api/rag/indexes", async (IConnectionMultiplexer redis) =>
{
    try
    {
        var db = redis.GetDatabase();
        var server = redis.GetServer(redis.GetEndPoints().First());
        var keys = server.Keys(pattern: "rag:index:*").ToList();

        var indexes = new List<object>();
        foreach (var key in keys)
        {
            var indexName = key.ToString().Replace("rag:index:", "");
            var fileCount = await db.SetLengthAsync(key.ToString());
            indexes.Add(new { name = indexName, fileCount });
        }

        return Results.Ok(new { indexes });
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

// DELETE /api/rag/index/{name} - Delete a RAG index
app.MapDelete("/api/rag/index/{name}", async (string name, IConnectionMultiplexer redis) =>
{
    try
    {
        var db = redis.GetDatabase();
        var indexKey = $"rag:index:{name}";

        // Get all file keys in the index
        var fileKeys = await db.SetMembersAsync(indexKey);

        // Delete all file entries
        foreach (var fileKey in fileKeys)
        {
            await db.KeyDeleteAsync(fileKey.ToString());
        }

        // Delete the index
        await db.KeyDeleteAsync(indexKey);

        return Results.Ok(new { deleted = true, indexName = name, filesRemoved = fileKeys.Length });
    }
    catch (Exception ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

app.Run();

// RAG request models
record RagIndexRequest(string Path, string? IndexName, string[]? Extensions, bool Recursive = true, int? MaxFiles = 100);
record RagQueryRequest(string Question, string? IndexName, string? Model, int? MaxContext = 30000);
