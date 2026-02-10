# 02-run-setup.ps1
# Run all setup scripts inside WSL instance

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [string]$Model = "",  # Override default model
    
    [switch]$ListModels   # Just list available models
)

# Import utilities
. "$PSScriptRoot\utils.ps1"

$config = Get-KhaosConfig
$instanceName = "khaos-$Name"

# If just listing models, do that and exit
if ($ListModels) {
    Show-AvailableModels
    exit 0
}

# Initialize logging
$logFile = Initialize-KhaosLogging -ScriptName "run-setup"

Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                  KHAOS SERVER - RUN SETUP                         ║
║                     Instance: $instanceName
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ============================================================================
# STEP 1: Verify instance exists
# ============================================================================
Write-KhaosLog -Step "Verify Instance" -Status "START" -Message "Checking WSL instance exists"

# Handle null bytes in WSL output (Windows encoding issue)
$instances = (wsl --list --quiet 2>&1) -replace '\x00','' -join ' '
if ($instances -notmatch $instanceName) {
    Write-KhaosLog -Step "Verify Instance" -Status "FAIL" -Message "Instance '$instanceName' not found. Run 01-create-instance.ps1 first."
    exit 1
}
Write-KhaosLog -Step "Verify Instance" -Status "SUCCESS" -Message "Instance found"

# ============================================================================
# STEP 1.5: Configure WSL to prevent auto-shutdown (vmIdleTimeout)
# ============================================================================
# Per Microsoft docs: WSL2 auto-shuts down VMs when there are no open file
# handles to Windows processes. Setting vmIdleTimeout=-1 disables this.
# https://learn.microsoft.com/en-us/windows/wsl/wsl-config
Write-KhaosLog -Step "WSL Config" -Status "START" -Message "Configuring .wslconfig to prevent auto-shutdown"

$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfigNeeded = $true

if (Test-Path $wslConfigPath) {
    $currentConfig = Get-Content $wslConfigPath -Raw
    if ($currentConfig -match "vmIdleTimeout\s*=\s*-1") {
        $wslConfigNeeded = $false
        Write-KhaosLog -Step "WSL Config" -Status "INFO" -Message ".wslconfig already configured"
    }
}

if ($wslConfigNeeded) {
    # Create or update .wslconfig with vmIdleTimeout=-1
    $wslConfig = @"
[wsl2]
networkingMode=nat
vmIdleTimeout=-1
"@
    $wslConfig | Set-Content $wslConfigPath -Encoding UTF8
    Write-KhaosLog -Step "WSL Config" -Status "SUCCESS" -Message ".wslconfig updated - WSL instances will not auto-shutdown"
    Write-KhaosLog -Step "WSL Config" -Status "INFO" -Message "Note: Requires WSL restart to take effect (will happen at end of setup)"
}

# ============================================================================
# STEP 2: Ensure khaos user exists and mount cache
# ============================================================================
Write-KhaosLog -Step "Prepare Instance" -Status "START" -Message "Preparing instance (user + cache mount)"

# Ensure khaos user exists (may have been created in 01-create-instance but let's verify)
$userCheck = wsl -d $instanceName -u root -- bash -c "id khaos 2>/dev/null && echo 'EXISTS' || echo 'MISSING'"
if ($userCheck -match "MISSING") {
    Write-KhaosLog -Step "Prepare Instance" -Status "INFO" -Message "Creating khaos user..."
    wsl -d $instanceName -u root -- bash -c "useradd -m -s /bin/bash khaos 2>/dev/null || true"
    wsl -d $instanceName -u root -- bash -c "echo 'khaos:khaos' | chpasswd"
    wsl -d $instanceName -u root -- bash -c "usermod -aG sudo khaos 2>/dev/null || true"
    wsl -d $instanceName -u root -- bash -c "echo 'khaos ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers"
}
Write-KhaosLog -Step "Prepare Instance" -Status "SUCCESS" -Message "User khaos ready"

