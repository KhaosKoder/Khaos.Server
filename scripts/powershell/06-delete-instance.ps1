# 06-delete-instance.ps1
# Delete a Khaos WSL instance

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$KeepData
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
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║                  KHAOS - DELETE INSTANCE                          ║" -ForegroundColor Red
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# Check if instance exists (clean up WSL output encoding issues)
$wslList = (wsl --list --quiet 2>&1) -replace '[^\x20-\x7E]', '' -join "`n"
if ($wslList -notmatch [regex]::Escape($InstanceName)) {
    Write-KhaosLog -Status "FAIL" -Step "Check Instance" -Message "Instance '$InstanceName' not found"
    exit 1
}

# Confirmation prompt unless Force is specified
if (-not $Force) {
    Write-Host "  ⚠️  WARNING: This will permanently delete the instance!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Instance: $InstanceName" -ForegroundColor White
    Write-Host ""
    Write-Host "  This will delete:" -ForegroundColor Yellow
    Write-Host "    • The entire WSL filesystem" -ForegroundColor Gray
    Write-Host "    • All installed applications and data" -ForegroundColor Gray
    Write-Host "    • All databases (PostgreSQL, Redis)" -ForegroundColor Gray
    Write-Host "    • All downloaded models (Ollama)" -ForegroundColor Gray
    Write-Host ""
    
    $confirmation = Read-Host "  Type the instance name to confirm deletion"
    
    if ($confirmation -ne $InstanceName -and $confirmation -ne ($InstanceName -replace 'khaos-', '')) {
        Write-Host ""
        Write-KhaosLog -Status "INFO" -Step "Cancelled" -Message "Deletion cancelled by user"
        exit 0
    }
}

# Stop the instance first if running
$wslStatus = wsl --list --verbose 2>&1
if ($wslStatus -match "$InstanceName\s+Running") {
    Write-KhaosLog -Status "START" -Step "Stop Instance" -Message "Stopping running instance..."
    wsl --terminate $InstanceName 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Write-KhaosLog -Status "SUCCESS" -Step "Stop Instance" -Message "Instance stopped"
}

# Unregister the WSL distribution
Write-KhaosLog -Status "START" -Step "Unregister" -Message "Unregistering WSL distribution..."

wsl --unregister $InstanceName 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-KhaosLog -Status "SUCCESS" -Step "Unregister" -Message "WSL distribution unregistered"
} else {
    Write-KhaosLog -Status "FAIL" -Step "Unregister" -Message "Failed to unregister distribution"
    exit 1
}

# Delete the instance directory unless KeepData is specified
$instanceDir = Join-Path $KhaosConfig.Paths.Instances $InstanceName

if (Test-Path $instanceDir) {
    if ($KeepData) {
        Write-KhaosLog -Status "INFO" -Step "Keep Data" -Message "Keeping instance data at: $instanceDir"
    } else {
        Write-KhaosLog -Status "START" -Step "Delete Files" -Message "Removing instance files..."
        Remove-Item -Path $instanceDir -Recurse -Force
        Write-KhaosLog -Status "SUCCESS" -Step "Delete Files" -Message "Instance files removed"
    }
}

Write-Host ""
Write-Host "  ✓ Instance '$InstanceName' has been deleted." -ForegroundColor Green
Write-Host ""
Write-Host "  To create a new instance: .\01-create-instance.ps1 -Name <name>" -ForegroundColor Gray
Write-Host ""
