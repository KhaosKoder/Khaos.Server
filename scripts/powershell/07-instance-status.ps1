# 07-instance-status.ps1
# List all Khaos WSL instances with running status, ports, and service health

param(
    [string]$Name = ""   # Optional: filter to specific instance
)

$ErrorActionPreference = "Stop"

# Get script directory and load dependencies
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\config.ps1"
. "$ScriptDir\utils.ps1"

Write-Host ""
Write-Host "╔═════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║               KHAOS - INSTANCE STATUS & PORTS                      ║" -ForegroundColor Cyan
Write-Host "╚═════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Get all WSL distributions and clean up encoding
$wslOutput = (wsl --list --verbose 2>&1) | ForEach-Object { $_ -replace '[^\x20-\x7E]', '' }

# Parse WSL output to find khaos instances
$instances = @()

foreach ($line in $wslOutput) {
    $cleanLine = $line.Trim()
    
    # Skip header and empty lines
    if ($cleanLine -match '^NAME' -or $cleanLine -eq '') { continue }
    
    # Match lines with khaos- prefix
    if ($cleanLine -match '^(\*)?\s*(khaos-\S+)\s+(\S+)\s+(\d+)') {
        $isDefault = $Matches[1] -eq '*'
        $instanceName = $Matches[2].Trim()
        $state = $Matches[3].Trim()
        $version = $Matches[4].Trim()
        
        # Apply name filter if specified
        if ($Name -and $instanceName -ne "khaos-$Name") { continue }
        
        $instances += [PSCustomObject]@{
            Default = if ($isDefault) { "*" } else { " " }
            Name = $instanceName
            ShortName = $instanceName -replace '^khaos-', ''
            State = $state
            WSL = $version
            Ports = $null
            Services = $null
        }
    }
}

