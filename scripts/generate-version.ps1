# Generate version info for the extension
# This captures the git commit hash and package version
# Auto-increments patch version on each build

param(
    [string]$OutputFile = "./src/version.json"
)

# Read package.json version
$packageJsonPath = "package.json"
$packageJson = Get-Content $packageJsonPath | ConvertFrom-Json
$currentVersion = $packageJson.version

# Parse version (major.minor.patch)
if ($currentVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]

    # Increment patch version
    $patch++
    $newVersion = "$major.$minor.$patch"

    # Update package.json with new version
    $packageJson.version = $newVersion
    $packageJson | ConvertTo-Json -Depth 100 | Set-Content $packageJsonPath

    Write-Host "Version bumped: $currentVersion → $newVersion" -ForegroundColor Cyan
    $version = $newVersion
}
else {
    Write-Host "Warning: Could not parse version, using as-is" -ForegroundColor Yellow
    $version = $currentVersion
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
