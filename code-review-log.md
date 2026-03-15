## Standards (to prevent flip-flops)

1. Monitor detection in PS1: `GetConsoleWindow()` + `MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST)`. No `MonitorFromPoint` in production code.
2. ProcessRunner: `process.WaitForExit()` (no-arg) after `Kill()`.
3. Test error handling: `throw`, not error-string returns.
4. Area percentage: `Math.Round` for computation, capped at 100% with `Math.Min(widthUsage, 100)`. Applies to PS1 and test assertions.
5. PICT FileCount column: split into InputType (none, file, directory, nonexistent) and InputCount (1, 2). Constraint: `IF [InputType] <> "file" THEN [InputCount] = 1`. No string-encoded numbers.
6. One-per-line struct fields: keep. Easier to diff and review.
7. `Marshal.SizeOf<T>()` over `Marshal.SizeOf(instance)`. Use the generic form.
8. Set `devMode.dmSize` before calling `EnumDisplaySettings`.
9. No repeated code, ever. Extract even one-liners if used more than once.
10. Do not remove test noise data. Noise modes exist to verify filtering works.
11. Dry-run stdin for zero-file: `PickerSelection + "\n"` only. Zero-file runs are non-interactive for monitor res and side.
12. Assert exact exit codes. `AssertExitCode(result, 1)` not `AssertNotExitCode(result, 0)`.
13. PS1 `-r` lookahead: first `-or` clause guards bounds. No redundant bounds checks on subsequent clauses.
14. ProcessRunner normal path: `Task.WaitAll` with timeout after `WaitForExit`. Throw if streams don't drain.
15. PS1 embedded C# `GetMonitorData`: pass constants as parameters, no hardcoded duplicates.
16. release.yml: separate "Build" and "Test" YAML steps. Each step gets its own pass/fail in the GitHub Actions UI.
17. DEVMODE fields: `uint` to match Windows SDK `DWORD` typedef. Explicit `(int)` casts at usage sites. Applies to MonitorOracle.cs and PS1 embedded C#.
18. CountOptionLines: regex `^\*?\d+x\d+,` for line counting, `Split(new[] { "\r\n", "\n" }, ...)` for line splitting, `Trim()` (not `TrimStart()`) for section-end detection.
19. Assertion failure messages: verbose. Include stdout, stderr, and excerpts. CI failures must be diagnosable without re-running locally.
20. SyntheticMonitor `TestMonitorArg`: computed property derived from Width/Height/Frequency/Dpi fields. No literal string duplication.
21. ProcessRunner: both stdout and stderr read async via `Task.Run`. Synchronous reads deadlock.
22. ProcessRunner timeout message: include stdout and stderr. Consistent with standard #19.

## Last version (progressive improvements)

