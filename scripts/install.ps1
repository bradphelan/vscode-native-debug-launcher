# Install code-dbg script for Windows
# This script installs the code-dbg Python script to a location in PATH

param(
    [string]$InstallPath = "$env:APPDATA\code-dbg"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installing code-dbg CLI Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Python 3 is installed
Write-Host "Checking Python 3 installation..." -ForegroundColor Yellow
$pythonCheck = python --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Python 3 is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Python from https://www.python.org/" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Python $pythonCheck found" -ForegroundColor Green
Write-Host ""

# Create installation directory
Write-Host "Creating installation directory..." -ForegroundColor Yellow
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "✓ Created $InstallPath" -ForegroundColor Green
}
else {
    Write-Host "✓ Directory already exists: $InstallPath" -ForegroundColor Green
}

Write-Host ""

# Copy the Python script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$pythonScript = Join-Path $projectRoot "app\code-dbg.py"

if (-not (Test-Path $pythonScript)) {
    Write-Host "ERROR: code-dbg.py not found at $pythonScript" -ForegroundColor Red
    exit 1
}

Copy-Item -Path $pythonScript -Destination "$InstallPath\code-dbg.py" -Force
Write-Host "✓ Copied code-dbg.py to $InstallPath" -ForegroundColor Green

Write-Host ""

# Create wrapper batch files for Windows
$batchFile = "$InstallPath\code-dbg.bat"
$batchContent = @"
@echo off
python "%~dp0code-dbg.py" %*
"@

Set-Content -Path $batchFile -Value $batchContent -Encoding ASCII
Write-Host "✓ Created code-dbg.bat wrapper" -ForegroundColor Green

$insidersBatchFile = "$InstallPath\code-dbg-insiders.bat"
$insidersBatchContent = @"
@echo off
python "%~dp0code-dbg.py" --insiders %*
"@

Set-Content -Path $insidersBatchFile -Value $insidersBatchContent -Encoding ASCII
Write-Host "✓ Created code-dbg-insiders.bat wrapper" -ForegroundColor Green

Write-Host ""

# Add to PATH if not already there
Write-Host "Adding to PATH..." -ForegroundColor Yellow

$userPath = [Environment]::GetEnvironmentVariable('PATH', [EnvironmentVariableTarget]::User)
if ($userPath -notlike "*$InstallPath*") {
    $newPath = "$userPath;$InstallPath"
    [Environment]::SetEnvironmentVariable('PATH', $newPath, [EnvironmentVariableTarget]::User)
    Write-Host "✓ Added $InstallPath to user PATH" -ForegroundColor Green
    Write-Host "  (Note: Restart your terminal to apply changes)" -ForegroundColor Yellow
}
else {
    Write-Host "✓ $InstallPath is already in PATH" -ForegroundColor Green
}

Write-Host ""

# Install VSIX into VS Code and VS Code Insiders if available
$vsixFile = Get-ChildItem "$projectRoot\*.vsix" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $vsixFile) {
    Write-Host "⚠ No VSIX found in project root. Build first with .\scripts\build.ps1" -ForegroundColor Yellow
}
else {
    Write-Host "Installing extension from $($vsixFile.Name)..." -ForegroundColor Yellow

    $codeCommand = Get-Command code -ErrorAction SilentlyContinue
    if ($null -ne $codeCommand) {
        & $codeCommand.Source --install-extension $vsixFile.FullName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Installed extension into VS Code" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ Failed to install extension into VS Code" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "⚠ 'code' command not found; skipping VS Code install" -ForegroundColor Yellow
    }

    $codeInsidersCommand = Get-Command code-insiders -ErrorAction SilentlyContinue
    if ($null -ne $codeInsidersCommand) {
        & $codeInsidersCommand.Source --install-extension $vsixFile.FullName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Installed extension into VS Code Insiders" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ Failed to install extension into VS Code Insiders" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "⚠ 'code-insiders' command not found; skipping VS Code Insiders install" -ForegroundColor Yellow
    }
}

Write-Host ""

# Test the installation
Write-Host "Testing installation..." -ForegroundColor Yellow
$testOutput = & "$batchFile" --help 2>&1
if ($testOutput -like "*code-dbg*") {
    Write-Host "✓ code-dbg is working correctly" -ForegroundColor Green
}
else {
    Write-Host "⚠ Could not verify installation" -ForegroundColor Yellow
}

$insidersTestOutput = & "$insidersBatchFile" --help 2>&1
if ($insidersTestOutput -like "*code-dbg*") {
    Write-Host "✓ code-dbg-insiders is working correctly" -ForegroundColor Green
}
else {
    Write-Host "⚠ Could not verify code-dbg-insiders" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "  code-dbg <exe-path> [arg1] [arg2] ..." -ForegroundColor White
Write-Host "  code-dbg-insiders <exe-path> [arg1] [arg2] ..." -ForegroundColor White
Write-Host ""
Write-Host "Example:" -ForegroundColor Yellow
Write-Host "  code-dbg myapp.exe --verbose" -ForegroundColor White
Write-Host "  code-dbg-insiders myapp.exe --verbose" -ForegroundColor White
Write-Host ""
Write-Host "Note: Restart your terminal for PATH changes to take effect!" -ForegroundColor Yellow
Write-Host ""