# Mount the cache directory (fstab bind mount may not be applied yet)
$windowsCachePath = $config.CacheRoot -replace "\\", "/"
$windowsCachePath = $windowsCachePath -replace "C:", "/mnt/c"
wsl -d $instanceName -u root -- bash -c "mkdir -p /mnt/khaos-cache"
wsl -d $instanceName -u root -- bash -c "mount --bind '$windowsCachePath' /mnt/khaos-cache 2>/dev/null || true"

# Verify mount worked
$mountCheck = wsl -d $instanceName -u root -- bash -c "ls /mnt/khaos-cache/templates 2>/dev/null && echo 'MOUNTED' || echo 'FAILED'"
if ($mountCheck -match "FAILED") {
    Write-KhaosLog -Step "Prepare Instance" -Status "WARN" -Message "Cache mount failed, will copy templates via UNC path"
}
Write-KhaosLog -Step "Prepare Instance" -Status "SUCCESS" -Message "Cache mount ready"

# ============================================================================
# STEP 3: Copy bash scripts to instance
# ============================================================================
Write-KhaosLog -Step "Copy Scripts" -Status "START" -Message "Copying bash scripts to instance"

$bashScriptsPath = Join-Path $PSScriptRoot "..\bash"

# Get WSL path for scripts
$wslScriptsPath = "/opt/khaos/scripts"

# Create the scripts directory in WSL
wsl -d $instanceName -u root -- mkdir -p $wslScriptsPath

# Copy scripts using the WSL filesystem path (more reliable than echo)
$wslFsPath = "\\wsl$\$instanceName\opt\khaos\scripts"

# Ensure the directory exists via UNC path
if (-not (Test-Path $wslFsPath)) {
    New-Item -ItemType Directory -Path $wslFsPath -Force | Out-Null
}

# Copy each script
$scripts = Get-ChildItem -Path $bashScriptsPath -Filter "*.sh" | Sort-Object Name

foreach ($script in $scripts) {
    # Read and convert line endings
    $content = Get-Content $script.FullName -Raw
    $content = $content -replace "`r`n", "`n"
    
    # Write directly to WSL filesystem (UTF8 without BOM)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$wslFsPath\$($script.Name)", $content, $utf8NoBom)
    
    # Make executable
    wsl -d $instanceName -u root -- chmod +x "$wslScriptsPath/$($script.Name)"
}

Write-KhaosLog -Step "Copy Scripts" -Status "SUCCESS" -Message "$($scripts.Count) scripts copied"

# ============================================================================
# STEP 4: Copy templates to instance (ALWAYS from source, not cache)
# ============================================================================
Write-KhaosLog -Step "Copy Templates" -Status "START" -Message "Copying latest templates to instance"

# ALWAYS use the source templates directory, never the cache
# This ensures new instances always get the latest code
$sourceTemplates = Join-Path $PSScriptRoot "..\..\templates"
if (-not (Test-Path $sourceTemplates)) {
    # Fallback to cache if source not found
    $sourceTemplates = Join-Path $config.CacheRoot "templates"
    Write-KhaosLog -Step "Copy Templates" -Status "WARN" -Message "Source templates not found, using cache"
}
$wslTemplatesPath = "\\wsl$\$instanceName\mnt\khaos-cache\templates"

# Always copy fresh templates
Write-KhaosLog -Step "Copy Templates" -Status "INFO" -Message "Copying from: $sourceTemplates"

