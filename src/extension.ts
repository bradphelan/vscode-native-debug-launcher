import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import * as os from "os";
import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

interface DebugPayload {
  exe: string;
  args: string[];
  cwd: string;
}

let outputChannel: vscode.OutputChannel;
let logFilePath: string | null = null;
let isTestMode = false;

function initializeLogging() {
  // Create output channel
  outputChannel = vscode.window.createOutputChannel("Code DBG");

  // Check if we're in test mode
  isTestMode = process.env.VSCODE_DEBUGGER_TEST_MODE === "1";

  if (isTestMode && vscode.workspace.workspaceFolders?.length) {
    const wsFolder = vscode.workspace.workspaceFolders[0].uri.fsPath;
    logFilePath = path.join(wsFolder, "code-dbg.log");
  }
}

function log(message: string) {
  const timestamp = new Date().toISOString().split("T")[1].split(".")[0];
  const formattedMsg = `[${timestamp}] ${message}`;

  // Always log to output channel
  outputChannel.appendLine(formattedMsg);

  // Also log to file in test mode
  if (isTestMode && logFilePath) {
    try {
      fs.appendFileSync(logFilePath, formattedMsg + "\n");
    } catch (e) {
      // Silently fail if we can't write to file
    }
  }

  // Also log to console for debugging
  console.log(formattedMsg);
}

function logError(message: string, error?: Error) {
  log(`❌ ERROR: ${message}`);
  if (error) {
    log(`   ${error.message}`);
    if (error.stack) {
      const lines = error.stack.split("\n");
      lines.slice(0, 5).forEach((line) => log(`   ${line}`));
    }
  }
}

export async function activate(context: vscode.ExtensionContext) {
  // Initialize logging first
  initializeLogging();

  // Show the output channel
  outputChannel.show();

  log("════════════════════════════════════════════════════════════");
  log("🚀 Code DBG Extension ACTIVATING");
  log("════════════════════════════════════════════════════════════");

  // Load and log version info if available
  let buildVersion = "0.1.0";
  let buildHash = "unknown";
  let buildBranch = "unknown";
  let buildTimestamp = "unknown";

  try {
    const versionPath = path.join(context.extensionPath, "src", "version.json");
    if (fs.existsSync(versionPath)) {
      const versionData = JSON.parse(fs.readFileSync(versionPath, "utf-8"));
      buildVersion = versionData.version || buildVersion;
      buildHash = versionData.build || buildHash;
      buildBranch = versionData.branch || buildBranch;
      buildTimestamp = versionData.timestamp || buildTimestamp;
    }
  } catch (e) {
    // Silently ignore if version.json doesn't exist yet
  }

  log(`📋 Extension version: ${buildVersion}`);
  log(`🔨 Build: ${buildHash} (${buildBranch})`);
  log(`⏰ Built: ${buildTimestamp}`);
  log(`🖥️  Platform: ${process.platform}`);
  log(`⚙️  Node: ${process.version}`);
  log(`🧪 Test mode: ${isTestMode ? "YES" : "NO"}`);
  if (logFilePath) {
    log(`📁 Log file: ${logFilePath}`);
  }

  // Register URL handler
  log("\n🔗 Registering URL handler for: vscode://bradphelan.code-dbg");
  log("   (also vscode-insiders://bradphelan.code-dbg)");
  const disposable = vscode.window.registerUriHandler({
    handleUri: async (uri: vscode.Uri) => {
      log("\n" + "═".repeat(60));
      log("🎯 URL HANDLER TRIGGERED!");
      log(`📍 Full URI: ${uri.toString()}`);
      log(`📍 Authority: ${uri.authority}`);
      log(`📍 Path: ${uri.path}`);
      log(`📍 Query length: ${uri.query.length} bytes`);

      try {
        await handleDebugUri(uri);
        log("✅ URL handler completed successfully");
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        logError("Debug launch failed", error as Error);
        vscode.window.showErrorMessage(`Debug launch failed: ${errorMsg}`);
      }
      log("═".repeat(60) + "\n");
    },
  });

  context.subscriptions.push(disposable);

  // Register command for testing
  log("📌 Registering command: extension.debugLaunch");
  const cmdDisposable = vscode.commands.registerCommand(
    "extension.debugLaunch",
    async () => {
      log("🎬 Test command executed");
      vscode.window.showInformationMessage("Code DBG Ready");
    },
  );

  context.subscriptions.push(cmdDisposable);

  // Register CLI install commands
  const installCliCmd = vscode.commands.registerCommand(
    "code-dbg.installCli",
    async () => {
      await installCliCommand(context);
    },
  );
  context.subscriptions.push(installCliCmd);

  const checkCliStatusCmd = vscode.commands.registerCommand(
    "code-dbg.checkCliStatus",
    async () => {
      await checkCliStatusCommand(context);
    },
  );
  context.subscriptions.push(checkCliStatusCmd);

  // Auto-install or upgrade CLI
  await autoInstallOrUpgradeCli(context);

  log("\n✅ Extension activated successfully");
  log("✅ URL handler is registered and ready");
  log("ℹ️  Registered for: vscode://bradphelan.code-dbg/*");
  log("ℹ️  Also registered: vscode-insiders://bradphelan.code-dbg/*");
  log("⏳ Waiting for URL invocations...");
  log("════════════════════════════════════════════════════════════\n");
}

