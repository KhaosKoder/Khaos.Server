# 04-start-instance.ps1
# Start a Khaos WSL instance and all its services

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [switch]$NoKeepalive  # Don't start background keepalive process
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

# Check if systemd is active (PID 1 should be systemd)
$pid1 = wsl -d $InstanceName -- ps -p 1 -o comm= 2>&1
if ($pid1 -match "systemd") {
    Write-KhaosLog -Status "INFO" -Step "Systemd" -Message "Systemd is active - services will auto-start"
    
    # Wait for systemd services to start
    Start-Sleep -Seconds 3
    
    # Check service status
    $serviceStatus = wsl -d $InstanceName -u root -- systemctl is-active khaos-api nginx redis-server 2>&1
    Write-KhaosLog -Status "INFO" -Step "Services" -Message "Service status: $($serviceStatus -join ', ')"
} else {
    # Fallback: No systemd, use manual start script
    Write-KhaosLog -Status "WARN" -Step "Systemd" -Message "Systemd not active, using manual start..."
    wsl -d $InstanceName -u root -- /opt/khaos/scripts/prod-start.sh 2>&1
    Start-Sleep -Seconds 3
}

# Verify services are running by checking ports
$ssPorts = wsl -d $InstanceName -u root -- ss -tlnp 2>&1
$config = wsl -d $InstanceName -u root -- cat /etc/khaos/khaos.conf 2>&1
$webPort = if ($config -match 'KHAOS_WEB_PORT=(\d+)') { $Matches[1] } else { "3000" }
$apiPort = if ($config -match 'KHAOS_API_PORT=(\d+)') { $Matches[1] } else { "5000" }

$webRunning = $ssPorts -match ":$webPort\b"
$apiRunning = $ssPorts -match ":$apiPort\b"

if ($webRunning -and $apiRunning) {
    Write-KhaosLog -Status "SUCCESS" -Step "Start Services" -Message "All services are running"
} else {
    $missing = @()
    if (-not $webRunning) { $missing += "Web/Nginx ($webPort)" }
    if (-not $apiRunning) { $missing += "API ($apiPort)" }
    Write-KhaosLog -Status "WARN" -Step "Start Services" -Message "Some services may not be ready: $($missing -join ', ')"
}

# ============================================================================
# Start background keepalive process
# ============================================================================
# WSL2 auto-shuts down when there are no Windows processes with file handles 
# to the VM. We start a background job to keep the instance alive.
# Per Microsoft docs: https://learn.microsoft.com/en-us/windows/wsl/faq

if (-not $NoKeepalive) {
    Write-KhaosLog -Status "START" -Step "Keepalive" -Message "Starting background keepalive process..."
    
    # Start a hidden background PowerShell process that keeps a WSL connection open
    $keepaliveScript = @"
while (`$true) { 
    `$null = wsl -d $InstanceName -- sleep 60 2>&1
    if (`$LASTEXITCODE -ne 0) { break }
}
"@
    
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($keepaliveScript)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    
    # Start as a hidden background process
    Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-EncodedCommand", $encodedCommand
    
    Write-KhaosLog -Status "SUCCESS" -Step "Keepalive" -Message "Background keepalive started - instance will stay running"
}

Write-Host ""
Write-KhaosLog -Status "SUCCESS" -Step "Complete" -Message "$InstanceName is ready!"
Write-Host ""
Write-Host "  Open in browser: " -NoNewline -ForegroundColor White
Write-Host "http://localhost:$webPort" -ForegroundColor Green
Write-Host ""
Write-Host "  To stop instance: .\05-stop-instance.ps1 -Name $Name" -ForegroundColor Gray
Write-Host ""
