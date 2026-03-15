# Code Review Log — 2026-03-14

Full codebase review: 37 review agents (3 per file × 12 files + 1 combined for .sln), followed by 12 fix agents.

## Findings and Fixes Applied

### Program.cs
- `Marshal.SizeOf(instance)` → `Marshal.SizeOf<T>()` (obsolete API)
- `PrintResolutionOptions`: `monitorResolutions.Add`/`optionNumber++` now guarded behind null check; callers pass null when non-interactive
- `ModeMatchesFilter`: `RatioTolerance` passed as explicit parameter instead of captured from file scope
- WxN:D branch: `rdpWidth <= 0` validated before computing `rdpHeight`

### resolutions_suggester.ps1
- Embedded C# monitor detection: replaced `GetConsoleWindow`+`MonitorFromWindow` with `MonitorFromPoint(0,1)` + `MONITOR_DEFAULTTONEAREST` (matching Program.cs)
- Added `[StructLayout(LayoutKind.Sequential)]` on embedded DEVMODE and RECT structs
- `SetProcessDpiAwareness` HRESULT now checked; tolerates 0 and E_ACCESSDENIED, errors on other values
- Added `MaxRdpDimension = 8192` validation in all three `-r` format branches
- Catch block: `$_` → `$($_.Exception.Message)`, `$targetPath` → `${targetPath}` before colon

### MonitorOracle.cs
- `MonitorFromPoint(0,0)` with `MONITOR_DEFAULTTOPRIMARY` → `(0,1)` with `MONITOR_DEFAULTTONEAREST` (matching Program.cs)
- Added `CharSet = CharSet.Auto` to DEVMODE `[StructLayout]` and `EnumDisplaySettings` DllImport
- `dpiY` now captured and asserted equal to `dpiX`

### ProcessRunner.cs
- `Task.WaitAll` return value now checked; throws `InvalidOperationException` on drain timeout instead of silently returning empty strings
- Removed redundant no-arg `WaitForExit()` on normal path

### Assertions.cs
- `ComputeExpectedWinposstr`: added `Math.Max(0, x1 - winW)` clamp (matching Program.cs)
- Removed duplicate fixture constants (`FixtureAllPresent`, `FixtureNonePresent`, `FixturePartial`); now references `FixtureManager.*`
- Removed duplicate `FixturesDir`; now references `FixtureManager.FixturesDir` (changed to `internal`)
- Error-string returns in `ComputeExpectedWinposstr` → `throw new InvalidOperationException`
- `AssertContains`/`AssertNotContains` failure messages now include actual text (truncated to 200 chars)
- `AssertExitCode` failure message now includes stdout alongside stderr

### TestRunner.cs
- Dry-run `dryStdin` now provides complete stdin for two_window cases (picker selection + monitor res "1" + side "L")
- Removed dead `tsvPath` parameter from `RunTestSuite`
- `tempDir`: empty-string sentinel → `string? tempDir = null` with null check
- `CountOptionLines`: now uses regex `^\*?\d+x\d+,` to match option lines instead of counting all non-blank lines

### TestCase.cs
- Removed dead `impl` parameter from `BuildCliArgs` and both call sites
- `BuildStdin` null return for zero-file non-picker: confirmed correct (program exits before stdin when zero files)

### SyntheticMonitor.cs
- Removed dead noise entries (`2560x1440@75Hz`, `1920x1080@144Hz`) that were silently skipped by Assertions.cs guard

### release.yml
- Removed `--no-build` from Publish step (incompatible with trimmed single-file publish)
- Added `shell: bash` to Verify step (was using `test -f` without specifying bash on Windows runner)
- Split `vedantmgoyal9/winget-releaser` into separate `winget` job with `permissions: contents: read`

### resolution_suggester.sln
- Project type GUID: classic `{FAE04EC0...}` → SDK-style `{9A19103F...}`