async function handleDebugUri(uri: vscode.Uri): Promise<void> {
  log("\n📋 handleDebugUri() called");

  // Check if workspace is open
  log(
    `📂 Checking workspace: ${vscode.workspace.workspaceFolders?.length ?? 0} folders open`,
  );
  if (
    !vscode.workspace.workspaceFolders ||
    vscode.workspace.workspaceFolders.length === 0
  ) {
    const msg =
      "No workspace folder is open. Please open a workspace before launching the debugger.";
    logError(msg);
    throw new Error(msg);
  }
  log(`✅ Workspace OK: ${vscode.workspace.workspaceFolders[0].uri.fsPath}`);

  // Parse URL parameters
  log("🔍 Parsing URL parameters");
  const params = new URLSearchParams(uri.query);
  const payload64 = params.get("payload");

  if (!payload64) {
    logError("Invalid debug URL: missing payload parameter");
    throw new Error("Invalid debug URL: missing payload parameter");
  }
  log(`✅ Payload found (${payload64.length} base64 chars)`);
  log(`   First 60 chars: ${payload64.substring(0, 60)}...`);

  // Decode base64 payload
  let payload: DebugPayload;
  try {
    log("🔐 Decoding base64 payload");
    const decodedJson = Buffer.from(payload64, "base64").toString("utf-8");
    log(`✅ Decoded JSON: ${decodedJson}`);
    payload = JSON.parse(decodedJson);
    log(`✅ Parsed payload successfully:`);
    log(`     exe: ${payload.exe}`);
    log(`     args: [${payload.args.join(", ")}]`);
    log(`     cwd: ${payload.cwd}`);
  } catch (error) {
    logError("Failed to decode debug payload", error as Error);
    throw new Error(`Failed to decode debug payload: ${error}`);
  }

  // Validate payload
  log("✔️  Validating payload structure");
  if (!payload.exe || !Array.isArray(payload.args) || !payload.cwd) {
    logError("Invalid payload: missing required fields");
    throw new Error("Invalid payload: missing exe, args, or cwd");
  }
  log("✅ Payload validation passed");

  // Resolve exe path (relative or absolute)
  log("📍 Resolving executable path");
  const exePath = path.isAbsolute(payload.exe)
    ? payload.exe
    : path.join(payload.cwd, payload.exe);
  log(`✅ Resolved exe path: ${exePath}`);

  // Verify executable exists
  log("🔎 Checking if executable exists");
  if (!fs.existsSync(exePath)) {
    logError(`Executable not found: ${exePath}`);
    throw new Error(`Executable not found: ${exePath}`);
  }
  log("✅ Executable found");
  const stats = fs.statSync(exePath);
  log(`   Size: ${stats.size} bytes`);

  // Detect debugger based on platform and exe extension
  log("🔧 Detecting debugger");
  const debugger_ = detectDebugger(exePath);
  log(`✅ Detected debugger: ${debugger_}`);

  // Create debug configuration
  log("⚙️  Creating debug configuration");
  const config: vscode.DebugConfiguration = {
    name: `Debug ${path.basename(exePath)}`,
    type: debugger_,
    request: "launch",
    program: exePath,
    args: payload.args,
    cwd: payload.cwd,
    stopAtEntry: false,
  };
  log(`✅ Base config created`);
  log(`   name: ${config.name}`);
  log(`   type: ${config.type}`);
  log(`   request: ${config.request}`);
  log(`   program: ${config.program}`);
  log(`   args: [${config.args.join(", ")}]`);
  log(`   cwd: ${config.cwd}`);

  // Add platform-specific settings
  log(`🖥️  Platform: ${process.platform}`);
  if (process.platform === "win32" && debugger_ === "cppvsdbg") {
    log("   Using MSVC debugger (cppvsdbg)");
    // Pass environment variables to the debugged process
    Object.assign(config, {
      env: {
        E2E_TEST_OUTPUT_DIR: payload.cwd,
      },
    });
    log(`   Environment: E2E_TEST_OUTPUT_DIR=${payload.cwd}`);
  } else if (debugger_ === "gdb" || debugger_ === "lldb") {
    log("   Adding GDB/LLDB-specific settings");
    Object.assign(config, {
      MIMode: debugger_,
      setupCommands: [],
      env: {
        E2E_TEST_OUTPUT_DIR: payload.cwd,
      },
    });
    log(`   Environment: E2E_TEST_OUTPUT_DIR=${payload.cwd}`);
  }

  // Get the workspace folder
  log("📂 Getting workspace folder");
  const workspaceFolder = vscode.workspace.workspaceFolders![0];
  log(`✅ Workspace folder: ${workspaceFolder.uri.fsPath}`);

  // Log the complete debug configuration
  log("\n📄 Complete Debug Configuration:");
  log(JSON.stringify(config, null, 2));

  // Start debugging
  log("\n🚀 Starting debug session...");
  const success = await vscode.debug.startDebugging(workspaceFolder, config);

  if (!success) {
    logError("Failed to start debugging session");
    throw new Error("Failed to start debugging session");
  }
  log("✅ Debug session started successfully");

  // Automatically continue execution after starting debug session
  log("⏸️  Setting up auto-continue on debug session activation");
  const disposable = vscode.debug.onDidChangeActiveDebugSession(
    (session: vscode.DebugSession | undefined) => {
      if (session) {
        log(
          `   → Debug session changed: "${session.name}" (type: ${session.type}, id: ${session.id})`,
        );
        if (session.configuration.program === exePath) {
          log(
            `   → ✅ Program matches! (${session.configuration.program} == ${exePath})`,
          );
          log("   → Waiting 500ms for debugger to fully attach...");
          setTimeout(() => {
            log("   → Sending 'continue' command to debugger");
            session.customRequest("continue", {}).then(
              () => {
                log("   → ✅ Continue command sent successfully!");
                disposable.dispose();
                log("   → Auto-continue listener disposed");
              },
              (err) => {
                logError("   → Failed to send continue command", err);
                disposable.dispose();
              },
            );
          }, 500);
        } else {
          log(
            `   → Program mismatch (${session.configuration.program} !== ${exePath}), skipping`,
          );
        }
      } else {
        log("   → Debug session cleared (session undefined)");
      }
    },
  );

  log(`✅ Now debugging: ${path.basename(exePath)} with ${debugger_}`);
  vscode.window.showInformationMessage(
    `Debugging ${path.basename(exePath)} with ${debugger_}`,
  );
}

