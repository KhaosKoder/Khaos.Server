# Khaos Server Configuration
# All versions, paths, and URLs in one place

$script:KhaosConfig = @{
    # Base paths
    CacheRoot = Join-Path $env:USERPROFILE ".khaos\cache"
    LogRoot = Join-Path $env:USERPROFILE ".khaos\logs"
    InstanceRoot = Join-Path $env:USERPROFILE ".khaos\instances"
    
    # Linux Distribution
    Linux = @{
        Distro = "Ubuntu-24.04"
        DownloadUrl = "https://wslstorestorage.blob.core.windows.net/wslblob/Ubuntu2404-240425.AppxBundle"
        FileName = "Ubuntu2404.AppxBundle"
    }
    
    # Ollama
    Ollama = @{
        Version = "latest"
        InstallScript = "https://ollama.ai/install.sh"
    }
    
    # LLM Models (user can select from these)
    Models = @(
        @{ Name = "qwen2.5:3b"; Size = "2.0GB"; Description = "Default - Balanced performance"; Default = $true }
        @{ Name = "qwen2.5:1.5b"; Size = "1.0GB"; Description = "Fastest, lowest memory" }
        @{ Name = "qwen2.5:7b"; Size = "4.5GB"; Description = "Better reasoning" }
        @{ Name = "phi3:mini"; Size = "2.3GB"; Description = "Microsoft, good for code" }
        @{ Name = "llama3.2:3b"; Size = "2.0GB"; Description = "Meta, general purpose" }
        @{ Name = "mistral:7b"; Size = "4.1GB"; Description = "Strong reasoning" }
    )
    
    # Python
    Python = @{
        Version = "3.12"
        Packages = @(
            "langchain"
            "langchain-community"
            "sentence-transformers"
            "chromadb"
            "httpx"
            "redis"
        )
    }
    
    # .NET
    DotNet = @{
        Version = "10.0"
        InstallScript = "https://dot.net/v1/dotnet-install.sh"
    }
    
    # Node.js
    Node = @{
        Version = "22"
    }
    
    # Ports
    Ports = @{
        Vue = 3000
        Api = 5000
        Ollama = 11434
        Redis = 6379
        Postgres = 5432
        NginxHttp = 80
        NginxHttps = 443
    }
    
    # WSL Mount
    WslCacheMount = "/mnt/khaos-cache"
}

# Export config
function Get-KhaosConfig {
    return $script:KhaosConfig
}

# Get default model
function Get-DefaultModel {
    $config = Get-KhaosConfig
    return ($config.Models | Where-Object { $_.Default -eq $true } | Select-Object -First 1).Name
}

# Display available models
function Show-AvailableModels {
    $config = Get-KhaosConfig
    $cachePath = Join-Path $config.CacheRoot "models"
    
    Write-Host "`nAvailable LLM Models:" -ForegroundColor Cyan
    Write-Host ("-" * 70)
    
    foreach ($model in $config.Models) {
        $cached = Test-Path (Join-Path $cachePath ($model.Name -replace ":", "_"))
        $status = if ($cached) { "[CACHED]" } else { "" }
        $default = if ($model.Default) { "(default)" } else { "" }
        
        $color = if ($cached) { "Green" } else { "White" }
        Write-Host ("{0,-20} {1,-10} {2,-30} {3} {4}" -f $model.Name, $model.Size, $model.Description, $default, $status) -ForegroundColor $color
    }
    Write-Host ""
}

# Note: When dot-sourced, all functions are available in caller's scope
