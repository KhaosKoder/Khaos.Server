# 01-create-instance.ps1
# Create a new WSL instance from cached Ubuntu image

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [int]$BasePort = 3000,  # Base port for calculating all service ports
    
    [switch]$Force  # Remove existing instance with same name
)

# Import utilities
. "$PSScriptRoot\utils.ps1"

# Initialize logging
$logFile = Initialize-KhaosLogging -ScriptName "create-instance"
$config = Get-KhaosConfig -BasePort $BasePort
$ports = $config.Ports

$instanceName = "khaos-$Name"
$displayName = "Khaos $Name"

Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                  KHAOS SERVER - CREATE INSTANCE                   ║
║                     Instance: $instanceName
║                     BasePort: $BasePort
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Show calculated port configuration
Show-PortConfig -BasePort $BasePort

# ============================================================================
# STEP 1: Check prerequisites
# ============================================================================
Write-KhaosLog -Step "Prerequisites" -Status "START" -Message "Checking system requirements"

# Check WSL is installed
if (-not (Test-WslInstalled)) {
    Write-KhaosLog -Step "Prerequisites" -Status "FAIL" -Message "WSL is not installed. Run 'wsl --install' first."
    exit 1
}
Write-KhaosLog -Step "Prerequisites" -Status "INFO" -Message "WSL is installed"

# Check for cached Ubuntu image
$ubuntuAppx = Join-Path $config.CacheRoot "distros" $config.Linux.FileName

if (-not (Test-Path $ubuntuAppx)) {
    Write-KhaosLog -Step "Prerequisites" -Status "FAIL" -Message "Ubuntu image not found. Run 00-download-all.ps1 first."
    Write-Host "  Expected: $ubuntuAppx" -ForegroundColor Red
    exit 1
}
Write-KhaosLog -Step "Prerequisites" -Status "SUCCESS" -Message "Prerequisites met"

# ============================================================================
# STEP 1.5: Configure WSL to prevent auto-shutdown
# ============================================================================
# Per Microsoft docs: "If you have no open file handles to Windows processes, 
# the WSL VM will automatically be shut down."
# https://learn.microsoft.com/en-us/windows/wsl/faq#can-i-use-wsl-for-production-scenarios-
# 
# Solution: The start script (04-start-instance.ps1) launches a background 
# PowerShell process that maintains a connection to keep WSL alive.
# We also set vmIdleTimeout=-1 as an additional safety measure.
Write-KhaosLog -Step "WSL Config" -Status "START" -Message "Configuring .wslconfig settings"

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
    Write-KhaosLog -Step "WSL Config" -Status "SUCCESS" -Message ".wslconfig updated with vmIdleTimeout=-1"
    
    # Shutdown WSL to apply the new config
    Write-KhaosLog -Step "WSL Config" -Status "INFO" -Message "Restarting WSL to apply configuration..."
    wsl --shutdown 2>$null
    Start-Sleep -Seconds 2
}

# ============================================================================
# STEP 2: Check for existing instance
# ============================================================================
Write-KhaosLog -Step "Check Instance" -Status "START" -Message "Checking for existing instance: $instanceName"

$existingInstances = wsl --list --quiet 2>&1
if ($existingInstances -match $instanceName) {
    if ($Force) {
        Write-KhaosLog -Step "Check Instance" -Status "WARN" -Message "Removing existing instance: $instanceName"
        wsl --unregister $instanceName 2>&1 | Out-Null
        Write-KhaosLog -Step "Check Instance" -Status "SUCCESS" -Message "Existing instance removed"
    } else {
        Write-KhaosLog -Step "Check Instance" -Status "FAIL" -Message "Instance '$instanceName' already exists. Use -Force to replace."
        exit 1
    }
} else {
    Write-KhaosLog -Step "Check Instance" -Status "INFO" -Message "No existing instance found"
}

# ============================================================================
# STEP 3: Extract AppxBundle and get rootfs
# ============================================================================
Write-KhaosLog -Step "Extract Image" -Status "START" -Message "Extracting Ubuntu image"

$tempDir = Join-Path $env:TEMP "khaos-ubuntu-extract"
$instanceDir = Join-Path $config.InstanceRoot $Name

# Clean up temp directory if exists
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Create instance directory
Ensure-Directory $instanceDir

