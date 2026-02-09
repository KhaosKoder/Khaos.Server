# 01-create-instance.ps1
# Create a new WSL instance from cached Ubuntu image

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [switch]$Force  # Remove existing instance with same name
)

# Import utilities
. "$PSScriptRoot\utils.ps1"

# Initialize logging
$logFile = Initialize-KhaosLogging -ScriptName "create-instance"
$config = Get-KhaosConfig

$instanceName = "khaos-$Name"

Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                  KHAOS SERVER - CREATE INSTANCE                   ║
║                     Instance: $instanceName
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

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
    $windowsCachePath = $config.CacheRoot -replace "\\", "/"
    $windowsCachePath = $windowsCachePath -replace "C:", "/mnt/c"
    
    # Add to fstab for persistent mount
    $fstabEntry = "$windowsCachePath /mnt/khaos-cache none bind 0 0"
    
    wsl -d $instanceName -u root -- bash -c "mkdir -p /mnt/khaos-cache" 2>&1 | Out-Null
    wsl -d $instanceName -u root -- bash -c "echo '$fstabEntry' >> /etc/fstab" 2>&1 | Out-Null
    
    Write-KhaosLog -Step "Cache Mount" -Status "SUCCESS" -Message "Cache mount configured at /mnt/khaos-cache"
}
catch {
    Write-KhaosLog -Step "Cache Mount" -Status "WARN" -Message "Cache mount configuration failed: $_"
}

# ============================================================================
# STEP 7: Clean up
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
  Location:       $instanceDir
  Default User:   khaos (password: khaos)
  Cache Mount:    /mnt/khaos-cache

  To access:      wsl -d $instanceName
  
  Next step:      .\02-run-setup.ps1 -Name "$Name"

"@ -ForegroundColor Green

Write-Host "Log file: $logFile`n" -ForegroundColor DarkGray
