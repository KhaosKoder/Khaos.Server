# 05-stop-instance.ps1
# Stop a Khaos WSL instance gracefully

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
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
Write-Host "║                  KHAOS - STOP INSTANCE                            ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if instance exists (clean up WSL output encoding issues)
$wslList = (wsl --list --quiet 2>&1) -replace '[^\x20-\x7E]', '' -join "`n"
if ($wslList -notmatch [regex]::Escape($InstanceName)) {
    Write-KhaosLog -Status "FAIL" -Step "Check Instance" -Message "Instance '$InstanceName' not found"
    exit 1
}

# Check if already stopped
$wslStatus = wsl --list --verbose 2>&1
if ($wslStatus -match "$InstanceName\s+Stopped") {
    Write-KhaosLog -Status "INFO" -Step "Check Status" -Message "Instance '$InstanceName' is already stopped"
    exit 0
}

if (-not $Force) {
    Write-KhaosLog -Status "START" -Step "Graceful Stop" -Message "Stopping services gracefully..."
    
    # Stop services gracefully
    $stopScript = @'
#!/bin/bash
echo "Stopping services..."

# Stop Vue dev server
pkill -f "npm run dev" 2>/dev/null || true
pkill -f "vite" 2>/dev/null || true
echo "  ✓ Vue frontend stopped"

# Stop .NET API
pkill -f "dotnet.*KhaosApi" 2>/dev/null || true
echo "  ✓ .NET API stopped"

# Stop Ollama
pkill -f "ollama serve" 2>/dev/null || true
echo "  ✓ Ollama stopped"

# Stop Nginx
nginx -s stop 2>/dev/null || service nginx stop 2>/dev/null || true
echo "  ✓ Nginx stopped"

# Stop Redis
redis-cli shutdown 2>/dev/null || true
echo "  ✓ Redis stopped"

# Stop PostgreSQL
/etc/init.d/postgresql stop 2>/dev/null || true
echo "  ✓ PostgreSQL stopped"

echo ""
echo "All services stopped."
'@

    $stopScript | wsl -d $InstanceName -u root -- bash 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}

# Kill any keepalive PowerShell processes for this instance
Write-KhaosLog -Status "START" -Step "Kill Keepalive" -Message "Stopping keepalive processes..."
$keepaliveProcesses = Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" | 
    Where-Object { $_.CommandLine -match "wsl.*$InstanceName.*sleep" }
if ($keepaliveProcesses) {
    $keepaliveProcesses | ForEach-Object { 
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue 
    }
    Write-KhaosLog -Status "SUCCESS" -Step "Kill Keepalive" -Message "Keepalive processes stopped"
} else {
    Write-KhaosLog -Status "INFO" -Step "Kill Keepalive" -Message "No keepalive processes found"
}

Write-KhaosLog -Status "START" -Step "Terminate WSL" -Message "Terminating WSL instance..."

# Terminate the WSL instance
wsl --terminate $InstanceName 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-KhaosLog -Status "SUCCESS" -Step "Stop Instance" -Message "$InstanceName has been stopped"
} else {
    Write-KhaosLog -Status "FAIL" -Step "Stop Instance" -Message "Failed to stop $InstanceName"
    exit 1
}

Write-Host ""
Write-Host "  To start again: .\04-start-instance.ps1 -Name $($InstanceName -replace 'khaos-', '')" -ForegroundColor Gray
Write-Host ""
