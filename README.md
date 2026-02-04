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
2. The `code-dbg` CLI is **automatically available** in any terminal opened within VS Code
3. No separate installation step needed—just open a terminal in VS Code and use `code-dbg`

The extension automatically:

- Bundles the CLI script in the extension's `app/` directory
- Makes it available via VS Code's `environmentVariableCollection` API
- Applies the PATH update only to VS Code terminals (not the system PATH)
- Works immediately when you activate the extension

### From Source

See the [Build and Install](#build-and-install-from-source) section below for building from source code.

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

## Development

### Setup

1. **Clone and install dependencies:**

```powershell
npm install
```

2. **Python is included** in the extension bundle:

The CLI (`app/code-dbg.py`) is a Python script bundled with the extension. No separate installation needed.

### Development Workflow

**Build with pre-release versioning:**

```powershell
.\scripts\build.ps1 -Dev
```

This creates a `.vsix` file with a pre-release version number like `0.1.42-dev.20260204.750` in `src/version.json`, while keeping `package.json` unchanged. This allows development builds to coexist with release versions.

**Build for release:**

```powershell
.\scripts\build.ps1
```

This increments the patch version in `package.json` and generates the final version number for the `.vsix` package.

**Run tests during development:**

```powershell
.\scripts\test.ps1
```

Tests automatically build the extension and test app, launch VS Code with the debugger, and validate the complete flow.

### Key Architecture

**CLI: `app/code-dbg.py`**

Python script bundled with the extension. Takes executable and arguments, constructs a base64-encoded debug payload, and launches VS Code with a custom URL scheme:

```
vscode://bradphelan.code-dbg/launch?payload={base64_json}
```

**Extension: `src/extension.ts`**

VS Code extension that:

- Adds the bundled `app/` directory to PATH via `environmentVariableCollection` (VS Code terminals only)
- Registers the `vscode://bradphelan.code-dbg/` URL handler
- Listens for launch requests via `vscode.window.registerUriHandler()`
- Parses and validates the payload
- Selects the appropriate debugger (cppvsdbg on Windows)
- Creates a debug configuration and launches the debug session

**Version Generation: `scripts/generate-version.ps1`**

Generates semantic versioning with pre-release suffixes for development builds:

- Dev mode (`-Dev` flag): Appends `-dev.{YYYYMMDD}.{NNN}` to version, skips updating `package.json`
- Release mode (no flag): Increments patch version in `package.json` and generates final version number

### Debugging the Extension

1. **In VS Code:**

```powershell
code .
```

2. **Press `F5`** to start the extension in debug mode (launches a new VS Code window)

3. **Set breakpoints** in `src/extension.ts` and they'll trigger in the debug instance

4. **Test the CLI:**

```powershell
.\app\code-dbg.bat -- cmd.exe /c "echo Hello"
```

Or from any VS Code terminal:

```powershell
code-dbg -- cmd.exe /c "echo Hello"
```

This prints the debug URL and launches VS Code with the debugger attached.

### Project Structure Reference

| File                           | Purpose                                      |
| ------------------------------ | -------------------------------------------- |
| `src/extension.ts`             | Main VS Code extension code                  |
| `src/version.json`             | Generated version info (Windows build only)  |
| `app/code-dbg.py`              | Python CLI tool (bundled in extension)       |
| `scripts/build.ps1`            | Main build script                            |
| `scripts/generate-version.ps1` | Semantic versioning with pre-release support |
| `scripts/install.ps1`          | Extension installation script                |
| `scripts/test.ps1`             | Automated test suite                         |
| `scripts/build-test-exe.ps1`   | Helper to compile test application           |
| `test-app/hello.cpp`           | Simple C++ test application                  |
| `package.json`                 | Extension manifest and dependencies          |
| `tsconfig.json`                | TypeScript compiler configuration            |

### PATH Management

The extension uses VS Code's `environmentVariableCollection` API to add the bundled `app/` directory to the PATH:

```typescript
const envCollection = context.environmentVariableCollection;
if (!existingPath || !existingPath.value.includes(appDir)) {
  envCollection.append("PATH", `;${appDir}`);
}
```

**Important:** The `code-dbg` command is **only available in terminals opened within VS Code**. It does not modify your system PATH, keeping your environment clean. External terminal windows won't have access to `code-dbg`.

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

**Build the extension:**

```powershell
.\scripts\build.ps1 -Dev
```

**Install to VS Code:**

```powershell
.\scripts\install.ps1 -Code
```

**Verify it works:**

1. Reopen VS Code: `code .`
2. Open a terminal inside VS Code (Terminal → New Terminal)
3. Run: `code-dbg --help`

The `code-dbg` command should be available immediately in the new terminal.

## How It Works

```
Terminal (in VS Code): code-dbg -- myapp.exe arg1 arg2
         ↓
CLI (app/code-dbg.py) parses args (requires -- separator)
         ↓
Constructs debug payload (exe, args, cwd) as base64 JSON
         ↓
Invokes: code --open-url vscode://bradphelan.code-dbg/launch?payload=...
         ↓
VS Code Extension receives URL via registerUriHandler
         ↓
Parses and validates payload
         ↓
Selects debugger by platform (MSVC on Windows, GDB/LLDB on Unix)
         ↓
Creates debug configuration and validates executable
         ↓
Launches debugger session via vscode.debug.startDebugging()
         ↓
Auto-continues execution after debugger attaches
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
