# Resolution Suggester

Analyzes available monitor resolutions on the current monitor and recommends settings for running 1 or 2 RDP windows at a given base RDP resolution (default 800x600), showing every supported whole-number zoom level from 100% through 200% plus a taskbar-fit zoom that maximizes the window while leaving space for the Windows taskbar.

An RDP session at a given RDP resolution does not fit in exactly that many pixels on screen. The window chrome (title bar and borders) adds pixels in both dimensions, so the actual footprint is larger (e.g., 800x600 becomes 814x637 at 100% DPI). Chrome scales proportionally with the monitor's DPI setting — at 200% DPI the chrome is twice as large in pixels — so the program factors in the current DPI when calculating window sizes.

## What It Does

1. Detects the monitor where the console is running (DPI and multi-monitor aware)
2. Enumerates all available monitor resolutions matching the current aspect ratio and refresh rate, and reports when other usable monitor modes exist
3. Calculates how much screen area an RDP window uses at each monitor resolution for each supported whole-number zoom level from 100% up to the configured cap (currently 200%), along with a taskbar-fit zoom that leaves 48 DPI-scaled pixels for the taskbar
4. Ranks monitor resolutions by area efficiency for single-window and dual-window layouts
5. Outputs ready-to-use `winposstr` values for `.rdp` files to position windows at each zoom level
6. Optionally edits `.rdp` files directly when file paths are passed as arguments (interactive mode)

## Install

Download the script, then run it. PowerShell script execution is assumed to be blocked (`running scripts is disabled on this system`), so both steps use scriptblock invocation instead of running the `.ps1` directly.

1. Download:

```powershell
New-Item -ItemType Directory -Force C:\dfc\scripts | Out-Null; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://raw.githubusercontent.com/Digital-Forces-Corp/resolution_suggester/main/resolutions_suggester.ps1' -OutFile C:\dfc\scripts\resolutions_suggester.ps1
```

2. Run:

```powershell
& ([scriptblock]::Create((Get-Content -Raw C:\dfc\scripts\resolutions_suggester.ps1)))
```

The script prompts for RDP resolution and options interactively.

## Run Without Installing

PowerShell script execution is typically blocked (`running scripts is disabled on this system`). These one-liners bypass the restriction by downloading the script content and executing it as a scriptblock in memory — no `.ps1` file touches disk.

From Windows PowerShell 5.1:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((Invoke-WebRequest 'https://raw.githubusercontent.com/Digital-Forces-Corp/resolution_suggester/main/resolutions_suggester.ps1').Content))
```

From `cmd.exe`:

```bat
powershell.exe -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; & ([scriptblock]::Create((Invoke-WebRequest 'https://raw.githubusercontent.com/Digital-Forces-Corp/resolution_suggester/main/resolutions_suggester.ps1').Content))"
```

## Simplifying Distribution

The earlier C# executable and winget packaging experiment worked, but this project now ships as a single PowerShell script instead. See [csharp-winget-experiment.md](csharp-winget-experiment.md) for the abandoned approach.

Reasons for the change:

- Keeping both the PowerShell and C# implementations in sync created substantial development overhead.
- Shipping PowerShell makes the tool easier for users to inspect, debug, and adapt with AI assistance.

Possible alternatives in the future:

- Ship the C# source as a .NET 10 file-based app that runs directly with `dotnet run <file>.cs`.
- Provide an installer that writes out the PowerShell script.


## Requirements

- Windows 10 or later

## Usage

```
resolution_suggester c:\rdp\server.rdp  # interactive: choose monitor resolution, and L/R position
resolution_suggester -h                 # show help
resolution_suggester                    # default remote desktop 800x600
resolution_suggester -r 1280x1024       # remote desktop 1280x1024
resolution_suggester -r 1280            # remote desktop width-only, height from monitor aspect ratio
resolution_suggester -r 1280x4:3        # remote desktop width with explicit 4:3 aspect ratio
resolution_suggester -m                 # include usable monitor modes with different ratio or refresh rate
resolution_suggester C:\dfc\rdp\        # interactive: choose monitor resolution, L/R position, and .rdp file
```

`--rdp-resolution` / `-r` accepts three formats: `WxH` (explicit width and height), `W` (width-only, height derived from monitor aspect ratio), and `WxN:D` (width with explicit aspect ratio). Default is `800x600`. `-r` with no argument opens an interactive picker to select from common RDP resolutions. 
`--include-mismatch-modes` / `-m` includes usable monitor modes even when their aspect ratio or refresh rate differs from the current mode. 

When `.rdp` file paths or directories are passed, the program enters interactive mode. It numbers each monitor resolution in the output, then prompts to choose a monitor resolution, an `.rdp` file (if multiple), and left/right window position. The selected `winposstr`, RDP resolution, and display settings are written directly into the `.rdp` file.

## Output

```
Current Monitor #1, 2560x1440, Ratio: 16:9, Frequency: 60Hz, DPI Scale 100%
RDP 800x600 100% rdp zoom: winposstr:s:0,1,0,0,814,637  2nd: winposstr:s:0,1,1746,0,2560,637
RDP 800x600 200% rdp zoom: winposstr:s:0,1,0,0,1614,1237  2nd: winposstr:s:0,1,946,0,2560,1237
RDP 800x600 226% taskbar zoom: winposstr:s:0,1,0,0,1822,1392  2nd: winposstr:s:0,1,738,0,2560,1392
Also found 2 other usable monitor modes on this monitor (1 ratio mismatch, 1 refresh mismatch). Run with --include-mismatch-modes / -m to include them.