try {
    # Extract the AppxBundle (it's a zip file)
    Write-KhaosLog -Step "Extract Image" -Status "INFO" -Message "Extracting AppxBundle..."
    Expand-Archive -Path $ubuntuAppx -DestinationPath $tempDir -Force
    
    # Find the x64 appx inside
    $x64Appx = Get-ChildItem -Path $tempDir -Filter "*x64*.appx" -Recurse | Select-Object -First 1
    
    if (-not $x64Appx) {
        # Try without x64 in name
        $x64Appx = Get-ChildItem -Path $tempDir -Filter "*.appx" -Recurse | 
                   Where-Object { $_.Name -notmatch "scale" } | 
                   Select-Object -First 1
    }
    
    if (-not $x64Appx) {
        throw "Could not find x64 appx in bundle"
    }
    
    Write-KhaosLog -Step "Extract Image" -Status "INFO" -Message "Found: $($x64Appx.Name)"
    
    # Extract the appx
    $appxExtractDir = Join-Path $tempDir "appx"
    Expand-Archive -Path $x64Appx.FullName -DestinationPath $appxExtractDir -Force
    
    # Find install.tar.gz (the rootfs)
    $rootfs = Get-ChildItem -Path $appxExtractDir -Filter "install.tar.gz" -Recurse | Select-Object -First 1
    
    if (-not $rootfs) {
        throw "Could not find install.tar.gz in appx"
    }
    
    Write-KhaosLog -Step "Extract Image" -Status "SUCCESS" -Message "Rootfs extracted: $($rootfs.Name)"
    
}
catch {
    Write-KhaosLog -Step "Extract Image" -Status "FAIL" -Message "Failed to extract: $_"
    exit 1
}

# ============================================================================
# STEP 4: Import WSL instance
# ============================================================================
Write-KhaosLog -Step "Import WSL" -Status "START" -Message "Importing WSL instance"

$vhdPath = Join-Path $instanceDir "ext4.vhdx"

try {
    Write-Host "  Importing instance (this may take a minute)..." -ForegroundColor Yellow
    $importResult = wsl --import $instanceName $instanceDir $rootfs.FullName --version 2 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "WSL import failed: $importResult"
    }
    
    Write-KhaosLog -Step "Import WSL" -Status "SUCCESS" -Message "Instance imported successfully"
}
catch {
    Write-KhaosLog -Step "Import WSL" -Status "FAIL" -Message "Import failed: $_"
    exit 1
}

# ============================================================================
# STEP 5: Configure instance
# ============================================================================
Write-KhaosLog -Step "Configure" -Status "START" -Message "Configuring WSL instance"

try {
    # Create a default user 'khaos'
    $createUser = @"
useradd -m -s /bin/bash khaos
echo 'khaos:khaos' | chpasswd
usermod -aG sudo khaos
echo 'khaos ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
"@
    
    wsl -d $instanceName -u root -- bash -c $createUser 2>&1 | Out-Null
    
    # Set default user
    # Create /etc/wsl.conf
    $wslConf = @"
[user]
default=khaos

[automount]
enabled=true
mountFsTab=true

[interop]
enabled=true
appendWindowsPath=true
"@
    
    wsl -d $instanceName -u root -- bash -c "echo '$wslConf' > /etc/wsl.conf" 2>&1 | Out-Null
    
    Write-KhaosLog -Step "Configure" -Status "SUCCESS" -Message "Instance configured (user: khaos, password: khaos)"
}
catch {
    Write-KhaosLog -Step "Configure" -Status "WARN" -Message "Configuration partial: $_"
}

# ============================================================================
# STEP 6: Setup cache mount
# ============================================================================
Write-KhaosLog -Step "Cache Mount" -Status "START" -Message "Configuring cache folder mount"

try {
    # Create mount point
    wsl -d $instanceName -u root -- bash -c "mkdir -p /mnt/khaos-cache" 2>&1 | Out-Null
    
    # Create a startup script to mount the cache instead of using fstab
    # This avoids the fstab parsing error with Windows paths
    $mountScript = @"
#!/bin/bash
# Mount khaos cache from Windows host
CACHE_PATH="/mnt/c/Users/$($env:USERNAME)/.khaos/cache"
if [ -d "\$CACHE_PATH" ] && [ ! -d "/mnt/khaos-cache/templates" ]; then
    mount --bind "\$CACHE_PATH" /mnt/khaos-cache 2>/dev/null || true
fi
"@
    $mountScriptPath = "\\wsl$\$instanceName\opt\khaos-mount.sh"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $mountScript = $mountScript -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($mountScriptPath, $mountScript, $utf8NoBom)
    wsl -d $instanceName -u root -- chmod +x /opt/khaos-mount.sh 2>&1 | Out-Null
    
    Write-KhaosLog -Step "Cache Mount" -Status "SUCCESS" -Message "Cache mount configured at /mnt/khaos-cache"
}
catch {
    Write-KhaosLog -Step "Cache Mount" -Status "WARN" -Message "Cache mount configuration failed: $_"
}