function detectDebugger(exePath: string): string {
  const platform = process.platform;

  // Windows: Use MSVC debugger for .exe files
  if (platform === "win32") {
    return "cppvsdbg";
  }

  // macOS: Use LLDB
  if (platform === "darwin") {
    return "lldb";
  }

  // Linux: Use GDB
  if (platform === "linux") {
    return "gdb";
  }

  // Fallback
  return "gdb";
}

async function autoInstallOrUpgradeCli(
  context: vscode.ExtensionContext,
): Promise<void> {
  try {
    const packageJson = JSON.parse(
      fs.readFileSync(
        path.join(context.extensionPath, "package.json"),
        "utf-8",
      ),
    );
    const bundledVersion = packageJson.version;
    const installedVersion = context.globalState.get<string>(
      "codeDbg.installedCliVersion",
    );

    log(`\n📦 CLI Version Check:`);
    log(`   Bundled: ${bundledVersion}`);
    log(`   Installed: ${installedVersion || "none"}`);

    if (installedVersion !== bundledVersion) {
      log(`\n🔄 CLI version mismatch - installing...`);
      const result = await installCli(context);

      if (result.success) {
        await context.globalState.update(
          "codeDbg.installedCliVersion",
          bundledVersion,
        );
        await context.globalState.update("codeDbg.cliInstallAttempted", false);

        const isFirstInstall = !installedVersion;
        const message = isFirstInstall
          ? `✓ Code DBG CLI installed to ${result.installPath}. Restart your terminal to use \`code-dbg\`.`
          : `✓ Code DBG CLI updated to v${bundledVersion}. Restart your terminal.`;

        log(`✅ ${message}`);

        // Skip notifications in test mode
        if (!isTestMode) {
          const action = await vscode.window.showInformationMessage(
            message,
            "Open Terminal",
            "Show Docs",
          );

          if (action === "Open Terminal") {
            vscode.commands.executeCommand("workbench.action.terminal.new");
          } else if (action === "Show Docs") {
            vscode.env.openExternal(
              vscode.Uri.parse(
                "https://github.com/bradphelan/vscode-native-debug-launcher#readme",
              ),
            );
          }
        }
      } else {
        const alreadyAttempted = context.globalState.get<boolean>(
          "codeDbg.cliInstallAttempted",
        );
        if (!alreadyAttempted && !isTestMode) {
          log(`❌ CLI installation failed: ${result.error}`);
          const action = await vscode.window.showErrorMessage(
            `Failed to install Code DBG CLI: ${result.error}`,
            "Retry",
            "Manual Instructions",
          );

          if (action === "Retry") {
            await installCliCommand(context);
          } else if (action === "Manual Instructions") {
            vscode.env.openExternal(
              vscode.Uri.parse(
                "https://github.com/bradphelan/vscode-native-debug-launcher#install",
              ),
            );
          }

          await context.globalState.update("codeDbg.cliInstallAttempted", true);
        } else if (!alreadyAttempted) {
          log(`❌ CLI installation failed: ${result.error}`);
        }
      }
    } else {
      log(`✅ CLI is up to date (v${bundledVersion})`);
    }
  } catch (error) {
    logError("Failed to check/install CLI", error as Error);
  }
}