if ($instances.Count -eq 0) {
    if ($Name) {
        Write-Host "  Instance 'khaos-$Name' not found." -ForegroundColor Yellow
    } else {
        Write-Host "  No Khaos instances found." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Create one with: .\01-create-instance.ps1 -Name <instance-name>" -ForegroundColor Gray
    exit 0
}

Write-Host "  Found $($instances.Count) Khaos instance(s):" -ForegroundColor Green
Write-Host ""

# Get detailed info for each running instance
foreach ($inst in $instances) {
    if ($inst.State -eq "Running") {
        # Get port configuration from instance using grep (more reliable than source)
        try {
            $configContent = wsl -d $inst.Name -u root -- cat /etc/khaos/khaos.conf 2>$null
            if ($configContent) {
                $webPort = ($configContent | Select-String 'KHAOS_WEB_PORT=(\d+)').Matches.Groups[1].Value
                $apiPort = ($configContent | Select-String 'KHAOS_API_PORT=(\d+)').Matches.Groups[1].Value
                $ollamaPort = ($configContent | Select-String 'KHAOS_OLLAMA_PORT=(\d+)').Matches.Groups[1].Value
                $redisPort = ($configContent | Select-String 'KHAOS_REDIS_PORT=(\d+)').Matches.Groups[1].Value
                $postgresPort = ($configContent | Select-String 'KHAOS_POSTGRES_PORT=(\d+)').Matches.Groups[1].Value
                
                if ($webPort -and $apiPort) {
                    $inst.Ports = @{
                        Web = [int]$webPort
                        API = [int]$apiPort
                        Ollama = [int]$ollamaPort
                        Redis = [int]$redisPort
                        Postgres = [int]$postgresPort
                    }
                }
            }
        } catch {
            # Ignore errors reading config
        }
        
        # Check service health
        try {
            $services = @{
                API = $false
                Redis = $false
                Ollama = $false
                Postgres = $false
            }
            
            # Check if services are listening on their ports
            $listenCheck = wsl -d $inst.Name -u root -- bash -c "ss -tlnp 2>/dev/null" 2>$null
            if ($listenCheck) {
                if ($inst.Ports) {
                    $services.API = $listenCheck -match ":$($inst.Ports.API)\s"
                    $services.Redis = $listenCheck -match ":$($inst.Ports.Redis)\s"
                    $services.Ollama = $listenCheck -match ":$($inst.Ports.Ollama)\s"
                    $services.Postgres = $listenCheck -match ":$($inst.Ports.Postgres)\s"
                }
            }
            $inst.Services = $services
        } catch {
            # Ignore errors
        }
    }
}

# Display each instance
$boxWidth = 69  # Inner width between │ and │ (fits 80-col terminal with 2-space indent)

foreach ($inst in $instances) {
    Write-Host "  ┌$("─" * $boxWidth)┐" -ForegroundColor DarkGray
    
    # Instance name and state
    $stateColor = switch ($inst.State) {
        "Running" { "Green" }
        "Stopped" { "Yellow" }
        default { "White" }
    }
    
    $defaultMark = if ($inst.Default -eq "*") { " [DEFAULT]" } else { "" }
    $leftContent = "$($inst.Name)$defaultMark"
    $rightContent = $inst.State
    $padding = $boxWidth - $leftContent.Length - $rightContent.Length - 2
    
    Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
    Write-Host $leftContent -ForegroundColor Cyan -NoNewline
    Write-Host (" " * $padding) -NoNewline
    Write-Host $rightContent -ForegroundColor $stateColor -NoNewline
    Write-Host " │" -ForegroundColor DarkGray
    
    if ($inst.State -eq "Running" -and $inst.Ports) {
        Write-Host "  ├$("─" * $boxWidth)┤" -ForegroundColor DarkGray
        
        # Port information - line 1
        $line1 = "Web: $($inst.Ports.Web)   API: $($inst.Ports.API)   Ollama: $($inst.Ports.Ollama)"
        $pad1 = $boxWidth - $line1.Length - 2
        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Web: " -NoNewline -ForegroundColor Gray
        Write-Host "$($inst.Ports.Web)" -NoNewline -ForegroundColor Yellow
        Write-Host "   API: " -NoNewline -ForegroundColor Gray
        Write-Host "$($inst.Ports.API)" -NoNewline -ForegroundColor Yellow
        Write-Host "   Ollama: " -NoNewline -ForegroundColor Gray
        Write-Host "$($inst.Ports.Ollama)" -NoNewline -ForegroundColor Yellow
        Write-Host (" " * $pad1) -NoNewline
        Write-Host " │" -ForegroundColor DarkGray
        
        # Port information - line 2
        $line2 = "Redis: $($inst.Ports.Redis)   PostgreSQL: $($inst.Ports.Postgres)"
        $pad2 = $boxWidth - $line2.Length - 2
        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Redis: " -NoNewline -ForegroundColor Gray
        Write-Host "$($inst.Ports.Redis)" -NoNewline -ForegroundColor Yellow
        Write-Host "   PostgreSQL: " -NoNewline -ForegroundColor Gray
        Write-Host "$($inst.Ports.Postgres)" -NoNewline -ForegroundColor Yellow
        Write-Host (" " * $pad2) -NoNewline
        Write-Host " │" -ForegroundColor DarkGray
        
        # Service status
        if ($inst.Services) {
            $svcApi = if ($inst.Services.API) { "●" } else { "○" }
            $svcRedis = if ($inst.Services.Redis) { "●" } else { "○" }
            $svcOllama = if ($inst.Services.Ollama) { "●" } else { "○" }
            $svcPostgres = if ($inst.Services.Postgres) { "●" } else { "○" }
            
            $apiColor = if ($inst.Services.API) { "Green" } else { "Red" }
            $redisColor = if ($inst.Services.Redis) { "Green" } else { "Red" }
            $ollamaColor = if ($inst.Services.Ollama) { "Green" } else { "Red" }
            $postgresColor = if ($inst.Services.Postgres) { "Green" } else { "Red" }
            
            Write-Host "  ├$("─" * $boxWidth)┤" -ForegroundColor DarkGray
            
            $statusLine = "API X   Redis X   Ollama X   PostgreSQL X"
            $statusPadding = $boxWidth - $statusLine.Length - 2
            
            Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
            Write-Host "API " -NoNewline -ForegroundColor Gray
            Write-Host $svcApi -NoNewline -ForegroundColor $apiColor
            Write-Host "   Redis " -NoNewline -ForegroundColor Gray
            Write-Host $svcRedis -NoNewline -ForegroundColor $redisColor
            Write-Host "   Ollama " -NoNewline -ForegroundColor Gray
            Write-Host $svcOllama -NoNewline -ForegroundColor $ollamaColor
            Write-Host "   PostgreSQL " -NoNewline -ForegroundColor Gray
            Write-Host $svcPostgres -NoNewline -ForegroundColor $postgresColor
            Write-Host (" " * $statusPadding) -NoNewline
            Write-Host " │" -ForegroundColor DarkGray
        }
        
        Write-Host "  ├$("─" * $boxWidth)┤" -ForegroundColor DarkGray
        
        # URLs - Dashboard
        $webUrl = "http://localhost:$($inst.Ports.Web)"
        $urlLine1 = "Dashboard: $webUrl"
        $urlPad1 = $boxWidth - $urlLine1.Length - 2
        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Dashboard: " -NoNewline -ForegroundColor Gray
        Write-Host $webUrl -NoNewline -ForegroundColor Cyan
        Write-Host (" " * $urlPad1) -NoNewline
        Write-Host " │" -ForegroundColor DarkGray
        
        # URLs - Swagger
        $swaggerUrl = "http://localhost:$($inst.Ports.API)/swagger"
        $urlLine2 = "Swagger:   $swaggerUrl"
        $urlPad2 = $boxWidth - $urlLine2.Length - 2
        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Swagger:   " -NoNewline -ForegroundColor Gray
        Write-Host $swaggerUrl -NoNewline -ForegroundColor Cyan
        Write-Host (" " * $urlPad2) -NoNewline
        Write-Host " │" -ForegroundColor DarkGray
        
    } elseif ($inst.State -eq "Stopped") {
        $hintText = "(Start: .\04-start-instance.ps1 -Name $($inst.ShortName))"
        $hintPadding = $boxWidth - $hintText.Length - 2
        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        Write-Host $hintText -ForegroundColor Gray -NoNewline
        Write-Host (" " * $hintPadding) -NoNewline
        Write-Host " │" -ForegroundColor DarkGray
    }
    
    Write-Host "  └$("─" * $boxWidth)┘" -ForegroundColor DarkGray
    Write-Host ""
}

# Summary
Write-Host "  $("─" * $boxWidth)" -ForegroundColor DarkGray
$runningCount = ($instances | Where-Object { $_.State -eq "Running" }).Count
$stoppedCount = ($instances | Where-Object { $_.State -eq "Stopped" }).Count
Write-Host "  Total: $($instances.Count) instance(s)  │  " -NoNewline -ForegroundColor Gray
Write-Host "Running: $runningCount" -NoNewline -ForegroundColor Green
Write-Host "  │  " -NoNewline -ForegroundColor Gray
Write-Host "Stopped: $stoppedCount" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Legend: ● = Service listening  │  ○ = Service not detected" -ForegroundColor DarkGray
Write-Host ""
