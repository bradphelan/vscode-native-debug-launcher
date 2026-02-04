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
4. Commit using conventional commit format (see below)
5. Only then consider the task complete

Example:

```
✗ Change argv parsing in code-dbg.py
✓ Update README.md usage examples
✓ Run test.ps1 (passes)
✓ Commit with: "feat: Add support for custom debugger flags"
```

## Commit Messages

**All commits must use conventional commit format** for automatic changelog generation.

Use these prefixes:

- `feat:` – New features or capabilities
- `fix:` – Bug fixes
- `docs:` – Documentation-only changes
- `chore:` – Maintenance, dependencies, build scripts
- `refactor:` – Code restructuring without behavior changes
- `perf:` – Performance improvements
- `test:` – Test additions or modifications

Examples:

```
feat: Add support for launching with custom arguments
fix: Resolve URI encoding issue with spaces in paths
docs: Update installation instructions for PowerShell 7
chore: Bump version to 0.1.34
refactor: Extract debugger launch logic into separate function
```

The changelog generation script (`.\scripts\generate-changelog.ps1`) automatically categorizes commits based on these prefixes.

## Building and Releasing

### Development Builds

For testing and development, use:

```powershell
.\scripts\build.ps1 -Dev
```

This:
- Bumps the patch version (0.1.37 → 0.1.38)
- Generates CHANGELOG.md from commits
- Compiles TypeScript
- Packages VSIX file
- **Does NOT** create git tags or commit

Use this for:
- Local testing before committing changes
- CI/CD pipelines
- Pre-release verification

### Release Builds

When ready to publish a new version:

```powershell
.\scripts\build.ps1 -Release
```

This performs pre-flight checks, then:
- Bumps the patch version
- Generates CHANGELOG.md
- Compiles TypeScript
- **Commits** version bump + changelog with message: `chore: bump version to X.X.X and update changelog`
- **Creates git tag** (annotated): `v0.1.37`
- **Pushes tag** to origin remote
- Packages VSIX file

Requirements:
- Working directory must be clean (no uncommitted changes)
- Git must be configured (`user.name`, `user.email`)
- Remote `origin` must be configured
- You must have push permissions

Example release workflow:

```powershell
# 1. Make changes and commit normally with conventional prefixes
git commit -m "feat: Add new debug feature"
git commit -m "fix: Resolve race condition"

# 2. Build and release
.\scripts\build.ps1 -Release

# 3. Publish to VS Code marketplace
vsce publish
```

After release, the tag is pushed to GitHub and CHANGELOG.md reflects only commits since the previous release.

## Key Files to Watch

- `app/code-dbg.py` – CLI tool, entry point for users
- `src/extension.ts` – VS Code extension logic
- `README.md` – User documentation, must stay synchronized
- `scripts/test.ps1` – E2E test, your verification tool
