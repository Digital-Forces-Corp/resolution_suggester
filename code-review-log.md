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

## To be discussed with user

- [Program.cs:243, resolutions_suggester.ps1:446, README.md:103] CONTRADICTION with standard #1: code and README use `MonitorFromPoint(POINT{0,1}, MONITOR_DEFAULTTONEAREST)` but standard #1 says "No `MonitorFromPoint`." Standard #1 text is stale. (agents: security 95, bugs 95, logic 95, docs 95; evidence: no reference to `GetConsoleWindow` or `MonitorFromWindow` exists anywhere in the codebase)

- [resolutions_suggester.ps1:432,434,449] CONTRADICTION with standard #8: PS1 embedded C# uses `Marshal.SizeOf(devMode)`, `Marshal.SizeOf(currentSettings)`, `Marshal.SizeOf(monitorInfo)` — the instance form. Standard #8 requires `Marshal.SizeOf<T>()`. Program.cs correctly uses the generic form. (agents: security 90, bugs 80, logic 80, quality 95; evidence: three call sites in PS1 embedded C# use the instance overload)

- [resolutions_suggester.ps1:425] CONTRADICTION with standard #16: PS1 embedded C# hardcodes `const double RatioTolerance = 0.001` instead of receiving it as a parameter to `GetMonitorData`. PS1 top-level also defines `$RatioTolerance = 0.001` on line 9, creating a duplicated magic value. (agents: quality 95; evidence: standard #16 says "pass constants as parameters, no hardcoded duplicates")

- [Program.cs:324] Missing `zoomFactor < 1` guard in compute loop. PS1 line 270 has `if ($zoom -lt 1) { continue }` but Program.cs has no equivalent, allowing zero-zoom entries with meaningless window dimensions. (agents: bugs 90, logic 90, quality 80, docs 80; evidence: PS1 line 270 guards explicitly, C# does not)

- [resolutions_suggester.ps1:606-625] CONTRADICTION with standard #10: PS1 1-window and 2-window display loops are near-identical copy-paste. Program.cs extracted this into `PrintResolutionOptions`. (agents: quality 85; evidence: lines 606-612 and 617-625 differ only in area/width fields and overlap note)

- [resolutions_suggester.ps1:252] Dead code: `if ($currentRatio -eq 0)` guard is unreachable because `$currentRatio` is computed as `$currentWidth / $currentHeight` on line 227 — if `$currentHeight` were zero, division would already have thrown before reaching line 252. (agents: quality 80, logic 50; evidence: line 227 divides unconditionally by `$currentHeight`)

- [Program.cs:117] Dead validation: `rdpWidth <= 0` check inside WxN:D branch is unreachable because the same condition already exits at line 102-106. (agents: quality 80; evidence: line 102 `if (rdpWidth <= 0)` exits, so line 117 left operand is always false)

- [README.md:74] Header line field order is wrong: describes "aspect ratio, DPI scale, refresh rate" but actual output (Program.cs:349, PS1:587) emits "Ratio, Frequency, DPI Scale" — frequency before DPI scale. (agents: bugs 95, quality 90, logic 95; evidence: example output on line 59 shows `Ratio: 16:9, Frequency: 60Hz, DPI Scale 100%`)

- [README.md:140,143] Build command `dotnet publish src/resolution_suggester.csproj -c Release` does not include `-o publish`, but line 143 says "pass `-o publish` as shown above." Without `-o publish`, actual output path is `src/bin/Release/net8.0-windows/win-x64/publish/`. Last-version entry #29 records this exact text. (agents: docs 92, bugs 95, quality 95, logic 95; evidence: release.yml line 30 has `-o publish` but README line 140 does not)

- [README.md:93] `smart sizing:i:0` description says "scales the remote desktop to fit the window" but `:i:0` disables smart sizing. Description matches enabled behavior, not the value shown. (agents: docs 85, bugs 80, logic 80, quality 80; evidence: `smart sizing:i:0` = disabled, `i:1` = enabled)

- [README.md:9] States "Detects the monitor where the console is running" but `MonitorFromPoint(0,1)` finds the monitor nearest to screen coordinate (0,1), not the console's monitor. On multi-monitor setups with the console on a secondary monitor, the result differs. (agents: docs 80, logic 80; evidence: Program.cs:243 and PS1:446 pass fixed coordinates, not a window handle)

- [release.yml:32-40] Tag format validation runs after Build, Test, and Publish. An invalid tag like `vfoo` triggers the workflow, burns through all three steps, then fails at validation. (agents: logic 80; evidence: steps execute sequentially; Build line 24, Test line 27, Publish line 30 all precede validation at line 36)

- [release.yml:36] Tag regex `^v[0-9]+\.[0-9]+\.[0-9]+` has no end anchor. Tags like `v1.2.3-rc1` or `v1.2.3garbage` pass validation. The extracted version string propagates to winget-releaser. (agents: logic 80; evidence: no `$` anchor; error message says "expected format v\*.\*.\*" suggesting strict matching was intended)

---
Sweep run: 2026-03-15. Threshold: 80. Skipped file types: (none — all tracked files are text)
