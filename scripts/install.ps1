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

# Install to specified VS Code variant
if ($Code) {
    Write-Host "Installing to VS Code (Stable)..." -ForegroundColor Yellow
    
    # Check if code command exists
    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if ($null -eq $codeCmd) {
        Write-Host "ERROR: 'code' command not found in PATH" -ForegroundColor Red
        Write-Host "Please install VS Code from https://code.visualstudio.com/" -ForegroundColor Yellow
        exit 1
    }
    
    & code --install-extension $vsixFile.FullName --force
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Extension installed successfully to VS Code!" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Failed to install extension to VS Code" -ForegroundColor Red
        exit 1
    }
}

if ($CodeInsiders) {
    Write-Host "Installing to VS Code Insiders..." -ForegroundColor Yellow
    
    # Check if code-insiders command exists
    $codeInsidersCmd = Get-Command code-insiders -ErrorAction SilentlyContinue
    if ($null -eq $codeInsidersCmd) {
        Write-Host "ERROR: 'code-insiders' command not found in PATH" -ForegroundColor Red
        Write-Host "Please install VS Code Insiders from https://code.visualstudio.com/insiders/" -ForegroundColor Yellow
        exit 1
    }
    
    & code-insiders --install-extension $vsixFile.FullName --force
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Extension installed successfully to VS Code Insiders!" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Failed to install extension to VS Code Insiders" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
