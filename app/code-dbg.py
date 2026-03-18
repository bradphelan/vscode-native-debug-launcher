#!/usr/bin/env python3
"""
code-dbg: Launch VS Code debugger from terminal without launch.json

Usage:
    code-dbg [OPTIONS] -- <exe-path> [arg1] [arg2] ... [argN]

Options:
    --cwd=<dir>      Working directory (defaults to current directory)
    --url-only       Only print the debug URL, do not launch VS Code
    --               Stop parsing options; everything after is: exe + args

Examples:
    code-dbg -- ./myapp.exe --verbose --config=file.conf
    code-dbg --cwd=/path/to/wd -- /usr/local/bin/myapp arg1 arg2
    code-dbg -- ./app.exe -- --my-flag
    code-dbg --cwd=/tmp -- /usr/local/bin/myapp
    code-dbg --url-only -- ./app.exe

Note: Use -- to separate code-dbg options from the executable and its arguments.
      This is required if your executable takes arguments starting with --

      The script automatically detects if running in VS Code Insiders by checking
      environment variables. Works seamlessly in both Insiders and Stable versions.
"""

import sys
import os
import json
import base64
import subprocess
import argparse
import webbrowser
from pathlib import Path


def detect_vscode_version():
    """Auto-detect if running in VS Code Insiders by checking environment variables.

    Returns True if running in VS Code Insiders, False otherwise (including when not in VS Code).
    """
    # First, check if we're even running inside VS Code
    if 'VSCODE_INJECTION' not in os.environ:
        return False

    # Fallback: Check VSCODE-related environment variables for "Insiders"
    for key, value in os.environ.items():
        if key.startswith('VSCODE_') and value and 'Insiders' in value:
            return True

    # Also check other common VS Code env vars
    for key in ['GIT_ASKPASS', 'BUNDLED_DEBUGPY_PATH', 'PYTHONSTARTUP']:
        value = os.environ.get(key, '')
        if value and 'Insiders' in value:
            return True

    return False


def find_natvis_upward(exe_path, cwd):
    """Find a single .natvis file by searching upward from the executable directory.

    Returns the absolute natvis path if found, or None if no natvis is discovered.
    Raises ValueError if more than one .natvis file exists in the same directory.
    """
    exe_abs = exe_path if os.path.isabs(exe_path) else os.path.abspath(os.path.join(cwd, exe_path))
    search_dir = Path(exe_abs).parent.resolve()

    while True:
        matches = sorted(
            [candidate for candidate in search_dir.iterdir() if candidate.is_file() and candidate.suffix.lower() == ".natvis"],
            key=lambda item: item.name.lower(),
        )

        if len(matches) == 1:
            return str(matches[0])

        if len(matches) > 1:
            names = ", ".join(item.name for item in matches)
            raise ValueError(
                f"Multiple .natvis files found in '{search_dir}': {names}. "
                "Pass exactly one file with --natvis."
            )

        parent = search_dir.parent
        if parent == search_dir:
            return None
        search_dir = parent


