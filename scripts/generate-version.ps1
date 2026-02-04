# Generate version info for the extension
# This captures the git commit hash and package version
#
# For -Dev builds: Uses pre-release suffix (e.g., 0.1.41-dev.20260204.1)
#                  Does NOT update package.json (stays ready for release)
# For -Release builds: Increments patch version (e.g., 0.1.41 -> 0.1.42)
#                      Updates package.json

param(
    [switch]$Dev = $false,
    [string]$OutputFile = "./src/version.json"
)

# Read package.json version
$packageJsonPath = "package.json"
$packageJson = Get-Content $packageJsonPath | ConvertFrom-Json
$baseVersion = $packageJson.version

# Parse version (major.minor.patch)
if ($baseVersion -match '^(\d+)\.(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]

    if ($Dev) {
        # Development build: Use pre-release suffix with date and random number
        # Format: major.minor.patch-dev.YYYYMMDD.NNN
        $dateStamp = Get-Date -Format "yyyyMMdd"
        $buildNumber = Get-Random -Minimum 1 -Maximum 1000
        $version = "$major.$minor.$patch-dev.$dateStamp.$buildNumber"

        Write-Host "Development build version: $version" -ForegroundColor Cyan
        Write-Host "  Base: $baseVersion (unchanged in package.json)" -ForegroundColor Gray
        Write-Host "  Pre-release suffix: -dev.$dateStamp.$buildNumber" -ForegroundColor Yellow
    }
    else {
        # Release build: Increment patch version
        $patch++
        $version = "$major.$minor.$patch"

        # Update package.json with new version
        $packageJson.version = $version
        $packageJson | ConvertTo-Json -Depth 100 | Set-Content $packageJsonPath

        Write-Host "Release build version: $version" -ForegroundColor Cyan
        Write-Host "  Bumped from: $baseVersion ? $version" -ForegroundColor Green
    }
}
else {
    Write-Host "Warning: Could not parse version, using as-is" -ForegroundColor Yellow
    $version = $baseVersion
}

# Get git commit hash (short)
$gitHash = git rev-parse --short HEAD 2>$null
if (-not $gitHash) {
    $gitHash = "unknown"
}

# Get git branch
$gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
if (-not $gitBranch) {
    $gitBranch = "unknown"
}

# Build timestamp
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"

# Create version object
$versionInfo = @{
    version   = $version
    build     = $gitHash
    branch    = $gitBranch
    timestamp = $timestamp
} | ConvertTo-Json

# Write to file
$versionInfo | Out-File -FilePath $OutputFile -Encoding utf8 -Force

Write-Host "Version info generated:" -ForegroundColor Green
Write-Host "  Version: $version"
Write-Host "  Build: $gitHash"
Write-Host "  Branch: $gitBranch"
Write-Host "  Timestamp: $timestamp"
Write-Host "  Output: $OutputFile"
