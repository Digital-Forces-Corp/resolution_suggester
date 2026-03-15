## Standards (to prevent flip-flops)

1. Monitor detection: `GetConsoleWindow()` + `MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST)`. No `MonitorFromPoint`.
2. ProcessRunner: `process.WaitForExit()` (no-arg) after `Kill()`.
3. Test error handling: `throw`, not error-string returns.
4. Area percentage: `Math.Round` for computation, capped at 100% with `Math.Min(widthUsage, 100)`. Applies to both C# and PS1.
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
17. release.yml: separate "Build" and "Test" YAML steps. Each step gets its own pass/fail in the GitHub Actions UI.
18. DEVMODE fields: `uint` to match Windows SDK `DWORD` typedef. Explicit `(int)` casts at usage sites. Applies to Program.cs, MonitorOracle.cs, and PS1 embedded C#.
19. CountOptionLines: regex `^\*?\d+x\d+,` for line counting, `Split(new[] { "\r\n", "\n" }, ...)` for line splitting, `Trim()` (not `TrimStart()`) for section-end detection.
20. Solution file: SDK-style project type GUID `{9A19103F-16F7-4668-BE54-9A1E7A4F7556}` for all projects.
21. Assertion failure messages: verbose. Include stdout, stderr, and excerpts. CI failures must be diagnosable without re-running locally.
22. SyntheticMonitor `TestMonitorArg`: computed property derived from Width/Height/Frequency/Dpi fields. No literal string duplication.
23. ProcessRunner: both stdout and stderr read async via `Task.Run`. Synchronous reads deadlock.
24. ProcessRunner timeout message: include stdout and stderr. Consistent with standard #21.

## Last version (progressive improvements)

25. README SetProcessDpiAwareness description: "with PROCESS_PER_MONITOR_DPI_AWARE to enable per-monitor DPI awareness".
26. README `-r` flag description: three formats WxH, W, WxN:D.
27. README aspect ratio tolerance wording: "same aspect ratio (ratio difference < 0.001)".
28. README zoom cap wording: "capped at the maximum zoom level, currently 2".
29. README build output path: "Produces publish\resolution_suggester.exe (pass -o publish as shown above).".
30. README winget PR timing: specific PR references and measured durations.
31. csproj DebugType: conditional on Release `<DebugType Condition="'$(Configuration)' == 'Release'">none</DebugType>`.
32. TestCase.cs BuildCliArgs: no `impl` parameter.
33. pairwise.pict comment ordering: merged comment blocks for file selection and nonexistent file.
34. Standard #1 respected: code reverted from MonitorFromPoint to GetConsoleWindow + MonitorFromWindow in both Program.cs and PS1.
35. PS1 embedded C# Marshal.SizeOf uses generic form `Marshal.SizeOf<T>()`.
36. PS1 embedded C# GetMonitorData receives `ratio_tolerance` as a parameter; no hardcoded `RatioTolerance` constant.
37. Program.cs zoomFactor < 1 guard added. PS1 already had it.
38. PS1 display loops extracted into `Write-ResolutionOptions` function.
39. PS1 dead code `if ($currentRatio -eq 0)` removed (unreachable).
40. Program.cs dead validation `rdpWidth <= 0` in WxN:D branch removed (unified validation).
41. README header line field order: "aspect ratio, refresh rate, DPI scale".
42. README build command includes `-o publish`.
43. README smart sizing description: "disabled — the remote desktop renders at native resolution without scaling".
44. README MonitorFromPoint description corrected to GetConsoleWindow + MonitorFromWindow.
45. release.yml tag validation moved to first step after checkout.
46. release.yml tag regex has end anchor `$`.
47. Program.cs and PS1 `-r` validation extracted into unified block (no duplication).
48. Program.cs dpiScale/chromeWidth/chromeHeight/minimumHeight extracted into ComputeDisplayMetrics helper.
49. PS1 zoom/area computation duplication between test-monitor path and embedded C# is intentional (documented).
50. README workflow description lists six steps: validate tag, build, test, publish+verify, create release, submit to winget.
51. README intro "zoom levels up to 2x" matches MaxZoom = 2.
52. PS1 `Get-FilteredModes` assigns `$modeFreq = $modeEntry.Frequency` inside the foreach loop, matching Program.cs per-mode extraction.
53. PS1 `-r` picker lookahead conforms to standard #14: first `-or` clause guards bounds, subsequent clauses have no redundant bounds checks.
54. PS1 and Program.cs reference winposstr display clamps `x0` with `Math.Max(0, ...)`, matching the interactive path.
55. PS1 menu input extracted into `Read-MenuChoice` helper (prompt, min, max). Three call sites: RDP resolution picker, monitor resolution selection, RDP file selection.
56. README sample output area percentage for 1920x1080 at 100% zoom: 25% (matches `Math.Round` computation).
57. README PS1 file size: ~29KB.
58. release.yml Publish step uses `--no-build` to reuse Build step output.

