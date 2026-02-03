# Agent Guidelines for code-dbg Development

## Code Changes & Testing

**All code changes must be followed by running the test script.**

After modifying any of the following files:

- `app/code-dbg.py` (CLI tool)
- `src/extension.ts` (VS Code extension)
- `test-app/hello.cpp` (test application)
- `scripts/*.ps1` (build/install scripts)

**You must run the test suite to verify nothing broke:**

```powershell
.\scripts\test.ps1
```

If the test fails, the change is incomplete and must be fixed before committing.

**For interactive debugging/inspection:**

```powershell
.\scripts\test.ps1 -Interactive
```

This keeps VS Code open so you can manually verify the behavior.

## Documentation

**README.md must always be kept up to date with code changes.**

When you modify:

- Command-line arguments (`code-dbg.py`)
- Default behaviors
- Usage patterns
- Installation or build procedures

You **must** update the corresponding sections in `README.md`:

- Usage examples
- Options and flags
- How It Works diagram
- Troubleshooting section
- Architecture section (if applicable)

**Do not leave documentation stale** – it should reflect the actual behavior of the code.

## Workflow

1. Make code changes
2. Update `README.md` to match the new behavior
3. Run `.\scripts\test.ps1` to verify everything works
4. Only then consider the task complete

Example:

```
✗ Change argv parsing in code-dbg.py
✓ Update README.md usage examples
✓ Run test.ps1 (passes)
✓ Commit
```

## Key Files to Watch

- `app/code-dbg.py` – CLI tool, entry point for users
- `src/extension.ts` – VS Code extension logic
- `README.md` – User documentation, must stay synchronized
- `scripts/test.ps1` – E2E test, your verification tool
