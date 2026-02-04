# Install code-dbg extension to VS Code or VS Code Insiders
# Usage: .\scripts\install.ps1 -Code
#        .\scripts\install.ps1 -CodeInsiders

param(
    [switch]$Code = $false,
    [switch]$CodeInsiders = $false
)

# Validate parameters - must specify one and only one
if (($Code -and $CodeInsiders) -or (-not $Code -and -not $CodeInsiders)) {
    Write-Host "ERROR: Must specify either -Code or -CodeInsiders (not both)" -ForegroundColor Red
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\scripts\install.ps1 -Code" -ForegroundColor White
    Write-Host "  .\scripts\install.ps1 -CodeInsiders" -ForegroundColor White
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installing code-dbg Extension" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get the VSIX file
$vsixFile = Get-ChildItem "$projectRoot\*.vsix" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($null -eq $vsixFile) {
    Write-Host "ERROR: No VSIX file found in $projectRoot" -ForegroundColor Red
    Write-Host "Please run: .\scripts\build.ps1 -Dev" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found VSIX: $($vsixFile.Name)" -ForegroundColor Green
Write-Host ""

# Determine which command to use for cleanup/install
$codeCmd = if ($Code) { "code" } else { "code-insiders" }
$codeDisplayName = if ($Code) { "VS Code (Stable)" } else { "VS Code Insiders" }

# Check if command exists
$cmdCheck = Get-Command $codeCmd -ErrorAction SilentlyContinue
if ($null -eq $cmdCheck) {
    Write-Host "ERROR: '$codeCmd' command not found in PATH" -ForegroundColor Red
    $downloadUrl = if ($Code) { "https://code.visualstudio.com/" } else { "https://code.visualstudio.com/insiders/" }
    Write-Host "Please install $codeDisplayName from $downloadUrl" -ForegroundColor Yellow
    exit 1
}

# Step 1: Close VS Code instances
Write-Host "Cleaning up..." -ForegroundColor Yellow

$processName = if ($Code) { "code" } else { "Code - Insiders" }
$runningProcesses = Get-Process -Name code -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "code" }

if ($runningProcesses) {
    Write-Host "  Closing $codeDisplayName instances..." -ForegroundColor Gray
    $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Step 2: Uninstall old extension IDs
$oldExtensionIds = @(
    "moduleworks.vscode-debugger-launcher",
    "bradphelan.code-dbg"
)

foreach ($extId in $oldExtensionIds) {
    Write-Host "  Uninstalling old extension: $extId" -ForegroundColor Gray
    & $codeCmd --uninstall-extension $extId 2>&1 | Out-Null
}

Start-Sleep -Seconds 2

# Step 3: Install the new VSIX
Write-Host ""
Write-Host "Installing to $codeDisplayName..." -ForegroundColor Yellow

& $codeCmd --install-extension $vsixFile.FullName --force 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "? Extension installed successfully to $codeDisplayName!" -ForegroundColor Green
}
else {
    Write-Host "? Failed to install extension to $codeDisplayName" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  0. Restart your extensions ( see extensions view )" -ForegroundColor White
Write-Host "  1. Reopen ${codeDisplayName}: $codeCmd ." -ForegroundColor White
Write-Host "  2. Open a new terminal (not reuse old one)" -ForegroundColor White
Write-Host "  3. Try the command: code-dbg --help" -ForegroundColor White
Write-Host ""