# Ensure directory exists
wsl -d $instanceName -u root -- mkdir -p /mnt/khaos-cache/templates/api
wsl -d $instanceName -u root -- mkdir -p /mnt/khaos-cache/templates/web/src/views
wsl -d $instanceName -u root -- mkdir -p /mnt/khaos-cache/templates/web/src/stores
    
    # Copy API templates
    if (Test-Path "$sourceTemplates\api") {
        $apiFiles = Get-ChildItem -Path "$sourceTemplates\api" -File
        foreach ($file in $apiFiles) {
            $content = Get-Content $file.FullName -Raw
            $content = $content -replace "`r`n", "`n"
            $destPath = "$wslTemplatesPath\api\$($file.Name)"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
        }
    }
    
    # Copy Web templates
    if (Test-Path "$sourceTemplates\web") {
        # Root files
        Get-ChildItem -Path "$sourceTemplates\web" -File | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            $content = $content -replace "`r`n", "`n"
            $destPath = "$wslTemplatesPath\web\$($_.Name)"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
        }
        
        # src files
        if (Test-Path "$sourceTemplates\web\src") {
            Get-ChildItem -Path "$sourceTemplates\web\src" -File | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                $content = $content -replace "`r`n", "`n"
                $destPath = "$wslTemplatesPath\web\src\$($_.Name)"
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
            }
        }
        
        # src/views files
        if (Test-Path "$sourceTemplates\web\src\views") {
            Get-ChildItem -Path "$sourceTemplates\web\src\views" -File | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                $content = $content -replace "`r`n", "`n"
                $destPath = "$wslTemplatesPath\web\src\views\$($_.Name)"
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
            }
        }
        
        # src/stores files (if any exist)
        if (Test-Path "$sourceTemplates\web\src\stores") {
            Get-ChildItem -Path "$sourceTemplates\web\src\stores" -File | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                $content = $content -replace "`r`n", "`n"
                $destPath = "$wslTemplatesPath\web\src\stores\$($_.Name)"
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
            }
        }
    }
    
    Write-KhaosLog -Step "Copy Templates" -Status "SUCCESS" -Message "Templates copied to instance"

# ============================================================================
# STEP 5: Determine model to use
# ============================================================================
if ([string]::IsNullOrEmpty($Model)) {
    $Model = Get-DefaultModel
}
Write-KhaosLog -Step "Model" -Status "INFO" -Message "Will install model: $Model"

# ============================================================================
# STEP 6: Run each bash script
# ============================================================================

$bashScripts = @(
    @{ Name = "01-system-setup.sh"; Description = "System setup" }
    @{ Name = "02-install-ollama.sh"; Description = "Ollama + LLM model"; Args = $Model }
    @{ Name = "03-install-python.sh"; Description = "Python 3.12 + RAG libraries" }
    @{ Name = "04-install-dotnet.sh"; Description = ".NET 10 + API scaffold" }
    @{ Name = "05-install-node-vue.sh"; Description = "Node.js + Vue frontend" }
    @{ Name = "06-install-redis.sh"; Description = "Redis cache server" }
    @{ Name = "07-install-postgres.sh"; Description = "PostgreSQL database" }
    @{ Name = "08-install-nginx.sh"; Description = "Nginx reverse proxy + SSL" }
    @{ Name = "10-setup-systemd.sh"; Description = "Configure systemd services" }
)

$succeeded = 0
$failed = 0
$errors = @()

foreach ($script in $bashScripts) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-KhaosLog -Step $script.Description -Status "START" -Message "Running $($script.Name)"
    Write-Host ("=" * 70) -ForegroundColor Cyan
    
    $args = if ($script.Args) { $script.Args } else { "" }
    $command = "$wslScriptsPath/$($script.Name) $args"
    
    try {
        # Run the script with output
        wsl -d $instanceName -u root -- bash -c $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-KhaosLog -Step $script.Description -Status "SUCCESS" -Message "Completed successfully"
            $succeeded++
        } else {
            Write-KhaosLog -Step $script.Description -Status "FAIL" -Message "Script exited with code $LASTEXITCODE"
            $errors += "$($script.Name) failed with exit code $LASTEXITCODE"
            $failed++
        }
    }
    catch {
        Write-KhaosLog -Step $script.Description -Status "FAIL" -Message "Error: $_"
        $errors += "$($script.Name): $_"
        $failed++
    }
}