def main():
    # Allow URL generation outside VS Code for tests/automation, but require VS Code for launching.
    url_only_requested = '--url-only' in sys.argv[1:]
    if 'VSCODE_INJECTION' not in os.environ and not url_only_requested:
        print("Error: code-dbg must be run from a terminal inside VS Code.", file=sys.stderr)
        print("This tool is designed to launch the VS Code debugger from within VS Code's integrated terminal.", file=sys.stderr)
        print("Tip: Use --url-only for automation outside VS Code.", file=sys.stderr)
        sys.exit(1)

    # Require -- separator to clearly separate options from exe/args
    if '--' not in sys.argv[1:]:
        print("Error: Missing '--' separator", file=sys.stderr)
        print("Usage: code-dbg [OPTIONS] -- <exe> [exe-args...]", file=sys.stderr)
        print("Example: code-dbg --cwd=/tmp -- ./app.exe arg1 arg2", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description='Launch VS Code debugger from terminal',
        prog='code-dbg',
        usage='%(prog)s [OPTIONS] -- <exe> [exe-args...]'
    )

    parser.add_argument(
        'exe',
        help='Path to executable to debug (relative or absolute)'
    )

    parser.add_argument(
        'args',
        nargs='*',
        help='Arguments to pass to the executable'
    )

    parser.add_argument(
        '--cwd',
        default=None,
        help='Working directory for the process (defaults to current directory)'
    )

    parser.add_argument(
        '--url-only',
        action='store_true',
        help='Only generate and print the URL, do not launch VS Code'
    )

    parser.add_argument(
        '--natvis',
        default=None,
        help='Path to a single .natvis file. If omitted, code-dbg searches upward from executable directory.'
    )

    args = parser.parse_args()

    # Auto-detect Insiders version from environment
    use_insiders = detect_vscode_version()

    # Get current working directory
    cwd = args.cwd or os.getcwd()
    cwd = os.path.abspath(cwd)

    # Normalize exe path
    exe_path = args.exe
    exe_path = os.path.abspath(exe_path) if os.path.isabs(exe_path) else exe_path

    # Resolve natvis file
    natvis_path = None
    if args.natvis:
        natvis_candidate = args.natvis
        natvis_abs = natvis_candidate if os.path.isabs(natvis_candidate) else os.path.abspath(os.path.join(cwd, natvis_candidate))
        if not os.path.exists(natvis_abs):
            print(f"Error: Natvis file not found: {natvis_abs}", file=sys.stderr)
            sys.exit(1)
        if not natvis_abs.lower().endswith('.natvis'):
            print(f"Error: Natvis file must end with .natvis: {natvis_abs}", file=sys.stderr)
            sys.exit(1)
        natvis_path = natvis_abs
    else:
        try:
            natvis_path = find_natvis_upward(exe_path, cwd)
        except ValueError as error:
            print(f"Error: {error}", file=sys.stderr)
            sys.exit(1)

    # Verify executable exists (if absolute path)
    if os.path.isabs(exe_path) and not os.path.exists(exe_path):
        print(f"Error: Executable not found: {exe_path}", file=sys.stderr)
        sys.exit(1)

    # Create debug payload
    payload = {
        'exe': exe_path,
        'args': args.args,
        'cwd': cwd
    }
    if natvis_path:
        payload['natvis'] = natvis_path

    # Encode payload as base64
    payload_json = json.dumps(payload)
    payload_base64 = base64.b64encode(payload_json.encode()).decode()

    # Construct VS Code URL
    scheme = 'vscode-insiders' if use_insiders else 'vscode'
    url = f"{scheme}://bradphelan.code-dbg/launch?payload={payload_base64}"

    # Print the URL (for logging/debugging, and for test automation)
    print(url)

    # If --url-only flag is set, just print the URL and exit
    if args.url_only:
        sys.exit(0)

    # Launch VS Code with the URL
    try:
        if sys.platform == 'win32':
            # Windows: Use webbrowser module which handles URL encoding properly
            webbrowser.open(url)
        elif sys.platform == 'darwin':
            # macOS: Use 'code' or 'code-insiders' command
            command = 'code-insiders' if use_insiders else 'code'
            subprocess.run([command, '--open-url', url], check=True)
        else:
            # Linux and other Unix-like systems
            command = 'code-insiders' if use_insiders else 'code'
            subprocess.run([command, '--open-url', url], check=True)

        print(f"Launching debugger for: {os.path.basename(exe_path)}")
    except FileNotFoundError:
        print("Error: VS Code executable not found in PATH.", file=sys.stderr)
        print("Please ensure VS Code is installed and the proper command is available.", file=sys.stderr)
        print("\nYou can manually open this URL in VS Code:", file=sys.stderr)
        print(url, file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to launch VS Code: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