### pairwise.pict
- Removed redundant constraint (line 24, subsumed by line 27)
- Added `RdpSettings` documentation comment
- Improved zero-file constraint comment

### ResolutionSuggesterTests.csproj
- `<ProjectReference>` attempted but reverted: NETSDK1151 prohibits non-self-contained project from referencing self-contained exe

## Lessons Learned

### ProjectReference to self-contained exe is not possible
.NET SDK error NETSDK1151 prevents a non-self-contained project from referencing a self-contained executable via `<ProjectReference>`. The test project's implicit dependency (locating the exe by convention path) is the correct design. Documented in README.md.

### picker + zero files is still non-interactive for MonitorResSel/Side
Picker only makes the RDP resolution selection interactive (the first prompt). The monitor resolution selection and side prompts only appear when file paths are provided. The original PICT constraint locking MonitorResSel/Side for all zero-file cases (including picker) was correct. Unlocking them produced test failures: program exits 0 (non-interactive success) but test expected exit code 1 (from invalid_side/invalid_selection that never runs).

## Fixes That Were Wrong

### pairwise.pict: unlocking picker+zero for MonitorResSel/Side
The review agent suggested that `picker + FileCount=zero` should allow MonitorResSel and Side to vary (since picker is interactive). This was wrong. Picker only makes the RDP resolution selection interactive. The MonitorResSel/Side prompts only appear when file paths are provided. Unlocking the constraint produced two test failures: program exits 0 (non-interactive success) but tests expected exit code 1 (from invalid_side/invalid_selection prompts that never run). Reverted to the original constraint with an improved comment.

### ResolutionSuggesterTests.csproj: adding ProjectReference
The review agent flagged the missing `<ProjectReference>` as an implicit dependency. Adding it caused NETSDK1151: a non-self-contained project cannot reference a self-contained executable. The test project's convention-based exe lookup is the correct design for this architecture. Reverted; documented in README.md instead.

## Not Fixed (by design)

### DEVMODE struct layout (Program.cs, MonitorOracle.cs)
- Fields use `int` instead of `uint` (DWORD) — coincidentally correct on x64, changing risks breaking working code
- Sequential layout instead of Explicit for the union region — same rationale
- Both patterns are established across the codebase and tests pass on the target platform

## Standards (to prevent flip-flops and invented issues)

1. Monitor detection: `GetConsoleWindow()` + `MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST)`. No `MonitorFromPoint`.
2. ProcessRunner: `process.WaitForExit()` (no-arg) after `Kill()`.
3. Test error handling: `throw`, not error-string returns.
4. `areaOne`: cap width at 100% with `Math.Min(widthUsage, 100)`, matching two-window calculation.
5. Review parity: Program.cs and resolutions_suggester.ps1 must be reviewed together. All findings in one pass.
6. PICT FileCount column: split into InputType (none, file, directory, nonexistent) and InputCount (1, 2). Constraint: `IF [InputType] <> "file" THEN [InputCount] = 1`. No string-encoded numbers.
7. One-per-line struct fields: keep. Easier to diff and review.
8. `Marshal.SizeOf<T>()` over `Marshal.SizeOf(instance)`. Use the generic form.
9. Set `devMode.dmSize` before calling `EnumDisplaySettings`.
10. No repeated code, ever. Extract even one-liners if used more than once.
11. Do not remove test noise data. Noise modes exist to verify filtering works.
12. Dry-run stdin for zero-file: `PickerSelection + "\n"` only. Zero-file runs are non-interactive for monitor res and side.
13. Assert exact exit codes. `AssertExitCode(result, 1)` not `AssertNotExitCode(result, 0)`.
14. PS1 `-r` lookahead: first `-or` clause guards bounds. No redundant bounds checks on subsequent clauses.
15. ProcessRunner normal path: `Task.WaitAll` with timeout after `WaitForExit`. Throw if streams don't drain.
16. PS1 embedded C# `GetMonitorData`: pass constants as parameters, no hardcoded duplicates.
