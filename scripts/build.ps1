# VS Code Extension Build Script
# Builds the code-dbg extension into a .vsix file

param(
    [switch]$NoClean = $false,
    [switch]$Watch = $false,
    [switch]$PublishVSIX = $false
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Code DBG - Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Node.js is installed
Write-Host "Checking prerequisites..." -ForegroundColor Yellow
$nodeCheck = node --version 2>$null
if ($null -eq $nodeCheck) {
    Write-Host "ERROR: Node.js is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Node.js from https://nodejs.org/" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Node.js $nodeCheck found" -ForegroundColor Green

$npmCheck = npm --version 2>$null
if ($null -eq $npmCheck) {
    Write-Host "ERROR: npm is not installed" -ForegroundColor Red
    exit 1
}
Write-Host "✓ npm $npmCheck found" -ForegroundColor Green

# Check if VSCE is installed globally
$vsceCheck = vsce --version 2>$null
if ($null -eq $vsceCheck) {
    Write-Host "Installing @vscode/vsce globally..." -ForegroundColor Yellow
    npm install -g @vscode/vsce
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install @vscode/vsce" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ @vscode/vsce installed" -ForegroundColor Green
}
else {
    Write-Host "✓ vsce $vsceCheck found" -ForegroundColor Green
}

Write-Host ""

# Clean previous builds
if (-not $NoClean) {
    Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
    if (Test-Path "$projectRoot\out") {
        Remove-Item -Recurse -Force "$projectRoot\out" | Out-Null
        Write-Host "✓ Cleaned ./out" -ForegroundColor Green
    }
    if (Test-Path "$projectRoot\*.vsix") {
        Remove-Item -Force "$projectRoot\*.vsix" | Out-Null
        Write-Host "✓ Cleaned *.vsix files" -ForegroundColor Green
    }
}

Write-Host ""

# Generate version info
Write-Host "Generating version info..." -ForegroundColor Yellow
Push-Location $projectRoot
& (Join-Path $projectRoot "scripts\generate-version.ps1")
Pop-Location
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to generate version info" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Version info generated" -ForegroundColor Green

Write-Host ""

# Generate changelog
Write-Host "Generating changelog..." -ForegroundColor Yellow
Push-Location $projectRoot
& (Join-Path $projectRoot "scripts\generate-changelog.ps1")
Pop-Location
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to generate changelog" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Changelog generated" -ForegroundColor Green

Write-Host ""

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
Push-Location $projectRoot
npm install
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install npm dependencies" -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "✓ Dependencies installed" -ForegroundColor Green
Pop-Location

Write-Host ""

# Compile TypeScript
if ($Watch) {
    Write-Host "Starting TypeScript compiler in watch mode..." -ForegroundColor Yellow
    Push-Location $projectRoot
    npm run watch
    Pop-Location
}
else {
    Write-Host "Compiling TypeScript..." -ForegroundColor Yellow
    Push-Location $projectRoot
    npm run compile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: TypeScript compilation failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "✓ TypeScript compiled successfully" -ForegroundColor Green
    Pop-Location
}

if ($Watch) {
    exit 0
}

Write-Host ""

# Package as VSIX
Write-Host "Packaging extension as VSIX..." -ForegroundColor Yellow
Push-Location $projectRoot
vsce package
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to package extension" -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "✓ VSIX package created successfully" -ForegroundColor Green

# Get the generated vsix filename
$vsixFile = Get-ChildItem "$projectRoot\*.vsix" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "  Output: $($vsixFile.Name)" -ForegroundColor Green

Pop-Location

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Build Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run .\scripts\build.ps1 again to rebuild" -ForegroundColor White
Write-Host "  2. Install locally: code --install-extension $($vsixFile.Name)" -ForegroundColor White
Write-Host "  3. Publish to marketplace: vsce publish" -ForegroundColor White
Write-Host ""
