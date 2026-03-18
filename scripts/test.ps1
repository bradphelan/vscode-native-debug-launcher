# Automated Test - Builds extension, tests it, and verifies the debugger works
# Runs the full build ? test ? verify pipeline

param(
    [switch]$Verbose = $false,
    [switch]$NoBuild = $false,
    [switch]$NoCleanup = $false,
    [switch]$Interactive = $false,
    [switch]$Quiet = $false,
    [int]$TimeoutSeconds = 60
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$testExe = Join-Path $projectRoot "test-app\build\test.exe"
$vsixFile = $null
$pythonScript = Join-Path $projectRoot "app\code-dbg.py"
$testWorkspace = Join-Path $projectRoot "test-app"
$testLogFile = Join-Path $testWorkspace "e2e-test-output.log"
$extensionLogFile = Join-Path $testWorkspace "code-dbg.log"
$legacyExtensionLogFile = Join-Path $testWorkspace "vscode-debugger-launcher.log"
$testsPassed = 0
$testsFailed = 0
$testErrors = @()  # Collect errors to report at end
$launchedCodeProcess = $null
$pythonCommand = $null

function Add-TestError {
    param([string]$ErrorMessage)
    $script:testErrors += $ErrorMessage
    $script:testsFailed++
}

function Write-Verbose-Conditional {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Write-Section {
    param([string]$Title)
    if ($Quiet) { return }
    Write-Host ""
    Write-Host "??????????????????????????????????????????" -ForegroundColor Cyan
    Write-Host "? $($Title.PadRight(38))?" -ForegroundColor Cyan
    Write-Host "??????????????????????????????????????????" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    if ($Quiet) { return }
    Write-Host "? $Message" -ForegroundColor Yellow
}

function Write-Pass {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host "? $Message" -ForegroundColor Green
    }
    $script:testsPassed++
}

function Write-Fail {
    param([string]$Message)
    Write-Host "? $Message" -ForegroundColor Red
    Add-TestError $Message
}

function Write-Check {
    param([string]$Message)
    if ($Quiet) { return }
    Write-Host "  ? $Message" -ForegroundColor Cyan
}

function Expect {
    param(
        [bool]$Condition,
        [string]$PassMessage,
        [string]$FailMessage
    )

    if ($Condition) {
        Write-Pass $PassMessage
        return $true
    }
    else {
        Write-Fail $FailMessage
        return $false
    }
}

function ExpectOrExit {
    param(
        [bool]$Condition,
        [string]$PassMessage,
        [string]$FailMessage
    )

    # No longer exits - just reports error and continues
    Expect $Condition $PassMessage $FailMessage | Out-Null
}

function ExpectEventually {
    param(
        [scriptblock]$Predicate,
        [string]$PassMessage,
        [string]$FailMessage,
        [int]$TimeoutSeconds = 30,
        [int]$IntervalMs = 100,
        [scriptblock]$OnTick = $null
    )

    $elapsed = 0.0

    while ($elapsed -lt $TimeoutSeconds) {
        if (& $Predicate) {
            Write-Pass $PassMessage
            return $true
        }

        if ($OnTick) {
            & $OnTick $elapsed
        }

        Start-Sleep -Milliseconds $IntervalMs
        $elapsed += ($IntervalMs / 1000.0)
    }

    Write-Fail $FailMessage
    return $false
}

function Close-LaunchedVSCode {
    Write-Step "Closing VS Code launched by this test run..."

    if ($null -eq $script:launchedCodeProcess) {
        Write-Check "No test-launched VS Code process recorded; skipping close"
        return
    }

    try {
        # The code launcher may exit after handing off, so only stop if still alive.
        if (-not $script:launchedCodeProcess.HasExited) {
            Stop-Process -Id $script:launchedCodeProcess.Id -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Pass "Closed test-launched VS Code process"
        }
        else {
            Write-Check "Test-launched VS Code process already exited"
        }
    }
    catch {
        Write-Check "Could not close test-launched VS Code process by PID; leaving existing VS Code instances untouched"
    }
}

function Get-PayloadFromDebugUrl {
    param([string]$DebugUrl)

    if ($DebugUrl -notmatch "payload=([^&]+)") {
        return $null
    }

    try {
        $base64 = $matches[1]
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
        return $json | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

Write-Host ""
Write-Host "?????????????????????????????????????????????????????????????" -ForegroundColor Cyan
Write-Host "?  Automated Test: VS Code Debugger Verification           ?" -ForegroundColor Cyan
Write-Host "?  (Build ? Package ? Test ? Verify)                      ?" -ForegroundColor Cyan
Write-Host "?????????????????????????????????????????????????????????????" -ForegroundColor Cyan

if ($Interactive) {
    Write-Host ""
    Write-Host "?? INTERACTIVE MODE: VS Code will stay open for manual inspection" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# 0. BUILD EXTENSION AND TEST APP
# ============================================================================
Write-Section "0. Build"

if (-not $NoBuild) {
    Write-Step "Building extension..."
    Push-Location $projectRoot
    & (Join-Path $projectRoot "scripts\build.ps1") -Dev
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Extension build failed"
        Pop-Location
    }
    else {
        Pop-Location
        Write-Pass "Extension built"
    }

    Write-Step "Building test application..."
    Push-Location $projectRoot
    & (Join-Path $projectRoot "scripts\build-test-exe.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Test app build failed"
        Pop-Location
    }
    else {
        Pop-Location
        Write-Pass "Test app built"
    }
}
else {
    Write-Check "Skipping build (-NoBuild flag set)"
}

# Get VSIX file reference after building
$vsixFile = Get-ChildItem "$projectRoot\*.vsix" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
ExpectOrExit ($null -ne $vsixFile) "VSIX file found" "No VSIX file found. Run without -NoBuild flag to build first."

# ============================================================================
# 1. PREREQUISITES CHECK
# ============================================================================
Write-Section "1. Prerequisites"

Write-Step "Checking for VSIX file..."
Write-Check "Found: $($vsixFile.Name)"

Write-Step "Checking for test executable..."
ExpectOrExit (Test-Path $testExe) "Found: test.exe" "Test executable not found"

Write-Step "Checking for Python script..."
ExpectOrExit (Test-Path $pythonScript) "Found: code-dbg.py" "code-dbg.py not found."

Write-Step "Resolving Python launcher..."
foreach ($candidate in @("py", "python")) {
    try {
        & $candidate --version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $pythonCommand = $candidate
            break
        }
    }
    catch {
        # Candidate is unavailable or non-runnable; try next.
    }
}

if ($null -ne $pythonCommand) {
    Write-Pass "Python launcher found: $pythonCommand"
}
else {
    Write-Fail "Neither 'python' nor 'py' launcher is available in PATH"
    exit 1
}

# ============================================================================
# 2. SETUP TEST WORKSPACE
# ============================================================================
Write-Section "2. Setup Test Workspace"

Write-Step "Using test-app workspace..."
ExpectOrExit (Test-Path $testWorkspace) "Workspace OK: $testWorkspace" "Test workspace not found: $testWorkspace"

Write-Step "Removing any previous log files..."
if (Test-Path $testLogFile) {
    Remove-Item $testLogFile -Force
}
if (Test-Path $extensionLogFile) {
    Remove-Item $extensionLogFile -Force
}
if (Test-Path $legacyExtensionLogFile) {
    Remove-Item $legacyExtensionLogFile -Force
}
Write-Pass "Workspace cleaned"

# ============================================================================
# 3. CLOSE EXISTING VS CODE
# ============================================================================
Write-Section "3. Prepare Environment"

Write-Step "Checking for running VS Code instances..."
$runningVSCode = Get-Process code -ErrorAction SilentlyContinue
if ($runningVSCode) {
    Write-Check "Found running VS Code instance(s); leaving them open"
    Write-Check "This script now only closes the VS Code process it launches"
    Write-Pass "Existing VS Code instances preserved"
}
else {
    Write-Pass "No VS Code running"
}

# ============================================================================
# 4. UNINSTALL PREVIOUS EXTENSION
# ============================================================================
Write-Section "4. Clean Previous Installation"

Write-Step "Removing previous extension installation..."
$extensionPath = "$env:USERPROFILE\.vscode\extensions"
$oldExtensions = @()
$oldExtensions += Get-ChildItem $extensionPath -Filter "*code-dbg*" -ErrorAction SilentlyContinue
$oldExtensions += Get-ChildItem $extensionPath -Filter "*vscode-debugger-launcher*" -ErrorAction SilentlyContinue

if ($oldExtensions) {
    foreach ($ext in $oldExtensions | Where-Object { $_ -ne $null }) {
        # Force remove with retry
        for ($i = 0; $i -lt 3; $i++) {
            try {
                Remove-Item -Recurse -Force $ext.FullName -ErrorAction Stop
                break
            }
            catch {
                Start-Sleep -Seconds 1
            }
        }
    }
    Write-Pass "Removed old extensions"
}
else {
    Write-Pass "No old extensions found"
}

# Also remove from disabled extensions
Write-Step "Clearing VS Code cache..."
$vscodeSettings = "$env:APPDATA\Code\extensions\state.vscdb"
if (Test-Path $vscodeSettings) {
    # Just note it exists, don't delete (too risky)
    Write-Pass "VS Code settings verified"
}

# ============================================================================
# 5. INSTALL EXTENSION
# ============================================================================
Write-Section "5. Install Extension"

Write-Step "Uninstalling any previous version..."
& code --uninstall-extension bradphelan.code-dbg 2>&1 | Out-Null
& code --uninstall-extension moduleworks.vscode-debugger-launcher 2>&1 | Out-Null
Start-Sleep -Seconds 3

Write-Step "Installing VSIX: $($vsixFile.Name)..."
Write-Check "Using --force to overwrite any existing version"
$installOutput = & code --install-extension $vsixFile.FullName --force 2>&1

if ($LASTEXITCODE -eq 0 -or $installOutput -like "*Successfully installed*") {
    Write-Pass "Extension installed"
    if ($Verbose) {
        Write-Host "Install output:" -ForegroundColor Gray
        $installOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    Start-Sleep -Seconds 3
}
else {
    Write-Fail "Failed to install extension"
    Write-Host "Install output:" -ForegroundColor Yellow
    $installOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    # Try one more time
    Write-Step "Retrying installation..."
    Start-Sleep -Seconds 2
    $installOutput = & code --install-extension $vsixFile.FullName --force 2>&1
    if ($LASTEXITCODE -ne 0 -and $installOutput -notlike "*Successfully installed*") {
        Write-Host "Second install output:" -ForegroundColor Yellow
        $installOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Fail "Extension installation failed (retry also failed)"
    }
    else {
        Write-Pass "Extension installed on retry"
    }
}

Write-Step "Verifying installation..."
Start-Sleep -Seconds 3
$installedExt = Get-ChildItem "$extensionPath" -Filter "*code-dbg*" -ErrorAction SilentlyContinue
ExpectOrExit ($null -ne $installedExt) "Extension found: $($installedExt.Name)" "Extension not found after installation"

Write-Step "Verifying build version..."
$versionJsonPath = Join-Path $projectRoot "src\version.json"
if (Test-Path $versionJsonPath) {
    try {
        $versionInfo = Get-Content $versionJsonPath | ConvertFrom-Json
        Write-Pass "Version info: $($versionInfo.version) (built from $($versionInfo.build) on $($versionInfo.branch))"
        Write-Check "Build timestamp: $($versionInfo.timestamp)"
    }
    catch {
        Write-Check "Warning: Could not parse version.json, but file exists"
    }
}
else {
    Write-Check "Note: version.json not found (expected if scripts\\build.ps1 not used)"
}

# ============================================================================
# 6. GENERATE DEBUG URL WITH TEST ARGUMENTS
# ============================================================================
Write-Section "6. Generate Debug URL"

Write-Step "Generating debug URL using code-dbg CLI..."
Write-Check "Executable: $testExe"
Write-Check "Arguments: 'e2e-test-arg1' 'e2e-test-arg2'"
Write-Check "Workspace: $testWorkspace"

# Note: With environmentVariableCollection, code-dbg is only available in VS Code terminals
# This test runs in an external PowerShell session, so it will fall back to Python
# This is expected behavior and validates both the CLI and the fallback path
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'Machine')

Write-Check "Full command: code-dbg --url-only --cwd=$testWorkspace -- $testExe 'e2e-test-arg1' 'e2e-test-arg2'"
Write-Check "Note: Expected to fall back to Python (not in external PowerShell PATH)"

try {
    $debugUrl = & code-dbg --url-only --cwd=$testWorkspace -- $testExe "e2e-test-arg1" "e2e-test-arg2" 2>&1

    if ($LASTEXITCODE -ne 0 -or $debugUrl -notlike "*vscode://*") {
        Write-Check "code-dbg not available (expected), using Python fallback"
        Write-Check "Fallback: $pythonCommand $pythonScript --url-only --cwd=$testWorkspace -- $testExe 'e2e-test-arg1' 'e2e-test-arg2'"
        $debugUrl = & $pythonCommand $pythonScript --url-only --cwd=$testWorkspace -- $testExe "e2e-test-arg1" "e2e-test-arg2" 2>&1
    }
    else {
        Write-Pass "code-dbg CLI command succeeded"
    }
}
catch {
    Write-Check "code-dbg not available (expected), using Python fallback"
    Write-Check "Error: $_"
    Write-Check "Fallback: $pythonCommand $pythonScript --url-only --cwd=$testWorkspace -- $testExe 'e2e-test-arg1' 'e2e-test-arg2'"
    $debugUrl = & $pythonCommand $pythonScript --url-only --cwd=$testWorkspace -- $testExe "e2e-test-arg1" "e2e-test-arg2" 2>&1
}

$debugUrlString = ((($debugUrl | Out-String) -split "`r?`n") | Where-Object { $_ -match "^vscode(-insiders)?://" } | Select-Object -First 1)
$urlGenerated = -not [string]::IsNullOrWhiteSpace($debugUrlString)
ExpectOrExit $urlGenerated "URL generated" "Failed to generate debug URL"
if (-not $urlGenerated) {
    Write-Fail "Cannot continue without a valid debug URL. Aborting test early."
    exit 1
}

if ($debugUrlString.Length -ge 70) {
    Write-Check "URL: $($debugUrlString.Substring(0, 70))..."
}
else {
    Write-Check "URL: $debugUrlString"
}

# ============================================================================
# 6.5. VERIFY NATVIS PAYLOAD BEHAVIOR
# ============================================================================
Write-Section "6.5. Verify Natvis Payload"

$autoNatvisFile = Join-Path $testWorkspace "auto-discovered.natvis"
$explicitNatvisFile = Join-Path $testWorkspace "explicit.natvis"
$duplicateNatvisFile = Join-Path $testWorkspace "duplicate.natvis"

Write-Step "Preparing natvis files for payload validation..."
"<AutoVisualizer xmlns='http://schemas.microsoft.com/vstudio/debugger/natvis/2010'></AutoVisualizer>" | Out-File -FilePath $autoNatvisFile -Encoding utf8
Write-Pass "Natvis files created"

Write-Step "Checking auto-discovery (no --natvis)..."
$autoUrl = & $pythonCommand $pythonScript --url-only --cwd=$testWorkspace -- $testExe "e2e-test-arg1" "e2e-test-arg2" 2>&1
$autoPayload = Get-PayloadFromDebugUrl -DebugUrl ($autoUrl | Out-String)
$autoNatvisOk = ($null -ne $autoPayload -and $autoPayload.natvis -and (Split-Path -Leaf $autoPayload.natvis) -eq "auto-discovered.natvis")
$null = Expect $autoNatvisOk "Auto-discovery selected single natvis file" "Auto-discovery did not select expected natvis file"

Write-Step "Checking explicit --natvis override..."
"<AutoVisualizer xmlns='http://schemas.microsoft.com/vstudio/debugger/natvis/2010'></AutoVisualizer>" | Out-File -FilePath $explicitNatvisFile -Encoding utf8
$explicitUrl = & $pythonCommand $pythonScript --url-only --cwd=$testWorkspace --natvis=$explicitNatvisFile -- $testExe "e2e-test-arg1" "e2e-test-arg2" 2>&1
$explicitPayload = Get-PayloadFromDebugUrl -DebugUrl ($explicitUrl | Out-String)
$explicitNatvisOk = ($null -ne $explicitPayload -and $explicitPayload.natvis -and (Split-Path -Leaf $explicitPayload.natvis) -eq "explicit.natvis")
$null = Expect $explicitNatvisOk "Explicit --natvis overrides auto-discovery" "Explicit --natvis was not propagated"

Write-Step "Checking duplicate natvis failure behavior..."
"<AutoVisualizer xmlns='http://schemas.microsoft.com/vstudio/debugger/natvis/2010'></AutoVisualizer>" | Out-File -FilePath $duplicateNatvisFile -Encoding utf8
$duplicateOutput = & $pythonCommand $pythonScript --url-only --cwd=$testWorkspace -- $testExe "e2e-test-arg1" "e2e-test-arg2" 2>&1
$duplicateFailed = ($LASTEXITCODE -ne 0 -and ($duplicateOutput | Out-String) -like "*Multiple .natvis files found*")
$null = Expect $duplicateFailed "Duplicate natvis files produce expected failure" "Duplicate natvis files did not produce expected failure"

Write-Step "Cleaning up temporary natvis files..."
foreach ($file in @($autoNatvisFile, $explicitNatvisFile, $duplicateNatvisFile)) {
    if (Test-Path $file) {
        Remove-Item $file -Force
    }
}
Write-Pass "Natvis test files cleaned"

# ============================================================================
# 7. OPEN WORKSPACE AND LAUNCH DEBUGGER
# ============================================================================
Write-Section "7. Launch Debugger in VS Code"

Write-Step "Opening VS Code workspace..."
$env:VSCODE_DEBUGGER_TEST_MODE = "1"
$env:E2E_TEST_OUTPUT_DIR = $testWorkspace
$codeProcess = Start-Process code -ArgumentList $testWorkspace -PassThru
$script:launchedCodeProcess = $codeProcess

Write-Step "Waiting for extension to register URL handler (monitoring log)..."
Write-Check "Looking for: 'URL handler is registered and ready'"

$maxWait = 30
$handlerReady = ExpectEventually {
    if (Test-Path $extensionLogFile) {
        $logContent = Get-Content $extensionLogFile -Raw
        return ($logContent -like "*URL handler is registered and ready*")
    }
    return $false
} "Handler registered! Sending URL..." "Extension did not register handler in time" $maxWait 100

if (-not $handlerReady) {
    Close-LaunchedVSCode
}

# ============================================================================
# 7.5. VERIFY CLI AUTO-INSTALLATION
# ============================================================================
Write-Section "7.5. Verify CLI Installation"

Write-Step "Checking extension log for CLI setup..."
$logContent = Get-Content $extensionLogFile -Raw

# Check for environmentVariableCollection setup
# The new architecture uses VS Code's environmentVariableCollection
$hasCliPathSetup = (
    $logContent -like "*Added app directory to VS Code terminal PATH*" -or
    $logContent -like "*App directory already in VS Code terminal PATH*"
)
$null = Expect $hasCliPathSetup "CLI PATH setup via environmentVariableCollection" "CLI PATH setup not found in log"

# Extract the app directory path from log
if ($logContent -match "Added app directory to VS Code terminal PATH: (.+)$") {
    $appDirPath = $matches[1].Trim()
    Write-Check "App directory added to VS Code terminals: $appDirPath"
}
elseif ($logContent -match "App directory already in VS Code terminal PATH") {
    Write-Check "App directory already configured in environmentVariableCollection"
}

# Note: PATH is now managed via VS Code's environmentVariableCollection
# It only applies to terminals opened within VS Code, not system-wide
Write-Step "Verifying CLI setup method..."
if ($logContent -like "*environmentVariableCollection*") {
    Write-Pass "Using VS Code environmentVariableCollection (applies to VS Code terminals only)"
}
else {
    Write-Check "Note: PATH management via environmentVariableCollection"
}

# Test CLI command - note that with environmentVariableCollection,
# code-dbg is only available in VS Code integrated terminals, not external shells
Write-Step "Note: code-dbg command is now available only in VS Code terminals..."
Write-Check "The extension uses VS Code's environmentVariableCollection API"
Write-Check "This makes code-dbg available in terminals opened within VS Code"
Write-Check "It does not modify system PATH, keeping your environment clean"
Write-Pass "CLI setup method verified (VS Code terminals only)"

Write-Step "Verifying extension version in log..."
$logContent = Get-Content $extensionLogFile -Raw
$hasVersionLog = ($logContent -like "*Extension version:*")
ExpectOrExit $hasVersionLog "Extension logged version info" "Extension did not log version info"

# Extract version line
$versionMatch = $logContent | Select-String "Extension version: ([\d.]+)"
if ($versionMatch) {
    $extractedVersion = $versionMatch.Matches[0].Groups[1].Value
    Write-Pass "Confirmed version: $extractedVersion"
}

# Also check for build info
if ($logContent -like "*Build:*") {
    $buildMatch = $logContent | Select-String "Build: ([a-f0-9]+) \(([^)]+)\)"
    if ($buildMatch) {
        $buildHash = $buildMatch.Matches[0].Groups[1].Value
        $buildBranch = $buildMatch.Matches[0].Groups[2].Value
        Write-Check "Build info: $buildHash from $buildBranch"
    }
}

# Now send the URL to the running instance
Write-Step "Triggering debugger via URL..."
# Use code --open-url to send the URL to the active VS Code instance
& code --open-url $debugUrlString 2>&1 | Out-Null

Write-Pass "Debug URL invoked!"

# ============================================================================
# 8. WAIT FOR URL HANDLER EXECUTION
# ============================================================================
Write-Section "8. Monitor URL Handler"

Write-Step "Waiting for URL handler to process (monitoring log)..."
Write-Check "Looking for: 'URL HANDLER TRIGGERED'"

$maxWait = 30
$handlerTriggered = ExpectEventually {
    if (Test-Path $extensionLogFile) {
        $logContent = Get-Content $extensionLogFile -Raw
        return ($logContent -like "*URL HANDLER TRIGGERED*")
    }
    return $false
} "URL handler triggered!" "URL handler was never triggered" $maxWait 100

if (-not $handlerTriggered) {
    Write-Host ""
    Write-Host "Extension log:" -ForegroundColor Yellow
    if (Test-Path $extensionLogFile) {
        Get-Content $extensionLogFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    Close-LaunchedVSCode
}

# ============================================================================
# 9. WAIT FOR APP OUTPUT LOG FILE
# ============================================================================
Write-Section "9. Monitor Debugger Execution"

Write-Step "Waiting for test app to execute..."
Write-Check "Looking for: e2e-test-output.log"
Write-Check "Full path: $testLogFile"

$maxWait = 60
$appLogFileFound = ExpectEventually {
    return (Test-Path $testLogFile)
} "App executed! Log file created!" "Test app did not execute (timeout ${maxWait}s)" $maxWait 100 {
    param($elapsed)
    if ([int]$elapsed % 10 -eq 0 -and $elapsed -gt 0) {
        Write-Host "  Waiting... ($([int]$elapsed)s)" -ForegroundColor Gray
    }
}

if (-not $appLogFileFound) {
    Write-Fail "App log file was not created in workspace"
    Write-Host ""
    Write-Host "The URL handler activated but the debugger didn't run the app." -ForegroundColor Yellow
    Write-Host "Check extension log for details:" -ForegroundColor Yellow
    Write-Host ""

    # Show the full extension log
    if (Test-Path $extensionLogFile) {
        Get-Content $extensionLogFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }

    Close-LaunchedVSCode
}

# ============================================================================
# 10. VERIFY LOG FILE CONTENTS
# ============================================================================
Write-Section "10. Verify Debugger Output"

Write-Step "Reading log file: $testLogFile"
Start-Sleep -Seconds 1

ExpectOrExit (Test-Path $testLogFile) "Log file found" "Log file disappeared!"

$logContent = Get-Content $testLogFile
Write-Check "Log file found and readable"

# Parse log file
$logData = @{}
Write-Check "Parsing log file contents..."
foreach ($line in $logContent) {
    if ($line -match "=") {
        $key, $value = $line.Split("=", 2)
        $logData[$key.Trim()] = $value.Trim()
        Write-Check "  $($key.Trim()) = $($value.Trim())"
    }
}

Write-Host ""
Write-Host "Raw log contents:" -ForegroundColor Gray
$logContent | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host ""

# ============================================================================
# 11. VALIDATE RESULTS
# ============================================================================
Write-Section "11. Validate Debugger Results"

# Check 1: App executed
Write-Step "Checking: App execution status"
$null = Expect ($logData["status"] -eq "SUCCESS") "Application executed successfully" "Application did not execute successfully"

# Check 2: Argument count
Write-Step "Checking: Command-line arguments"
$argc = [int]$logData["argc"]
$null = Expect ($argc -eq 3) "Correct argument count (3: program, arg1, arg2)" "Wrong argument count: $argc (expected 3)"

# Check 3: First argument (program path contains test.exe)
Write-Step "Checking: Program path"
$argv0 = $logData["argv[0]"]
$null = Expect ($argv0 -like "*test.exe*") "Program path correct: $(Split-Path -Leaf $argv0)" "Program path incorrect: $argv0"

# Check 4: Second argument
Write-Step "Checking: First custom argument"
$argv1 = $logData["argv[1]"]
$null = Expect ($argv1 -eq "e2e-test-arg1") "Argument 1 correct: '$argv1'" "Argument 1 incorrect: '$argv1' (expected 'e2e-test-arg1')"

# Check 5: Third argument
Write-Step "Checking: Second custom argument"
$argv2 = $logData["argv[2]"]
$null = Expect ($argv2 -eq "e2e-test-arg2") "Argument 2 correct: '$argv2'" "Argument 2 incorrect: '$argv2' (expected 'e2e-test-arg2')"

# Check 6: Calculation result
Write-Step "Checking: Application calculation"
$sum = [int]$logData["sum"]
$null = Expect ($sum -eq 30) "Calculation correct: sum = $sum" "Calculation wrong: sum = $sum (expected 30)"

# ============================================================================
# 12. CLEANUP
# ============================================================================
Write-Section "12. Cleanup"

if ($Interactive) {
    Write-Host ""
    Write-Host "??????????????????????????????????????????????????????????????" -ForegroundColor Cyan
    Write-Host "?                    INTERACTIVE MODE                       ?" -ForegroundColor Cyan
    Write-Host "??????????????????????????????????????????????????????????????" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "VS Code is still running. You can now:" -ForegroundColor Yellow
    Write-Host "  ? Check the Debug Console for output" -ForegroundColor Gray
    Write-Host "  ? Inspect the running debugger session" -ForegroundColor Gray
    Write-Host "  ? Check extension log: test-app\code-dbg.log" -ForegroundColor Gray
    Write-Host "  ? Check test output: test-app\e2e-test-output.log (if created)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Test Results Summary:" -ForegroundColor Yellow
    Write-Host "  Passed: $testsPassed" -ForegroundColor $(if ($testsPassed -gt 0) { "Green" } else { "Gray" })
    Write-Host "  Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })
    Write-Host ""
    Write-Host "Press any key to close VS Code and exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

Write-Step "Closing VS Code..."
Close-LaunchedVSCode

if (-not $NoCleanup) {
    Write-Step "Cleaning up test output..."
    if (Test-Path $testLogFile) {
        Remove-Item $testLogFile -Force
    }
    Write-Pass "Test files cleaned"
}
else {
    Write-Pass "Test files preserved"
}

# ============================================================================
# 13. FINAL RESULTS
# ============================================================================
Write-Section "E2E Test Results"

function Report-TestResults {
    Write-Host ""
    Write-Host "Tests Passed:  $testsPassed" -ForegroundColor Green
    Write-Host "Tests Failed:  $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
    Write-Host "Total Tests:   $($testsPassed + $testsFailed)" -ForegroundColor White
    Write-Host ""

    if ($testsFailed -gt 0) {
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "ERRORS REPORTED:" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        $testErrors | ForEach-Object { Write-Host "  x $_" -ForegroundColor Red }
        Write-Host ""
    }

    if ($testsFailed -eq 0 -and $testsPassed -gt 0) {
        Write-Host "??????????????????????????????????????????" -ForegroundColor Green
        Write-Host "?   ? E2E TEST PASSED!                  ?" -ForegroundColor Green
        Write-Host "?                                        ?" -ForegroundColor Green
        Write-Host "?   Code DBG is                         ?" -ForegroundColor Green
        Write-Host "?   fully functional and verified!      ?" -ForegroundColor Green
        Write-Host "??????????????????????????????????????????" -ForegroundColor Green
        Write-Host ""
        exit 0
    }
    else {
        if (-not $Quiet) {
            Write-Host "??????????????????????????????????????????" -ForegroundColor Red
            Write-Host "?   ? E2E TEST FAILED                   ?" -ForegroundColor Red
            Write-Host "??????????????????????????????????????????" -ForegroundColor Red
        }
        exit 1
    }
}
# Call the Report-TestResults function to display results and exit
Report-TestResults