23. README SetProcessDpiAwareness description: "with PROCESS_PER_MONITOR_DPI_AWARE to enable per-monitor DPI awareness".
24. README `-r` flag description: three formats WxH, W, WxN:D.
25. README aspect ratio tolerance wording: "same aspect ratio (ratio difference < 0.001)".
26. README zoom cap wording: "capped at the maximum zoom level, currently 2".
27. README build output path: "Produces publish\resolution_suggester.exe (pass -o publish as shown above).".
28. README winget PR timing: specific PR references and measured durations.
29. TestCase.cs BuildCliArgs: no `impl` parameter.
30. pairwise.pict comment ordering: merged comment blocks for file selection and nonexistent file.
31. PS1 embedded C# Marshal.SizeOf uses generic form `Marshal.SizeOf<T>()`.
32. PS1 embedded C# GetMonitorData receives `ratio_tolerance` as a parameter; no hardcoded `RatioTolerance` constant.
33. PS1 display loops extracted into `Write-ResolutionOptions` function.
34. PS1 dead code `if ($currentRatio -eq 0)` removed (unreachable).
35. README header line field order: "aspect ratio, refresh rate, DPI scale".
36. README build command includes `-o publish`.
37. README smart sizing description: "disabled — the remote desktop renders at native resolution without scaling".
38. README MonitorFromPoint description corrected to GetConsoleWindow + MonitorFromWindow.
39. release.yml tag validation moved to first step after checkout.
40. release.yml tag regex has end anchor `$`.
41. PS1 zoom/area computation duplication between test-monitor path and embedded C# is intentional (documented).
42. README workflow description lists six steps: validate tag, build, test, publish+verify, create release, submit to winget.
43. README intro "zoom levels up to 2x" matches MaxZoom = 2.
44. PS1 `Get-FilteredModes` assigns `$modeFreq = $modeEntry.Frequency` inside the foreach loop.
45. PS1 `-r` picker lookahead conforms to standard #13: first `-or` clause guards bounds, subsequent clauses have no redundant bounds checks.
46. PS1 winposstr display clamps `x0` with `[Math]::Max(0, ...)`, matching the interactive path.
47. PS1 menu input extracted into `Read-MenuChoice` helper (prompt, min, max). Three call sites: RDP resolution picker, monitor resolution selection, RDP file selection.
48. README sample output area percentage for 1920x1080 at 100% zoom: 25% (matches `Math.Round` computation).
49. README PS1 file size: ~29KB.
50. release.yml Publish step uses `--no-build` to reuse Build step output.
51. Terminology rename: "scenario" → "monitor resolution"/"option" in output text. `--resolution` → `--rdp-resolution` flag name.
52. StructLayout(LayoutKind.Sequential) on RECT, POINT, and interop structs in MonitorOracle.cs and PS1 embedded C#.
53. SetProcessDpiAwareness HRESULT check: ignore E_ACCESSDENIED (0x80070005), error on other non-zero. MonitorOracle.cs and PS1.
54. GetDpiForMonitor HRESULT check: error on non-zero.
55. `[Console]::In.ReadLine()` null guard before `.Trim()`. Exit 1 on null.
56. MaxRdpDimension = 8192. Validate rdpWidth and rdpHeight against upper bound in all `-r` format branches.
57. Positive integer validation on rdpWidth and rdpHeight (> 0) in all `-r` format branches.
58. Default throw in switch statements. TestCase.cs switches have default cases that throw InvalidOperationException.
59. Column-count validation in TSV parsing. TestCase.cs throws InvalidDataException if column count < 7.
60. GitHub Actions pinned to commit SHAs (not tags) for security.
61. Publish verification step in release.yml: `test -f publish/resolution_suggester.exe` with error exit.
62. MonitorOracle.cs (test infrastructure) uses MonitorFromPoint. Standard #1 (GetConsoleWindow + MonitorFromWindow) applies to PS1 production code only.
63. dpiX == dpiY validation in MonitorOracle.cs (asymmetric DPI not supported).
64. Process.Start() null check in ProcessRunner.cs: `?? throw new InvalidOperationException(...)`.
65. File I/O try/catch around Set-Content in PS1.
66. Get-FilteredModes function extracted in PS1 for mode filtering.
67. Write-ResolutionOptions function extracted in PS1 for display loops.
68. Read-MenuChoice helper extracted in PS1 for interactive menu input (3 call sites: RDP resolution picker, monitor resolution selection, RDP file selection).
69. SyntheticMonitor: TestMonitorArg is computed property from Width/Height/Frequency/Dpi fields. No literal string field.
70. Pairwise constraints lock RdpSettings to `all_present` for invalid_side and invalid_selection cases.
71. .gitignore simplified from ~480 lines to ~26 essential patterns.
72. DEVMODE CharSet.Auto on StructLayout and EnumDisplaySettings DllImport. Applied in MonitorOracle.cs and PS1.

## To be discussed with user

- [src/Program.cs:NativeMethods.DEVMODE] CONTRADICTION: DEVMODE struct has `[StructLayout(LayoutKind.Sequential)]` without `CharSet = CharSet.Auto`. The `EnumDisplaySettings` DllImport uses `CharSet.Auto` (resolving to `EnumDisplaySettingsW`), but the struct's `ByValTStr` fields marshal as ANSI (32 bytes) instead of Unicode (64 bytes), shifting all subsequent field offsets and corrupting values. Violates standard #72. (agents: bugs 90; evidence: PS1 embedded C# and MonitorOracle.cs both have `CharSet = CharSet.Auto` on their DEVMODE structs; Program.cs NativeMethods.DEVMODE does not)
- [src/Program.cs:~line 167] CONTRADICTION: `SetProcessDpiAwareness` non-zero/non-E_ACCESSDENIED result writes warning to stderr and continues execution. Standard #53 requires erroring on non-zero (excluding E_ACCESSDENIED). PS1 embedded C# returns an error (exit 1). MonitorOracle.cs throws. Program.cs is the only implementation that degrades to a warning. (agents: logic 80; evidence: PS1 line 442-445 returns error, MonitorOracle throws, Program.cs line ~167 writes to Console.Error and continues)
- [src/Program.cs] Duplicated mode-filtering loop pattern. Test-monitor branch and real-monitor branch both perform identical loop body: call `ModeMatchesFilter`, build key string, `seen.Add(key)`, append to `modes`. Could be extracted into a helper. (agents: quality 80; evidence: two loop instances with same dedup-and-filter logic, differing only in where width/height/frequency values come from)
- [src/Program.cs] No `ReadMenuChoice` equivalent extracted. Three identical read+null-check+parse+range-check sequences: RDP resolution picker, monitor resolution selection, RDP file selection. PS1 has this extracted per standard #47. (agents: quality 80; evidence: three instances of Console.ReadLine + null check + int.TryParse + range validation + "Invalid selection" error, matching the pattern PS1 extracts into Read-MenuChoice)
- [README.md + src/Program.cs + src/resolution_suggester.csproj] README documents building, publishing, and installing the C# executable across multiple sections (Install, Releasing, Building). Both `src/Program.cs` and `src/resolution_suggester.csproj` are deleted in the working tree. If deletions are intentional, README sections referencing the exe need revision. (agents: docs 95, docs 80; evidence: `git status` shows ` D src/Program.cs` and ` D src/resolution_suggester.csproj`; README lines 24-28, 109-148 reference the exe)

---
Sweep run: 2026-03-15. Threshold: 80. Skipped file types: (none).
