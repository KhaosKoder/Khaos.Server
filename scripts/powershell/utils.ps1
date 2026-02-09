# Khaos Server Utilities
# Logging, caching, and error handling helpers

# Import config
. "$PSScriptRoot\config.ps1"

# Initialize logging
function Initialize-KhaosLogging {
    param([string]$ScriptName)
    
    $config = Get-KhaosConfig
    $logDir = $config.LogRoot
    
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $script:LogFile = Join-Path $logDir "$ScriptName`_$timestamp.log"
    
    Write-KhaosLog -Step $ScriptName -Status "START" -Message "Logging initialized"
    return $script:LogFile
}

# Logging function
function Write-KhaosLog {
    param(
        [string]$Step,
        [ValidateSet("START", "SUCCESS", "FAIL", "INFO", "WARN")]
        [string]$Status,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Step] [$Status] $Message"
    
    # Console output with colors
    $color = switch ($Status) {
        "START"   { "Cyan" }
        "SUCCESS" { "Green" }
        "FAIL"    { "Red" }
        "WARN"    { "Yellow" }
        default   { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # File output
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logEntry
    }
}

# Ensure directory exists
function Ensure-Directory {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-KhaosLog "Ensure-Directory" "INFO" "Created directory: $Path"
    }
}

# Download file with caching
function Get-CachedFile {
    param(
        [string]$Url,
        [string]$DestinationFolder,
        [string]$FileName,
        [int]$MaxRetries = 3
    )
    
    $config = Get-KhaosConfig
    $cachePath = Join-Path $config.CacheRoot $DestinationFolder
    Ensure-Directory $cachePath
    
    $filePath = Join-Path $cachePath $FileName
    
    # Check if already cached
    if (Test-Path $filePath) {
        Write-KhaosLog "Download" "INFO" "Using cached file: $FileName"
        return $filePath
    }
    
    # Download with retry
    $attempt = 0
    $success = $false
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        Write-KhaosLog "Download" "INFO" "Downloading $FileName (attempt $attempt of $MaxRetries)..."
        
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $filePath -UseBasicParsing
            $success = $true
            Write-KhaosLog "Download" "SUCCESS" "Downloaded: $FileName"
        }
        catch {
            Write-KhaosLog "Download" "WARN" "Attempt $attempt failed: $_"
            if ($attempt -lt $MaxRetries) {
                $delay = [Math]::Pow(2, $attempt)
                Write-KhaosLog "Download" "INFO" "Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
            }
        }
    }
    
    if (-not $success) {
        Write-KhaosLog "Download" "FAIL" "Failed to download $FileName after $MaxRetries attempts"
        return $null
    }
    
    return $filePath
}

# Check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check WSL status
function Test-WslInstalled {
    try {
        $wslVersion = wsl --version 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# List existing Khaos instances
function Get-KhaosInstances {
    $instances = wsl --list --quiet 2>&1 | Where-Object { $_ -match "^khaos-" }
    return $instances
}

# Check if instance exists
function Test-KhaosInstance {
    param([string]$Name)
    
    $instances = Get-KhaosInstances
    return $instances -contains "khaos-$Name"
}

# Run command in WSL instance
function Invoke-WslCommand {
    param(
        [string]$InstanceName,
        [string]$Command,
        [switch]$AsRoot
    )
    
    $user = if ($AsRoot) { "-u root" } else { "" }
    $fullCommand = "wsl -d khaos-$InstanceName $user -- $Command"
    
    Write-KhaosLog "WSL" "INFO" "Executing: $Command"
    
    try {
        $output = Invoke-Expression $fullCommand 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{ Success = $true; Output = $output }
        } else {
            return @{ Success = $false; Output = $output; ExitCode = $LASTEXITCODE }
        }
    }
    catch {
        return @{ Success = $false; Output = $_.Exception.Message }
    }
}

# Copy file to WSL instance
function Copy-ToWsl {
    param(
        [string]$InstanceName,
        [string]$SourcePath,
        [string]$DestinationPath
    )
    
    $wslPath = wsl -d "khaos-$InstanceName" -- wslpath -a "$SourcePath"
    Invoke-WslCommand -InstanceName $InstanceName -Command "cp '$wslPath' '$DestinationPath'" -AsRoot
}

# Display summary of operations
function Show-Summary {
    param(
        [int]$Succeeded,
        [int]$Failed,
        [array]$Errors
    )
    
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    Write-Host "Succeeded: $Succeeded" -ForegroundColor Green
    Write-Host "Failed: $Failed" -ForegroundColor $(if ($Failed -gt 0) { "Red" } else { "Green" })
    
    if ($Errors.Count -gt 0) {
        Write-Host "`nErrors:" -ForegroundColor Red
        foreach ($err in $Errors) {
            Write-Host "  - $err" -ForegroundColor Red
        }
    }
    
    Write-Host ("=" * 60) -ForegroundColor Cyan
}
