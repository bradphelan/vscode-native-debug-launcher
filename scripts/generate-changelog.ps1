# Generate CHANGELOG.md from git commit messages
# Groups commits by version tags or generates entries for unreleased changes

param(
    [string]$OutputFile = "CHANGELOG.md",
    [string]$Since = "",
    [int]$MaxCommits = 50
)

function Get-CommitsBetween {
    param(
        [string]$Range
    )

    if ($Range) {
        $commits = git log $Range --pretty=format:"%h|%s|%an|%ad" --date=short 2>$null
    }
    else {
        $commits = git log -$MaxCommits --pretty=format:"%h|%s|%an|%ad" --date=short 2>$null
    }

    return $commits
}

function Format-CommitMessage {
    param([string]$Message)

    # Clean up common prefixes and capitalize
    $cleaned = $Message -replace '^(fix|feat|chore|docs|style|refactor|test|perf):\s*', ''

    # Capitalize first letter
    $cleaned = $cleaned.Substring(0, 1).ToUpper() + $cleaned.Substring(1)

    return $cleaned
}

function Get-CommitType {
    param([string]$Message)

    if ($Message -match '^fix:') { return 'Fixed' }
    if ($Message -match '^feat:') { return 'Added' }
    if ($Message -match '^docs:') { return 'Documentation' }
    if ($Message -match '^perf:') { return 'Performance' }
    if ($Message -match '^refactor:') { return 'Changed' }
    if ($Message -match '^test:') { return 'Testing' }
    if ($Message -match '^chore:') { return 'Maintenance' }

    return 'Changed'
}

# Get package version
$packageJson = Get-Content "package.json" | ConvertFrom-Json
$currentVersion = $packageJson.version
$currentDate = Get-Date -Format "yyyy-MM-dd"

# Get git tags (versions)
$tags = git tag --sort=-version:refname 2>$null

# Start changelog content
$changelog = @"
# Changelog

All notable changes to the "Code DBG" extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

"@

# Get unreleased commits (since last tag or all if no tags)
if ($tags) {
    $lastTag = $tags[0]
    $commitRange = "${lastTag}..HEAD"
    $sinceText = "since last tag ($lastTag)"
}
else {
    $commitRange = ""
    $sinceText = "all commits"
}

if ($Since) {
    $commitRange = "${Since}..HEAD"
    $sinceText = "since $Since"
}

Write-Host "Collecting commits $sinceText..." -ForegroundColor Cyan

$commits = Get-CommitsBetween -Range $commitRange

if ($commits) {
    # Use current version from package.json instead of "Unreleased"
    $changelog += "`n## [$currentVersion] - $currentDate`n`n"

    # Group commits by type
    $grouped = @{}

    foreach ($line in $commits) {
        if (-not $line) { continue }

        $parts = $line -split '\|'
        if ($parts.Length -lt 4) { continue }

        $hash = $parts[0]
        $message = $parts[1]
        $author = $parts[2]
        $date = $parts[3]

        $type = Get-CommitType -Message $message
        $formatted = Format-CommitMessage -Message $message

        if (-not $grouped.ContainsKey($type)) {
            $grouped[$type] = @()
        }

        $grouped[$type] += "- $formatted ($hash)"
    }

    # Output grouped commits
    $order = @('Added', 'Changed', 'Fixed', 'Performance', 'Documentation', 'Testing', 'Maintenance')

    foreach ($type in $order) {
        if ($grouped.ContainsKey($type)) {
            $changelog += "### $type`n`n"
            foreach ($item in $grouped[$type]) {
                $changelog += "$item`n"
            }
            $changelog += "`n"
        }
    }
}

# Add version history section for tagged releases
if ($tags) {
    foreach ($tag in $tags) {
        $tagDate = git log -1 --pretty=format:"%ad" --date=short $tag 2>$null
        $changelog += "## [$tag] - $tagDate`n`n"

        # Get commits for this tag (simplified - just show the tag exists)
        $changelog += "See git history for details.`n`n"
    }
}

# Write changelog
$changelog | Out-File -FilePath $OutputFile -Encoding utf8 -Force

Write-Host "Changelog generated successfully!" -ForegroundColor Green
Write-Host "  Output: $OutputFile" -ForegroundColor Gray
Write-Host "  Commits processed: $(if($commits){$commits.Count}else{0})" -ForegroundColor Gray
Write-Host ""
Write-Host "Review and edit the changelog as needed before committing." -ForegroundColor Yellow

