#!/usr/bin/env python3
"""
code-dbg: Launch VS Code debugger from terminal without launch.json

Usage:
    code-dbg [OPTIONS] -- <exe-path> [arg1] [arg2] ... [argN]

Options:
    --cwd=<dir>      Working directory (defaults to current directory)
    --insiders       Use VS Code Insiders URL scheme and launcher
    --               Stop parsing options; everything after is: exe + args

Examples:
    code-dbg -- ./myapp.exe --verbose --config=file.conf
    code-dbg --cwd=/path/to/wd -- /usr/local/bin/myapp arg1 arg2
    code-dbg -- ./app.exe -- --my-flag
    code-dbg --cwd=/tmp -- /usr/local/bin/myapp
    code-dbg --insiders -- ./app.exe
    code-dbg-insiders -- ./app.exe

Note: Use -- to separate code-dbg options from the executable and its arguments.
      This is required if your executable takes arguments starting with --
"""

import sys
import os
import json
import base64
import subprocess
import argparse
import webbrowser
from pathlib import Path


def main():
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
        '--insiders',
        action='store_true',
        help='Use VS Code Insiders URL scheme and launcher'
    )

    parser.add_argument(
        '--url-only',
        action='store_true',
        help='Only generate and print the URL, do not launch VS Code'
    )

    args = parser.parse_args()

    # Get current working directory
    cwd = args.cwd or os.getcwd()
    cwd = os.path.abspath(cwd)

    # Normalize exe path
    exe_path = args.exe
    exe_path = os.path.abspath(exe_path) if os.path.isabs(exe_path) else exe_path

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

    # Encode payload as base64
    payload_json = json.dumps(payload)
    payload_base64 = base64.b64encode(payload_json.encode()).decode()

    # Construct VS Code URL
    scheme = 'vscode-insiders' if args.insiders else 'vscode'
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
            command = 'code-insiders' if args.insiders else 'code'
            subprocess.run([command, '--open-url', url], check=True)
        else:
            # Linux and other Unix-like systems
            command = 'code-insiders' if args.insiders else 'code'
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