interface InstallResult {
  success: boolean;
  installPath?: string;
  error?: string;
}

async function installCli(
  context: vscode.ExtensionContext,
): Promise<InstallResult> {
  try {
    const platform = process.platform;
    const sourcePath = path.join(context.extensionPath, "app", "code-dbg.py");

    if (!fs.existsSync(sourcePath)) {
      return {
        success: false,
        error: "code-dbg.py not found in extension bundle",
      };
    }

    let installDir: string;
    let needsPathUpdate = false;

    if (platform === "win32") {
      // Windows: Install to AppData\code-dbg
      installDir = path.join(os.homedir(), "AppData", "Roaming", "code-dbg");
    } else {
      // macOS/Linux: Install to ~/.local/bin
      installDir = path.join(os.homedir(), ".local", "bin");
    }

    // Create install directory
    fs.mkdirSync(installDir, { recursive: true });

    // Copy Python script
    const targetPyScript = path.join(installDir, "code-dbg.py");
    fs.copyFileSync(sourcePath, targetPyScript);
    log(`✓ Copied code-dbg.py to ${installDir}`);

    if (platform === "win32") {
      // Create batch wrappers for Windows
      const batchFile = path.join(installDir, "code-dbg.bat");
      const batchContent = `@echo off\npython "%~dp0code-dbg.py" %*`;
      fs.writeFileSync(batchFile, batchContent, "ascii");
      log(`✓ Created code-dbg.bat`);

      const insidersBatchFile = path.join(installDir, "code-dbg-insiders.bat");
      const insidersBatchContent = `@echo off\npython "%~dp0code-dbg.py" --insiders %*`;
      fs.writeFileSync(insidersBatchFile, insidersBatchContent, "ascii");
      log(`✓ Created code-dbg-insiders.bat`);

      // Add to PATH if not already there
      try {
        const { stdout } = await execAsync(
          `powershell -Command "[Environment]::GetEnvironmentVariable('PATH', 'User')"`,
        );
        const userPath = stdout.trim();

        if (!userPath.includes(installDir)) {
          const newPath = userPath ? `${userPath};${installDir}` : installDir;
          // Escape quotes for PowerShell command
          const escapedPath = newPath.replace(/"/g, '""');
          await execAsync(
            `powershell -Command "[Environment]::SetEnvironmentVariable('PATH', '${escapedPath}', 'User')"`,
          );
          log(`✓ Added ${installDir} to user PATH`);
          needsPathUpdate = true;
        }
      } catch (error) {
        log(`⚠ Could not update PATH automatically: ${error}`);
      }
    } else {
      // Create shell script wrappers for Unix
      const shellScript = path.join(installDir, "code-dbg");
      const shellContent = `#!/usr/bin/env bash\npython3 "$(dirname "$0")/code-dbg.py" "$@"`;
      fs.writeFileSync(shellScript, shellContent, { mode: 0o755 });
      log(`✓ Created code-dbg shell script`);

      const insidersShellScript = path.join(installDir, "code-dbg-insiders");
      const insidersShellContent = `#!/usr/bin/env bash\npython3 "$(dirname "$0")/code-dbg.py" --insiders "$@"`;
      fs.writeFileSync(insidersShellScript, insidersShellContent, {
        mode: 0o755,
      });
      log(`✓ Created code-dbg-insiders shell script`);

      // Check if ~/.local/bin is in PATH
      const pathEnv = process.env.PATH || "";
      if (!pathEnv.includes(installDir)) {
        log(
          `⚠ ${installDir} may not be in PATH. Add it to ~/.bashrc or ~/.zshrc`,
        );
        needsPathUpdate = true;
      }
    }

    return {
      success: true,
      installPath: installDir,
    };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

async function installCliCommand(
  context: vscode.ExtensionContext,
): Promise<void> {
  await vscode.window.withProgress(
    {
      location: vscode.ProgressLocation.Notification,
      title: "Installing Code DBG CLI...",
      cancellable: false,
    },
    async () => {
      const result = await installCli(context);

      if (result.success) {
        const packageJson = JSON.parse(
          fs.readFileSync(
            path.join(context.extensionPath, "package.json"),
            "utf-8",
          ),
        );
        await context.globalState.update(
          "codeDbg.installedCliVersion",
          packageJson.version,
        );
        await context.globalState.update("codeDbg.cliInstallAttempted", false);

        vscode.window.showInformationMessage(
          `✓ Code DBG CLI installed to ${result.installPath}. Restart your terminal.`,
        );
      } else {
        vscode.window.showErrorMessage(
          `Failed to install CLI: ${result.error}`,
        );
      }
    },
  );
}

async function checkCliStatusCommand(
  context: vscode.ExtensionContext,
): Promise<void> {
  const installedVersion = context.globalState.get<string>(
    "codeDbg.installedCliVersion",
  );
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(context.extensionPath, "package.json"), "utf-8"),
  );
  const bundledVersion = packageJson.version;

  let statusMessage = "Code DBG CLI Status:\n\n";
  statusMessage += `Bundled Version: ${bundledVersion}\n`;
  statusMessage += `Installed Version: ${installedVersion || "Not installed"}\n\n`;

  // Try to find CLI in PATH
  try {
    const command =
      process.platform === "win32" ? "where code-dbg" : "which code-dbg";
    const { stdout } = await execAsync(command);
    const cliPath = stdout.trim().split("\n")[0];
    statusMessage += `✓ Found in PATH: ${cliPath}\n`;
  } catch {
    statusMessage += `✗ Not found in PATH\n`;
  }

  if (installedVersion !== bundledVersion) {
    statusMessage += "\n⚠ Version mismatch detected";
    const action = await vscode.window.showWarningMessage(
      statusMessage,
      "Reinstall",
      "Close",
    );
    if (action === "Reinstall") {
      await installCliCommand(context);
    }
  } else {
    vscode.window.showInformationMessage(statusMessage, "Close");
  }
}

export function deactivate() {
  if (outputChannel) {
    try {
      log("👋 Extension deactivating");
    } catch (e) {
      // Ignore if output channel is already disposed
    }
    outputChannel.dispose();
  }
}
