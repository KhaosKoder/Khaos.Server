# 00-download-all.ps1
# Pre-download everything for offline WSL instance creation

param(
    [switch]$Force  # Force re-download even if cached
)

# Import utilities
. "$PSScriptRoot\utils.ps1"

# Initialize logging
$logFile = Initialize-KhaosLogging -ScriptName "download-all"
$config = Get-KhaosConfig

$succeeded = 0
$failed = 0
$errors = @()

Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                    KHAOS SERVER - DOWNLOAD ALL                    ║
║               Pre-downloading files for offline use               ║
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# ============================================================================
# STEP 1: Create cache directory structure
# ============================================================================
Write-KhaosLog -Step "Directory Setup" -Status "START" -Message "Creating cache directories"

$directories = @(
    $config.CacheRoot
    (Join-Path $config.CacheRoot "distros")
    (Join-Path $config.CacheRoot "models")
    (Join-Path $config.CacheRoot "scripts")
)

foreach ($dir in $directories) {
    Ensure-Directory $dir
}
Write-KhaosLog -Step "Directory Setup" -Status "SUCCESS" -Message "Cache directories created"
$succeeded++

# ============================================================================
# STEP 2: Download Ubuntu WSL image
# ============================================================================
Write-KhaosLog -Step "Ubuntu Image" -Status "START" -Message "Downloading Ubuntu 24.04 WSL image"

$ubuntuPath = Join-Path $config.CacheRoot "distros" $config.Linux.FileName

if ((Test-Path $ubuntuPath) -and -not $Force) {
    Write-KhaosLog -Step "Ubuntu Image" -Status "INFO" -Message "Already cached: $($config.Linux.FileName)"
    $succeeded++
} else {
    try {
        Write-Host "  Downloading Ubuntu 24.04 (this may take a few minutes)..." -ForegroundColor Yellow
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $config.Linux.DownloadUrl -OutFile $ubuntuPath -UseBasicParsing
        
        $size = [math]::Round((Get-Item $ubuntuPath).Length / 1MB, 2)
        Write-KhaosLog -Step "Ubuntu Image" -Status "SUCCESS" -Message "Downloaded: $($config.Linux.FileName) ($size MB)"
        $succeeded++
    }
    catch {
        Write-KhaosLog -Step "Ubuntu Image" -Status "FAIL" -Message "Failed: $_"
        $errors += "Ubuntu image download failed: $_"
        $failed++
    }
}

# ============================================================================
# STEP 3: Download .NET install script
# ============================================================================
Write-KhaosLog -Step ".NET Script" -Status "START" -Message "Downloading .NET install script"

$dotnetScriptPath = Join-Path $config.CacheRoot "scripts" "dotnet-install.sh"

if ((Test-Path $dotnetScriptPath) -and -not $Force) {
    Write-KhaosLog -Step ".NET Script" -Status "INFO" -Message "Already cached: dotnet-install.sh"
    $succeeded++
} else {
    try {
        Invoke-WebRequest -Uri $config.DotNet.InstallScript -OutFile $dotnetScriptPath -UseBasicParsing
        Write-KhaosLog -Step ".NET Script" -Status "SUCCESS" -Message "Downloaded: dotnet-install.sh"
        $succeeded++
    }
    catch {
        Write-KhaosLog -Step ".NET Script" -Status "FAIL" -Message "Failed: $_"
        $errors += ".NET script download failed: $_"
        $failed++
    }
}

# ============================================================================
# STEP 4: Copy bash scripts to cache (for WSL access)
# ============================================================================
Write-KhaosLog -Step "Bash Scripts" -Status "START" -Message "Copying bash scripts to cache"

$bashSourceDir = Join-Path $PSScriptRoot "..\bash"
$bashCacheDir = Join-Path $config.CacheRoot "scripts" "bash"

if (Test-Path $bashSourceDir) {
    Ensure-Directory $bashCacheDir
    try {
        Copy-Item -Path "$bashSourceDir\*" -Destination $bashCacheDir -Force -Recurse
        Write-KhaosLog -Step "Bash Scripts" -Status "SUCCESS" -Message "Bash scripts copied to cache"
        $succeeded++
    }
    catch {
        Write-KhaosLog -Step "Bash Scripts" -Status "WARN" -Message "No bash scripts found yet (will be created later)"
        $succeeded++
    }
} else {
    Write-KhaosLog -Step "Bash Scripts" -Status "INFO" -Message "Bash scripts directory not yet created"
    $succeeded++
}

# ============================================================================
# STEP 5: Copy templates to cache (for WSL access)
# ============================================================================
Write-KhaosLog -Step "Templates" -Status "START" -Message "Copying template files to cache"

$templatesSourceDir = Join-Path (Split-Path $PSScriptRoot -Parent) "..\templates"
$templatesCacheDir = Join-Path $config.CacheRoot "templates"

if (Test-Path $templatesSourceDir) {
    Ensure-Directory $templatesCacheDir
    try {
        Copy-Item -Path "$templatesSourceDir\*" -Destination $templatesCacheDir -Force -Recurse
        $templateCount = (Get-ChildItem -Path $templatesCacheDir -Recurse -File).Count
        Write-KhaosLog -Step "Templates" -Status "SUCCESS" -Message "Templates copied to cache ($templateCount files)"
        $succeeded++
    }
    catch {
        Write-KhaosLog -Step "Templates" -Status "FAIL" -Message "Failed to copy templates: $_"
        $errors += "Template copy failed: $_"
        $failed++
    }
} else {
    Write-KhaosLog -Step "Templates" -Status "WARN" -Message "Templates directory not found: $templatesSourceDir"
    $succeeded++
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host ""
Show-Summary -Succeeded $succeeded -Failed $failed -Errors $errors

Write-Host "`nCache location: $($config.CacheRoot)" -ForegroundColor Cyan

if ($failed -eq 0) {
    Write-Host "`n✓ All downloads completed successfully!" -ForegroundColor Green
    Write-Host "  You can now create offline WSL instances." -ForegroundColor Green
} else {
    Write-Host "`n⚠ Some downloads failed. Check errors above." -ForegroundColor Yellow
    Write-Host "  Re-run with -Force to retry failed downloads." -ForegroundColor Yellow
}

Write-Host "`nLog file: $logFile`n" -ForegroundColor DarkGray
