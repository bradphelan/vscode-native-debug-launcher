@echo off
REM code-dbg.bat - Wrapper for code-dbg.py
REM Launches VS Code debugger from terminal without launch.json

setlocal enabledelayedexpansion

REM Get the directory where this batch file is located
set SCRIPT_DIR=%~dp0

REM Call Python with the script and pass all arguments through
py "%SCRIPT_DIR%code-dbg.py" %*

REM Exit with the same error code as Python
exit /b %ERRORLEVEL%
