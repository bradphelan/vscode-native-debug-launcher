# Build script for test executables
# Compiles test-app\hello.cpp to test.exe using MSVC

param(
    [switch]$ReleaseMode = $false
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$testAppDir = Join-Path $projectRoot "test-app"
$buildDir = Join-Path $testAppDir "build"
$helloSrc = Join-Path $testAppDir "hello.cpp"
$output = Join-Path $buildDir "test.exe"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building Test Application" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create build directory
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    Write-Host "✓ Created build directory: $buildDir" -ForegroundColor Green
}

# Check if source file exists
if (-not (Test-Path $helloSrc)) {
    Write-Host "ERROR: Source file not found: $helloSrc" -ForegroundColor Red
    exit 1
}

# Look for MSVC compiler
Write-Host "Locating MSVC compiler..." -ForegroundColor Yellow

# Try to find cl.exe in common Visual Studio locations
$clPaths = @(
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe"
)

$clExe = $null
foreach ($path in $clPaths) {
    $found = Get-Item $path -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $clExe = $found.FullName
        break
    }
}

# Also check if cl.exe is in PATH
if (!$clExe) {
    $clExe = Get-Command cl.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

if (!$clExe) {
    Write-Host "ERROR: MSVC compiler (cl.exe) not found" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "You need Visual Studio Build Tools or Visual Studio Community Edition." -ForegroundColor Red
    Write-Host "Download from: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "Or install Visual C++ Build Tools:" -ForegroundColor Red
    Write-Host "  https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Found MSVC at: $clExe" -ForegroundColor Green
Write-Host ""

# Compile
Write-Host "Compiling $([System.IO.Path]::GetFileName($helloSrc))..." -ForegroundColor Yellow

$compileArgs = @(
    $helloSrc,
    "/Fe$output",                # Output executable
    "/Fd$($buildDir)\test.pdb",  # Debug info
    "/Fo$($buildDir)\"           # Object files
)

if ($ReleaseMode) {
    $compileArgs += "/O2"        # Optimize for speed
    $compileArgs += "/NDEBUG"    # Release mode
    Write-Host "  Mode: Release" -ForegroundColor White
}
else {
    $compileArgs += "/Zi"        # Full debug info
    $compileArgs += "/Od"        # No optimization (debug)
    Write-Host "  Mode: Debug" -ForegroundColor White
}

$compileArgs += "/TC"           # Compile as C (not C++)
$compileArgs += "/W3"           # Warning level 3
$compileArgs += "/nologo"       # Don't show compiler banner

# Run compiler
& $clExe @compileArgs 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Compilation failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Note: This might be due to missing Windows SDK headers." -ForegroundColor Yellow
    Write-Host "Make sure you have Visual Studio with C++ development tools installed." -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Compilation successful" -ForegroundColor Green
Write-Host ""

# Verify output
if (Test-Path $output) {
    $fileSize = (Get-Item $output).Length
    Write-Host "✓ Executable created: $output" -ForegroundColor Green
    Write-Host "  Size: $($fileSize / 1KB)KB" -ForegroundColor Green
}
else {
    Write-Host "ERROR: Output executable not found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Build Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: Run the test suite with: .\scripts\test.ps1" -ForegroundColor Yellow
Write-Host ""
