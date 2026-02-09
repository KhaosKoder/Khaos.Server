using System.Text.Json;
using System.Net.Http.Json;
using StackExchange.Redis;

var builder = WebApplication.CreateBuilder(args);

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
    var config = ConfigurationOptions.Parse("localhost:6379");
    config.AbortOnConnectFail = false;
    config.AllowAdmin = true;
    return ConnectionMultiplexer.Connect(config);
});

// HttpClient for Ollama
builder.Services.AddHttpClient("Ollama", client =>
{
    client.BaseAddress = new Uri("http://localhost:11434");
    client.Timeout = TimeSpan.FromMinutes(5);
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();
app.UseCors();

// ============================================================================
// Health Check
// ============================================================================
app.MapGet("/api/health", async (IConnectionMultiplexer redis, IHttpClientFactory httpFactory) =>
{
    var health = new Dictionary<string, object>
    {
        ["status"] = "healthy",
        ["timestamp"] = DateTime.UtcNow
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

    var conversations = new List<object>();
    foreach (var key in keys)
    {
        var data = await db.StringGetAsync(key);
        if (data.HasValue)
        {
            var conv = JsonSerializer.Deserialize<JsonElement>(data.ToString());
            conversations.Add(new
            {
                id = key.ToString().Replace("conversation:", ""),
                name = conv.TryGetProperty("name", out var n) ? n.GetString() : "Untitled",
                createdAt = conv.TryGetProperty("createdAt", out var c) ? c.GetString() : null,
                messageCount = conv.TryGetProperty("messages", out var msgs) ? msgs.GetArrayLength() : 0
            });
        }
    }
    return Results.Ok(conversations.OrderByDescending(c => ((dynamic)c).createdAt));
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

    var prompts = new List<object>();
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

    var prompts = new List<object>();
    foreach (var key in keys)
    {
        var data = await db.StringGetAsync(key);
        if (data.HasValue)
        {
            prompts.Add(JsonSerializer.Deserialize<JsonElement>(data.ToString()));
        }
    }
    return Results.Ok(prompts.OrderBy(p => ((dynamic)p).name));
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

app.Run("http://0.0.0.0:5000");