--- Available monitor resolutions for 1 RDP 800x600 with same ratio and frequency sorted by area used ---
*2560x1440, 69% area (71% width, 97% height), 226% taskbar zoom
*2560x1440, 54% area (63% width, 86% height), 200% rdp zoom
 1920x1080, 25% area (42% width, 59% height), 100% rdp zoom

--- Available monitor resolutions for 2 RDP 800x600 with same ratio and frequency sorted by area used ---
*2560x1440, 97% area (100% width, 97% height, 42% overlap), 226% taskbar zoom
*2560x1440, 86% area (100% width, 86% height, 26% overlap), 200% rdp zoom
 1920x1080, 50% area (85% width, 59% height), 100% rdp zoom
```

### Reading the Output

- Header line: monitor number, current monitor resolution, aspect ratio, refresh rate, DPI scale
- `winposstr` lines: ready-to-use values for positioning the 1st and 2nd RDP windows at each supported whole-number zoom level, plus the taskbar-fit entry
- Summary line: indicates when additional usable monitor modes were excluded by the default ratio and refresh-rate filters, and points to `--include-mismatch-modes` / `-m`
- Ranked lists: available monitor resolutions sorted by how efficiently they fill the screen for 1 or 2 RDP windows; numbered in interactive mode; includes every supported whole-number zoom entry together with the taskbar zoom entry
- `*` marks the current monitor resolution
- Percentage values: `width` = horizontal space used, `height` = vertical space used, `area` = combined fill
- `overlap` (in dual-window list) = percentage the two windows overlap horizontally when they exceed monitor width

### Applying winposstr Values

To apply manually (interactive mode writes these automatically), add these lines to an `.rdp` file and set `smart sizing` to `i:1` on Windows 11 or `i:0` on Windows 10:

```
smart sizing:i:<0_or_1>
allow font smoothing:i:1
desktopwidth:i:800
desktopheight:i:600
winposstr:s:0,1,0,0,814,637
```

- `smart sizing` \- on Windows 11 (`i:1`), the remote desktop is scaled to fit the window; on Windows 10 (`i:0`), it renders at native resolution without scaling
- `allow font smoothing` \- enables ClearType rendering in the session
- `desktopwidth` / `desktopheight` \- the remote session resolution (must match the `-r` value passed to the program)
- `winposstr` \- window position on the local monitor; format: `flags,showCmd,left,top,right,bottom`

Note: when you create or save an `.rdp` file in the Remote Desktop Connection GUI, `winposstr` is typically carried over from the current per-user `Default.rdp` state rather than recomputed from `desktopwidth` / `desktopheight`. In practice, GUI-created files often inherit the last remembered local client window rectangle.

### Speed Profiles

The built-in Remote Desktop speed presets mainly change the connection type and a small set of visual-effect toggles.

| Setting | Highest speed | Lowest speed |
| --- | --- | --- |
| `connection type:i` | `6` | `1` |
| `disable wallpaper:i` | `0` | `1` |
| `allow font smoothing:i` | `1` | `0` |
| `allow desktop composition:i` | `1` | `0` |
| `disable full window drag:i` | `0` | `1` |
| `disable menu anims:i` | `0` | `1` |
| `disable themes:i` | `0` | `1` |

In practice, the low-speed profile disables most cosmetic effects, while the high-speed profile leaves them enabled.

### Probing MSTSC Window Behavior

Use [rdp_window_probe/rdp_window_probe.ps1](rdp_window_probe/rdp_window_probe.ps1) to iterate over `smart sizing`, `screen mode id`, the `showCmd` field in `winposstr`, selected `winposstr` right/bottom sizes, and a `smart_size_125` yes/no probe flag. The `smart_size_125` flag is only used when `smart sizing=1`; for `smart sizing=0`, the probe always records `smart_size_125=no`. When `smart_size_125=yes`, the script attempts to enlarge the live MSTSC window by 25% via Win32 before taking the final measurement. With the default settings, this produces 24 probe rows. It writes a CSV with the main window size, client size, and largest visible child window size. Use `-SingleCase` to run exactly one probe row with scalar parameters instead of one-element arrays.

Example:

```powershell
powershell -File .\rdp_window_probe\rdp_window_probe.ps1

powershell -File .\rdp_window_probe\rdp_window_probe.ps1 -SingleCase -TargetAddress 192.0.2.1 -SmartSizing 0 -ScreenModeId 1 -WinposShowCmd 1 -WinposSize 800x600
```

## How It Works

The program:

1. Calls `SetProcessDpiAwareness` with `PROCESS_PER_MONITOR_DPI_AWARE` to enable per-monitor DPI awareness
2. Identifies the current monitor using `GetConsoleWindow` and `MonitorFromWindow` with `MONITOR_DEFAULTTONEAREST`
3. Reads current display settings and DPI via `EnumDisplaySettings` and `GetDpiForMonitor`
4. Enumerates all display modes for that monitor, filtering by default to same aspect ratio (ratio difference < 0.001), same refresh rate, and minimum height to fit at least one RDP session plus window chrome; `--include-mismatch-modes` / `-m` drops the ratio and refresh-rate filters while still requiring a usable height
5. Computes the supported whole-number zoom factors for each monitor resolution, from 100% through the largest value where `N * RDP height + chrome height <= monitor resolution height`, capped at `MaxZoom` (currently 2)
6. Computes a taskbar-fit zoom for each monitor resolution: the fractional zoom where `base height * zoom + decoration height + 48 * DPI scale = monitor height`, leaving exactly 48 DPI-scaled pixels for the Windows taskbar
7. Calculates area usage percentages and ranks results
