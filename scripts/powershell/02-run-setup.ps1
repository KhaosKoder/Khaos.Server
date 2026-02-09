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

$instances = wsl --list --quiet 2>&1
if ($instances -notmatch $instanceName) {
    Write-KhaosLog -Step "Verify Instance" -Status "FAIL" -Message "Instance '$instanceName' not found. Run 01-create-instance.ps1 first."
    exit 1
}
Write-KhaosLog -Step "Verify Instance" -Status "SUCCESS" -Message "Instance found"

# ============================================================================
# STEP 2: Copy bash scripts to instance
# ============================================================================
Write-KhaosLog -Step "Copy Scripts" -Status "START" -Message "Copying bash scripts to instance"

$bashScriptsPath = Join-Path $PSScriptRoot "..\bash"

# Get WSL path for scripts
$wslScriptsPath = "/opt/khaos/scripts"

# Copy each script
$scripts = Get-ChildItem -Path $bashScriptsPath -Filter "*.sh" | Sort-Object Name

foreach ($script in $scripts) {
    $content = Get-Content $script.FullName -Raw
    # Convert line endings to Unix
    $content = $content -replace "`r`n", "`n"
    
    # Write to WSL
    $escapedContent = $content -replace "'", "'\''"
    wsl -d $instanceName -u root -- bash -c "echo '$escapedContent' > $wslScriptsPath/$($script.Name)"
    wsl -d $instanceName -u root -- chmod +x "$wslScriptsPath/$($script.Name)"
}

Write-KhaosLog -Step "Copy Scripts" -Status "SUCCESS" -Message "$($scripts.Count) scripts copied"

# ============================================================================
# STEP 3: Determine model to use
# ============================================================================
if ([string]::IsNullOrEmpty($Model)) {
    $Model = Get-DefaultModel
}
Write-KhaosLog -Step "Model" -Status "INFO" -Message "Will install model: $Model"

# ============================================================================
# STEP 4: Run each bash script
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
    @{ Name = "09-start-services.sh"; Description = "Start all services" }
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
# SUMMARY
# ============================================================================
Write-Host ""
Show-Summary -Succeeded $succeeded -Failed $failed -Errors $errors

if ($failed -eq 0) {
    # Get the WSL IP address
    $wslIp = wsl -d $instanceName -- hostname -I 2>&1 | ForEach-Object { $_.Trim().Split()[0] }
    
    Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                     SETUP COMPLETE!                                ║
╚═══════════════════════════════════════════════════════════════════╝

  Access the application:
  
    🌐 From Windows:  https://localhost (via WSL)
                      https://$wslIp
    
    📱 From network:  https://$wslIp
  
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
