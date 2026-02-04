# Code DBG

Launch executables with the VS Code debugger from the terminal—**no `launch.json` required**.

Solves https://github.com/microsoft/vscode/issues/10979

## Purpose

This extension enables debugging any executable directly from the command line by creating a VS Code URL handler that selects a debugger and launches the debug session.

**No configuration needed.** Just run:

```powershell
code-dbg -- myapp.exe arg1 arg2
```

The extension parses the debug URL, validates the workspace and executable, and starts debugging—all without touching `launch.json`.

## Installation

### From VS Code Marketplace

1. Install the extension from the [VS Code Marketplace](https://marketplace.visualstudio.com/) or search for "Code DBG" in VS Code's Extensions view (`Ctrl+Shift+X`)
2. The CLI script (`code-dbg`) is automatically installed to your system PATH when the extension activates
3. **Restart your terminal** after installation to use the `code-dbg` command

The extension will:

- Auto-install the CLI script to `%APPDATA%\code-dbg` (Windows)
- Update your PATH environment variable
- Notify you when installation completes
- Auto-upgrade the CLI when you update the extension

**Manual Commands:**

- `Code DBG: Install CLI` - Reinstall the CLI script
- `Code DBG: Check CLI Status` - Verify installation and version

### From Source

See the [Build and Install](#build-and-install-from-source) section below for manual installation from source code.

## Usage

**Basic:**

```powershell
code-dbg [OPTIONS] -- <executable> [arguments...]
```

**Options:**

- `--cwd=<dir>` — Working directory (defaults to current directory)
- `--insiders` — Use VS Code Insiders URL scheme and launcher
- `--` — Required separator between code-dbg options and executable/args

**Examples:**

```powershell
# Print debug URL (default)
code-dbg -- myapp.exe

# Print URL with arguments
code-dbg -- myapp.exe --verbose --config=file.conf

# Specific working directory
code-dbg --cwd=C:\workspace -- myapp.exe

# Launch VS Code immediately
code-dbg -- myapp.exe

# Launch VS Code Insiders immediately
code-dbg --insiders -- myapp.exe

# Insiders wrapper
code-dbg-insiders -- myapp.exe

# With options and arguments starting with --
code-dbg --cwd=/tmp -- ./app.exe -- --my-flag
```

**Requirements:**

1. Must use `--` separator before the executable path
2. Must have a folder open in VS Code (File → Open Folder)
3. Executable must exist and be accessible
4. Appropriate debugger must be installed:
   - Windows: MSVC debugger (Visual Studio or Build Tools)
   - (No other platform tested at the moment)

## Build and Install from Source

### Prerequisites

- Node.js 14+ (https://nodejs.org/)
- Python 3.6+ (https://www.python.org/)
- VS Code 1.85+ (https://code.visualstudio.com/)

### Windows

```powershell
.\scripts\build.ps1
```

**This script:**

- Installs npm dependencies
- Compiles TypeScript to JavaScript
- Packages the extension as a `.vsix` file

**Windows only:**

- Generates and updates [src/version.json](src/version.json)
- Bumps extension version before packaging

Output: `code-dbg-X.X.X.vsix`

## Test

Run the automated test suite:

```powershell
.\scripts\test.ps1
```

This will:

- Build the extension
- Compile the test app
- Launch VS Code with the debugger
- Verify arguments are received correctly
- Check that debug session completes successfully
- Validate the payload, executable, and debugger start

**For manual debugging/inspection:**

```powershell
.\scripts\test.ps1 -Interactive
```

This keeps VS Code open after the test completes so you can inspect the debugger, output, and logs yourself.

**Skip the build (use existing binaries):**

```powershell
.\scripts\test.ps1 -NoBuild
```

## Publish

### Marketplace (VSCE)

1. Login with your publisher account:

```powershell
vsce login bradphelan
```

2. Publish the extension:

```powershell
vsce publish
```

**Optional:**

- Publish a specific version (matches `package.json`):

```powershell
vsce publish 0.1.32
```

- Bump and publish a version:

```powershell
vsce publish patch
```

### Manual Installation (Development)

### Step 1: Install the Extension

After building, install the `.vsix` file:

```powershell
code --install-extension code-dbg-X.X.X.vsix
```

Or open the VSIX directly in VS Code:

- Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
- Type "Extensions: Install from VSIX"
- Select the `.vsix` file

### Step 2: Install the CLI Script

**Windows:**

```powershell
.\scripts\install.ps1
```

This copies the `code-dbg` script to your PATH, adds the `code-dbg-insiders` wrapper,
and installs the VSIX into VS Code and VS Code Insiders when their CLI commands are available.

### Step 3: Verify Installation

```powershell
code-dbg --help
```

You should see the usage information.

## How It Works

```
Terminal: code-dbg -- myapp.exe arg1 arg2
         ↓
Python script parses args (requires -- separator)
         ↓
Constructs debug payload (exe, args, cwd)
         ↓
Base64-encodes payload into VS Code URL
         ↓
Prints URL: vscode://bradphelan.code-dbg/launch?payload=...
         ↓
Invokes: code --open-url <URL>
         ↓
VS Code Extension receives URL
         ↓
Parses and validates payload
         ↓
Selects debugger by platform (MSVC/GDB/LLDB)
         ↓
Creates debug configuration
         ↓
Launches debugger via VS Code Debug API
         ↓
Session starts and auto-continues after activation
```

## Project Structure

```
├── src/extension.ts              # VS Code extension
├── src/version.json              # Generated version info (Windows build)
├── app/code-dbg.py               # Python CLI tool (runtime)
├── scripts/build.ps1             # Build script (Windows)
├── scripts/build-test-exe.ps1    # Test app build helper
├── scripts/install.ps1           # Install script (Windows)
├── scripts/test.ps1              # Automated test
├── scripts/generate-version.ps1  # Version file generator (Windows)
├── test-app/hello.cpp            # Test application
├── test-app/build/               # Test app output
├── package.json                  # Extension manifest
├── package-lock.json             # NPM lockfile
├── out/                          # Compiled extension output
└── code-dbg-*.vsix               # Packaged extension output
```

## License

MIT
