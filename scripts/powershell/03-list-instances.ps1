# 03-list-instances.ps1
# List all Khaos WSL instances

$ErrorActionPreference = "Stop"

# Get script directory and load dependencies
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\config.ps1"
. "$ScriptDir\utils.ps1"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  KHAOS - LIST INSTANCES                           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Get all WSL distributions and clean up encoding
$wslOutput = (wsl --list --verbose 2>&1) | ForEach-Object { $_ -replace '[^\x20-\x7E]', '' }

# Parse WSL output to find khaos instances
$instances = @()

foreach ($line in $wslOutput) {
    $cleanLine = $line.Trim()
    
    # Skip header and empty lines
    if ($cleanLine -match '^NAME' -or $cleanLine -eq '') { continue }
    
    # Match lines with khaos- prefix
    if ($cleanLine -match '^(\*)?\s*(khaos-\S+)\s+(\S+)\s+(\d+)') {
        $isDefault = $Matches[1] -eq '*'
        $name = $Matches[2].Trim()
        $state = $Matches[3].Trim()
        $version = $Matches[4].Trim()
        
        $instances += [PSCustomObject]@{
            Default = if ($isDefault) { "*" } else { " " }
            Name = $name
            State = $state
            WSL = $version
        }
    }
}

if ($instances.Count -eq 0) {
    Write-Host "  No Khaos instances found." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Create one with: .\01-create-instance.ps1 -Name <instance-name>" -ForegroundColor Gray
} else {
    Write-Host "  Found $($instances.Count) Khaos instance(s):" -ForegroundColor Green
    Write-Host ""
    
    # Display as formatted table
    Write-Host "  ┌───┬─────────────────────────┬──────────┬─────┐" -ForegroundColor DarkGray
    Write-Host "  │   │ Instance Name           │ State    │ WSL │" -ForegroundColor DarkGray
    Write-Host "  ├───┼─────────────────────────┼──────────┼─────┤" -ForegroundColor DarkGray
    
    foreach ($inst in $instances) {
        $stateColor = switch ($inst.State) {
            "Running" { "Green" }
            "Stopped" { "Yellow" }
            default { "White" }
        }
        
        $defaultMark = $inst.Default
        $namePadded = $inst.Name.PadRight(23)
        $statePadded = $inst.State.PadRight(8)
        $wslPadded = $inst.WSL.PadRight(3)
        
        Write-Host "  │ $defaultMark │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$namePadded" -ForegroundColor White -NoNewline
        Write-Host " │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$statePadded" -ForegroundColor $stateColor -NoNewline
        Write-Host " │ " -ForegroundColor DarkGray -NoNewline
        Write-Host "$wslPadded" -ForegroundColor White -NoNewline
        Write-Host " │" -ForegroundColor DarkGray
    }
    
    Write-Host "  └───┴─────────────────────────┴──────────┴─────┘" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor Gray
    Write-Host "    Start:  .\04-start-instance.ps1 -Name <name>" -ForegroundColor Gray
    Write-Host "    Stop:   .\05-stop-instance.ps1 -Name <name>" -ForegroundColor Gray
    Write-Host "    Delete: .\06-delete-instance.ps1 -Name <name>" -ForegroundColor Gray
}

Write-Host ""