59. DisplayMonitor.cs deleted. Monitor detection code integrated into Program.cs.
60. Terminology rename: "scenario" → "monitor resolution"/"option" in output text. `--resolution` → `--rdp-resolution` flag name.
61. StructLayout(LayoutKind.Sequential) on RECT, POINT, and interop structs in Program.cs, MonitorOracle.cs, and PS1 embedded C#.
62. SetProcessDpiAwareness HRESULT check: ignore E_ACCESSDENIED (0x80070005), error on other non-zero. Program.cs, MonitorOracle.cs, PS1.
63. GetDpiForMonitor HRESULT check: error on non-zero. Validate dpiX > 0 (Program.cs checks `dpiX == 0`).
64. Console.ReadLine() / `[Console]::In.ReadLine()` null guard before `.Trim()`. Exit 1 on null.
65. MaxRdpDimension = 8192. Validate rdpWidth and rdpHeight against upper bound in all `-r` format branches.
66. Positive integer validation on rdpWidth and rdpHeight (> 0) in all `-r` format branches.
67. Integer overflow protection in WxN:D ratio computation: `(int)((long)rdpWidth * ratioH / ratioW)` in Program.cs.
68. Default throw in switch statements. TestCase.cs and Program.cs switches have default cases that throw InvalidOperationException.
69. Column-count validation in TSV parsing. TestCase.cs throws InvalidDataException if column count < 7.
70. GitHub Actions pinned to commit SHAs (not tags) for security.
71. Publish verification step in release.yml: `test -f publish/resolution_suggester.exe` with error exit.
72. MonitorOracle.cs (test infrastructure) uses MonitorFromPoint. Standard #1 (GetConsoleWindow + MonitorFromWindow) applies to Program.cs and PS1 production code only.
73. dpiX == dpiY validation in MonitorOracle.cs (asymmetric DPI not supported). dpiX > 0 validation in Program.cs.
74. Process.Start() null check in ProcessRunner.cs: `?? throw new InvalidOperationException(...)`.
75. File I/O try/catch around File.ReadAllLines/WriteAllLines in Program.cs and Set-Content in PS1.
76. ModeMatchesFilter helper extracted in Program.cs for mode filtering logic.
77. PrintResolutionOptions helper extracted in Program.cs for 1-window and 2-window display loops.
78. Get-FilteredModes function extracted in PS1 for mode filtering.
79. Write-ResolutionOptions function extracted in PS1 for display loops.
80. Read-MenuChoice helper extracted in PS1 for interactive menu input (3 call sites: RDP resolution picker, monitor resolution selection, RDP file selection).
81. SyntheticMonitor: TestMonitorArg is computed property from Width/Height/Frequency/Dpi fields. No literal string field.
82. Pairwise constraints lock RdpSettings to `all_present` for invalid_side and invalid_selection cases.
83. .gitignore simplified from ~480 lines to ~26 essential patterns.
84. Test project (ResolutionSuggesterTests.csproj) added to solution with x86/x64/AnyCPU configurations.
85. DEVMODE CharSet.Auto on StructLayout and EnumDisplaySettings DllImport. Applied in Program.cs, MonitorOracle.cs, and PS1.

## To be discussed with user

---
