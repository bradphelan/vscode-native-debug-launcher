# VS Code Extension Build Script
# Builds the code-dbg extension into a .vsix file

param(
    [switch]$Dev = $false,
    [switch]$Release = $false,
    [switch]$NoClean = $false,
    [switch]$Watch = $false,
    [switch]$PublishVSIX = $false
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

# Validate mutually exclusive flags
if ($Dev -and $Release) {
    Write-Host "ERROR: --Dev and --Release are mutually exclusive" -ForegroundColor Red
    exit 1
}

if (-not $Dev -and -not $Release) {
    Write-Host "ERROR: Must specify either --Dev or --Release" -ForegroundColor Red
    Write-Host "Usage: .\scripts\build.ps1 -Dev    # Development build (no git tagging)" -ForegroundColor Yellow
    Write-Host "       .\scripts\build.ps1 -Release # Release build (tags and pushes)" -ForegroundColor Yellow
    exit 1
}

$buildMode = if ($Release) { "RELEASE" } else { "DEV" }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Code DBG - Build Script ($buildMode)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Pre-release validation (for --Release mode)
if ($Release) {
    Write-Host "Validating release prerequisites..." -ForegroundColor Yellow
    
    # Check working directory is clean
    $gitStatus = git status --porcelain 2>$null
    if ($gitStatus) {
        Write-Host "ERROR: Working directory has uncommitted changes" -ForegroundColor Red
        Write-Host "Please commit or stash changes before releasing" -ForegroundColor Red
        Write-Host "" -ForegroundColor Gray
        Write-Host "Uncommitted changes:" -ForegroundColor Gray
        Write-Host $gitStatus -ForegroundColor Gray
        exit 1
    }
    Write-Host "✓ Working directory is clean" -ForegroundColor Green
    
    # Check git is configured
    $gitName = git config user.name 2>$null
    $gitEmail = git config user.email 2>$null
    if (-not $gitName -or -not $gitEmail) {
        Write-Host "ERROR: Git user.name or user.email not configured" -ForegroundColor Red
        Write-Host "Run: git config user.name 'Your Name'" -ForegroundColor Yellow
        Write-Host "Run: git config user.email 'your.email@example.com'" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✓ Git configured ($gitName <$gitEmail>)" -ForegroundColor Green
    
    # Check that origin remote exists
    $remoteOrigin = git remote get-url origin 2>$null
    if (-not $remoteOrigin) {
        Write-Host "ERROR: No 'origin' remote configured" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Remote configured: $remoteOrigin" -ForegroundColor Green
}

Write-Host ""
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

# Release workflow: commit version/changelog and create tag
if ($Release) {
    Write-Host "Preparing release..." -ForegroundColor Yellow
    
    # Check if version files changed
    $gitDiff = git diff --name-only 2>$null
    
    if ($gitDiff -match "package.json|CHANGELOG.md") {
        Write-Host "Committing version bump and changelog..." -ForegroundColor Yellow
        Push-Location $projectRoot
        
        # Get the new version
        $packageJson = Get-Content "package.json" | ConvertFrom-Json
        $version = $packageJson.version
        
        git add package.json package-lock.json CHANGELOG.md 2>$null
        git commit -m "chore: bump version to $version and update changelog" --quiet 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to commit release changes" -ForegroundColor Red
            Pop-Location
            exit 1
        }
        Write-Host "✓ Release commit created (v$version)" -ForegroundColor Green
        
        # Create annotated tag
        $tagDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $tagMessage = "Release version $version`n`nBuilt: $tagDate"
        
        git tag -a "v$version" -m $tagMessage 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to create git tag" -ForegroundColor Red
            Pop-Location
            exit 1
        }
        Write-Host "✓ Git tag created: v$version" -ForegroundColor Green
        
        # Push tag to remote
        Write-Host "Pushing release to remote..." -ForegroundColor Yellow
        git push origin "v$version" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Failed to push tag to remote" -ForegroundColor Yellow
            Write-Host "Push manually with: git push origin v$version" -ForegroundColor Yellow
        } else {
            Write-Host "✓ Tag pushed to origin" -ForegroundColor Green
        }
        
        Pop-Location
    } else {
        Write-Host "No version changes to commit" -ForegroundColor Gray
    }
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
Write-Host "Build Complete! ($buildMode)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Generated:" -ForegroundColor Yellow
Write-Host "  VSIX: $($vsixFile.Name)" -ForegroundColor White

if ($Release) {
    Write-Host "  Tag: v$($packageJson.version)" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Publish to marketplace: vsce publish" -ForegroundColor White
    Write-Host "  2. Verify release on GitHub" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "Next steps (dev mode):" -ForegroundColor Yellow
    Write-Host "  1. Test locally: code --install-extension $($vsixFile.Name)" -ForegroundColor White
    Write-Host "  2. When ready to release, run: .\scripts\build.ps1 -Release" -ForegroundColor White
}

Write-Host ""