# ============================================================================
# STEP 7: Create Khaos configuration file
# ============================================================================
Write-KhaosLog -Step "Config File" -Status "START" -Message "Creating instance configuration file"

try {
    # Create config directory via WSL
    wsl -d $instanceName -u root -- bash -c "mkdir -p /etc/khaos" 2>&1 | Out-Null
    
    # Write config file via UNC path with Unix line endings
    $khaosConf = @"
# Khaos Instance Configuration
# Auto-generated by create-instance.ps1

KHAOS_INSTANCE_NAME="$displayName"
KHAOS_BASE_PORT=$BasePort
KHAOS_WEB_PORT=$($ports.Vue)
KHAOS_API_PORT=$($ports.Api)
KHAOS_OLLAMA_PORT=$($ports.Ollama)
KHAOS_REDIS_PORT=$($ports.Redis)
KHAOS_POSTGRES_PORT=$($ports.Postgres)

# Paths
KHAOS_CACHE_PATH=/mnt/khaos-cache
KHAOS_APPS_PATH=/opt/khaos/apps
KHAOS_MODELS_PATH=/usr/share/ollama/.ollama/models
KHAOS_LOGS_PATH=/var/log/khaos
"@
    
    # Convert to Unix line endings and write via UNC path
    $khaosConf = $khaosConf -replace "`r`n", "`n"
    $wslConfPath = "\\wsl$\$instanceName\etc\khaos\khaos.conf"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($wslConfPath, $khaosConf, $utf8NoBom)
    
    # Also create a profile.d script to load the config
    $profileScript = @"
# Load Khaos configuration
if [ -f /etc/khaos/khaos.conf ]; then
    set -a
    source /etc/khaos/khaos.conf
    set +a
fi
"@
    $profileScript = $profileScript -replace "`r`n", "`n"
    wsl -d $instanceName -u root -- mkdir -p /etc/profile.d 2>&1 | Out-Null
    $wslProfilePath = "\\wsl$\$instanceName\etc\profile.d\khaos.sh"
    [System.IO.File]::WriteAllText($wslProfilePath, $profileScript, $utf8NoBom)
    wsl -d $instanceName -u root -- chmod +x /etc/profile.d/khaos.sh 2>&1 | Out-Null
    
    Write-KhaosLog -Step "Config File" -Status "SUCCESS" -Message "Configuration saved to /etc/khaos/khaos.conf"
}
catch {
    Write-KhaosLog -Step "Config File" -Status "WARN" -Message "Config file creation failed: $_"
}

# ============================================================================
# STEP 8: Clean up
# ============================================================================
Write-KhaosLog -Step "Cleanup" -Status "START" -Message "Cleaning up temporary files"

try {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-KhaosLog -Step "Cleanup" -Status "SUCCESS" -Message "Temporary files removed"
}
catch {
    Write-KhaosLog -Step "Cleanup" -Status "WARN" -Message "Could not remove temp files: $tempDir"
}

# ============================================================================
# DONE
# ============================================================================
Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                     INSTANCE CREATED SUCCESSFULLY                  ║
╚═══════════════════════════════════════════════════════════════════╝

  Instance Name:  $instanceName
  Display Name:   $displayName
  Location:       $instanceDir
  Default User:   khaos (password: khaos)
  Cache Mount:    /mnt/khaos-cache
  
  Port Configuration:
    Vue/Web:      $($ports.Vue)
    API:          $($ports.Api)
    Ollama:       $($ports.Ollama)
    Redis:        $($ports.Redis)
    PostgreSQL:   $($ports.Postgres)

  To access:      wsl -d $instanceName
  
  Next step:      .\02-run-setup.ps1 -Name "$Name"

"@ -ForegroundColor Green

Write-Host "Log file: $logFile`n" -ForegroundColor DarkGray
