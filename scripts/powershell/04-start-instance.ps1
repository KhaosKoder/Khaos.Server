# 04-start-instance.ps1
# Start a Khaos WSL instance and all its services

param(
    [Parameter(Mandatory=$true)]
    [string]$Name
)

$ErrorActionPreference = "Stop"

# Get script directory and load dependencies
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\config.ps1"
. "$ScriptDir\utils.ps1"

# Ensure khaos- prefix
if (-not $Name.StartsWith("khaos-")) {
    $InstanceName = "khaos-$Name"
} else {
    $InstanceName = $Name
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  KHAOS - START INSTANCE                           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if instance exists (clean up WSL output encoding issues)
$wslList = (wsl --list --quiet 2>&1) -replace '[^\x20-\x7E]', '' -join "`n"
if ($wslList -notmatch [regex]::Escape($InstanceName)) {
    Write-KhaosLog -Status "FAIL" -Step "Check Instance" -Message "Instance '$InstanceName' not found"
    Write-Host ""
    Write-Host "  Available instances:" -ForegroundColor Yellow
    wsl --list --quiet 2>&1 | Where-Object { $_ -match "khaos-" } | ForEach-Object {
        Write-Host "    - $_" -ForegroundColor Gray
    }
    exit 1
}

Write-KhaosLog -Status "START" -Step "Start Instance" -Message "Starting $InstanceName..."

# Start the WSL instance by running a simple command
$startResult = wsl -d $InstanceName -- echo "Instance started" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-KhaosLog -Status "FAIL" -Step "Start Instance" -Message "Failed to start WSL instance"
    exit 1
}

Write-KhaosLog -Status "SUCCESS" -Step "Start Instance" -Message "WSL instance is running"

# With systemd enabled, services start automatically when WSL boots
# Just verify they're running
Write-KhaosLog -Status "START" -Step "Verify Services" -Message "Checking systemd services..."

$services = @("redis-server", "postgresql", "nginx", "khaos-api", "khaos-web")
$allRunning = $true

foreach ($service in $services) {
    $status = wsl -d $InstanceName -u root -- systemctl is-active $service 2>&1
    if ($status -eq "active") {
        Write-KhaosLog -Status "SUCCESS" -Step $service -Message "Running"
    } else {
        Write-KhaosLog -Status "WARN" -Step $service -Message "Not running, attempting start..."
        wsl -d $InstanceName -u root -- systemctl start $service 2>&1 | Out-Null
        $status = wsl -d $InstanceName -u root -- systemctl is-active $service 2>&1
        if ($status -eq "active") {
            Write-KhaosLog -Status "SUCCESS" -Step $service -Message "Started successfully"
        } else {
            Write-KhaosLog -Status "FAIL" -Step $service -Message "Failed to start"
            $allRunning = $false
        }
    }
}

# Also check Ollama (runs independently, not via systemd)
$ollamaCheck = wsl -d $InstanceName -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:11434 2>&1
if ($ollamaCheck -eq "200") {
    Write-KhaosLog -Status "SUCCESS" -Step "ollama" -Message "Running"
} else {
    Write-KhaosLog -Status "WARN" -Step "ollama" -Message "Starting Ollama..."
    wsl -d $InstanceName -u root -- bash -c "ollama serve > /dev/null 2>&1 &"
}

Write-Host ""
if ($allRunning) {
    Write-KhaosLog -Status "SUCCESS" -Step "Complete" -Message "$InstanceName is ready!"
} else {
    Write-KhaosLog -Status "WARN" -Step "Complete" -Message "$InstanceName started with some service issues"
}
Write-Host ""
Write-Host "  Open in browser: " -NoNewline -ForegroundColor White
Write-Host "https://localhost" -ForegroundColor Green
Write-Host ""