# ============================================================================
# RESTART WSL TO ACTIVATE SYSTEMD
# ============================================================================
# systemd is now configured. We need to restart WSL for it to take effect.
# After restart, all services will auto-start via systemd.
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-KhaosLog -Step "Activate Systemd" -Status "START" -Message "Restarting WSL to enable systemd..."
Write-Host ("=" * 70) -ForegroundColor Cyan

# Terminate WSL instance
wsl --terminate $instanceName 2>$null
Start-Sleep -Seconds 2

# Start it again - systemd will now be active and services will auto-start
Write-KhaosLog -Step "Activate Systemd" -Status "INFO" -Message "Starting instance with systemd..."
$startResult = wsl -d $instanceName -- echo "Systemd activated" 2>&1
Start-Sleep -Seconds 5

# Verify systemd is running
$pid1 = wsl -d $instanceName -- ps -p 1 -o comm= 2>&1
if ($pid1 -match "systemd") {
    Write-KhaosLog -Step "Activate Systemd" -Status "SUCCESS" -Message "Systemd is now running as PID 1"
    $succeeded++
} else {
    Write-KhaosLog -Step "Activate Systemd" -Status "WARN" -Message "Systemd may not be active (PID 1: $pid1)"
    $succeeded++
}

# Wait for services to start
Write-Host "  Waiting for services to start..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Verify services are running by checking ports
$ssPorts = wsl -d $instanceName -u root -- ss -tlnp 2>&1
$webPort = if ($BasePort -eq 0) { 3000 } else { $BasePort }
$apiPort = if ($BasePort -eq 0) { 5000 } else { $BasePort + 2000 }

$webRunning = $ssPorts -match ":$webPort\b"
$apiRunning = $ssPorts -match ":$apiPort\b"

if ($webRunning -and $apiRunning) {
    Write-KhaosLog -Step "Services" -Status "SUCCESS" -Message "All services running (Web:$webPort, API:$apiPort)"
} else {
    $missing = @()
    if (-not $webRunning) { $missing += "Nginx ($webPort)" }
    if (-not $apiRunning) { $missing += "API ($apiPort)" }
    Write-KhaosLog -Step "Services" -Status "WARN" -Message "Some services may still be starting: $($missing -join ', ')"
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host ""
Show-Summary -Succeeded $succeeded -Failed $failed -Errors $errors

$devWebPort = $webPort + 1
$devApiPort = $apiPort + 1

if ($failed -eq 0) {
    # Get the WSL IP address
    $wslIp = wsl -d $instanceName -- hostname -I 2>&1 | ForEach-Object { $_.Trim().Split()[0] }
    
    Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                     SETUP COMPLETE!                                ║
╚═══════════════════════════════════════════════════════════════════╝

  Production (nginx serves static files):
  
    🌐 http://localhost:$webPort
    
  Development (when needed):
  
    Start dev servers:  wsl -d $instanceName -u root -- /opt/khaos/scripts/dev-start.sh
    Dev Web:            http://localhost:$devWebPort
    Dev API:            http://localhost:$devApiPort/api/health
  
  Management Commands:
  
    wsl -d $instanceName -u root -- /opt/khaos/scripts/status.sh      # Show status
    wsl -d $instanceName -u root -- /opt/khaos/scripts/dev-start.sh   # Start dev
    wsl -d $instanceName -u root -- /opt/khaos/scripts/dev-stop.sh    # Stop dev
    wsl -d $instanceName -u root -- /opt/khaos/scripts/deploy.sh      # Deploy changes
  
  Connect to instance:
  
    wsl -d $instanceName
  
  Manual service start (if needed):
  
    wsl -d $instanceName -u root -- /opt/khaos/scripts/09-start-services.sh

  Credentials:
    - Linux user:  khaos / khaos
    - PostgreSQL:  khaos / khaos (database: khaosdb)
    - Redis:       no password

"@ -ForegroundColor Green
} else {
    Write-Host "`n⚠ Setup completed with errors. Check the log for details." -ForegroundColor Yellow
}

Write-Host "Log file: $logFile`n" -ForegroundColor DarkGray
