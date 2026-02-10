# 08-update-instance.ps1
# Sync latest templates to a running instance and rebuild everything

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
Write-Host "║                  KHAOS - UPDATE INSTANCE                          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if instance exists
$wslList = (wsl --list --quiet 2>&1) -replace '[^\x20-\x7E]', '' -join "`n"
if ($wslList -notmatch [regex]::Escape($InstanceName)) {
    Write-KhaosLog -Status "FAIL" -Step "Check" -Message "Instance '$InstanceName' not found"
    exit 1
}

# Source templates (ALWAYS use project templates, never cache)
$templatesDir = Join-Path $ScriptDir "..\..\templates"
$templatesDir = (Resolve-Path $templatesDir).Path

if (-not (Test-Path $templatesDir)) {
    Write-KhaosLog -Status "FAIL" -Step "Check" -Message "Templates directory not found: $templatesDir"
    exit 1
}

Write-KhaosLog -Status "INFO" -Step "Source" -Message "Using templates from: $templatesDir"

# Ensure instance is running
$wslStatus = wsl --list --verbose 2>&1
if ($wslStatus -notmatch "$InstanceName\s+Running") {
    Write-KhaosLog -Status "START" -Step "Start" -Message "Starting instance..."
    wsl -d $InstanceName -- echo "started" | Out-Null
    Start-Sleep -Seconds 3
}

# WSL UNC path
$wslBase = "\\wsl$\$InstanceName"

# ============================================================================
# UPDATE WEB (Vue Frontend)
# ============================================================================
Write-KhaosLog -Status "START" -Step "Web" -Message "Copying web templates..."

$webSrc = Join-Path $templatesDir "web\src"
$webDest = "$wslBase\opt\khaos\apps\web\src"

# Remove old src and copy new
if (Test-Path $webDest) {
    Remove-Item -Path $webDest -Recurse -Force
}
Copy-Item -Path $webSrc -Destination $webDest -Recurse -Force

# Also copy root web files (package.json, vite.config.ts, etc.)
Get-ChildItem -Path (Join-Path $templatesDir "web") -File | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($content) {
        $content = $content -replace "`r`n", "`n"
        $destPath = "$wslBase\opt\khaos\apps\web\$($_.Name)"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
    }
}

Write-KhaosLog -Status "SUCCESS" -Step "Web" -Message "Web templates copied"

# Build web
Write-KhaosLog -Status "START" -Step "Web Build" -Message "Building Vue app..."
$buildResult = wsl -d $InstanceName -u root -- bash -c 'cd /opt/khaos/apps/web && npm run build 2>&1'
if ($LASTEXITCODE -ne 0) {
    Write-KhaosLog -Status "FAIL" -Step "Web Build" -Message "Build failed"
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}

# Deploy web
wsl -d $InstanceName -u root -- bash -c 'rm -rf /opt/khaos/publish/web/* && cp -r /opt/khaos/apps/web/dist/* /opt/khaos/publish/web/'
Write-KhaosLog -Status "SUCCESS" -Step "Web Build" -Message "Vue app built and deployed"

# ============================================================================
# UPDATE API (.NET Backend)
# ============================================================================
Write-KhaosLog -Status "START" -Step "API" -Message "Copying API templates..."

$apiSrc = Join-Path $templatesDir "api"
$apiDest = "$wslBase\opt\khaos\apps\api"

# Copy API files
Get-ChildItem -Path $apiSrc -File | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($content) {
        $content = $content -replace "`r`n", "`n"
        $destPath = "$apiDest\$($_.Name)"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
    }
}

Write-KhaosLog -Status "SUCCESS" -Step "API" -Message "API templates copied"

# Stop API, rebuild, restart
Write-KhaosLog -Status "START" -Step "API Build" -Message "Building .NET API..."
$buildResult = wsl -d $InstanceName -u root -- bash -c 'systemctl stop khaos-api 2>/dev/null; cd /opt/khaos/apps/api && dotnet publish -c Release -o /opt/khaos/publish/api --self-contained false 2>&1'
if ($LASTEXITCODE -ne 0) {
    Write-KhaosLog -Status "FAIL" -Step "API Build" -Message "Build failed"
    Write-Host $buildResult -ForegroundColor Red
    exit 1
}

# Restart API
wsl -d $InstanceName -u root -- systemctl start khaos-api
Start-Sleep -Seconds 2
Write-KhaosLog -Status "SUCCESS" -Step "API Build" -Message "API built and restarted"

# ============================================================================
# VERIFY
# ============================================================================
Write-KhaosLog -Status "START" -Step "Verify" -Message "Testing endpoints..."

# Get ports
$configContent = wsl -d $InstanceName -u root -- cat /etc/khaos/khaos.conf 2>$null
$webPort = if ($configContent -match 'KHAOS_WEB_PORT=(\d+)') { $Matches[1] } else { "3000" }
$apiPort = if ($configContent -match 'KHAOS_API_PORT=(\d+)') { $Matches[1] } else { "5000" }

# Test health
$health = curl -s --max-time 5 "http://localhost:$apiPort/api/health" 2>$null
if ($health -match "healthy") {
    Write-KhaosLog -Status "SUCCESS" -Step "Verify" -Message "API is healthy"
} else {
    Write-KhaosLog -Status "WARN" -Step "Verify" -Message "API health check inconclusive"
}

Write-Host ""
Write-Host "  ✓ Instance '$InstanceName' updated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard: http://localhost:$webPort" -ForegroundColor Cyan
Write-Host "  API Docs:  http://localhost:$apiPort/swagger" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Hard refresh your browser (Ctrl+Shift+R) to see changes." -ForegroundColor Yellow
Write-Host ""
