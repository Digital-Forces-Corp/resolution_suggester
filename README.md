# Resolution Suggester

Analyzes available monitor resolutions on the current monitor and recommends settings for running 1 or 2 RDP windows at a given base RDP resolution (default 800x600) with integer zoom up to 200%, plus a taskbar-fit zoom that maximizes the window while leaving space for the Windows taskbar.

An RDP session at a given RDP resolution does not fit in exactly that many pixels on screen. The window chrome (title bar and borders) adds pixels in both dimensions, so the actual footprint is larger (e.g., 800x600 becomes 814x637 at 100% DPI). Chrome scales proportionally with the monitor's DPI setting — at 200% DPI the chrome is twice as large in pixels — so the program factors in the current DPI when calculating window sizes.

## What It Does

1. Detects the monitor where the console is running (DPI and multi-monitor aware)
2. Enumerates all available monitor resolutions matching the current aspect ratio and refresh rate, and reports when other usable monitor modes exist
3. Calculates how much screen area an RDP window uses at each monitor resolution for integer zoom levels (100%, 200%) and a taskbar-fit zoom that leaves 48 DPI-scaled pixels for the taskbar
4. Ranks monitor resolutions by area efficiency for single-window and dual-window layouts
5. Outputs ready-to-use `winposstr` values for `.rdp` files to position windows at each zoom level
6. Optionally edits `.rdp` files directly when file paths are passed as arguments (interactive mode)

## Install

Choose the path that matches your shell:

1. Already in Windows PowerShell 5.1?

```powershell
New-Item -ItemType Directory -Force -Path c:\dfc\scripts | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri https://raw.githubusercontent.com/Digital-Forces-Corp/resolution_suggester/main/resolutions_suggester.ps1 -OutFile c:\dfc\scripts\resolutions_suggester.ps1
```

2. Starting from `cmd.exe`?

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Force -Path 'c:\dfc\scripts' | Out-Null; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Digital-Forces-Corp/resolution_suggester/main/resolutions_suggester.ps1' -OutFile 'c:\dfc\scripts\resolutions_suggester.ps1'"
```

Alternate path if PowerShell is unavailable:

```powershell
curl.exe -LO --output-dir c:\dfc\scripts https://raw.githubusercontent.com/Digital-Forces-Corp/resolution_suggester/main/resolutions_suggester.ps1
```

The C# executable and winget distribution worked but has been abandoned [csharp-winget-experiment.md](csharp-winget-experiment.md) to to be replaced by deploying an installer that drops the ps1 so users can debug with ai.

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
RDP 800x600 100% rdp zoom: winposstr:s:0,1,0,0,814,637  2nd: winposstr:s:0,1,1745,0,2559,637
RDP 800x600 200% rdp zoom: winposstr:s:0,1,0,0,1614,1237  2nd: winposstr:s:0,1,945,0,2559,1237
RDP 800x600 226% taskbar zoom: winposstr:s:0,1,0,0,1822,1392  2nd: winposstr:s:0,1,737,0,2559,1392
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
- `winposstr` lines: ready-to-use values for positioning the 1st and 2nd RDP windows at each zoom level (100%, 200%, and taskbar-fit)
- Summary line: indicates when additional usable monitor modes were excluded by the default ratio and refresh-rate filters, and points to `--include-mismatch-modes` / `-m`
- Ranked lists: available monitor resolutions sorted by how efficiently they fill the screen for 1 or 2 RDP windows; numbered in interactive mode; includes both integer zoom (100%/200%) and taskbar zoom entries
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

## How It Works

The program:

1. Calls `SetProcessDpiAwareness` with `PROCESS_PER_MONITOR_DPI_AWARE` to enable per-monitor DPI awareness
2. Identifies the current monitor using `GetConsoleWindow` and `MonitorFromWindow` with `MONITOR_DEFAULTTONEAREST`
3. Reads current display settings and DPI via `EnumDisplaySettings` and `GetDpiForMonitor`
4. Enumerates all display modes for that monitor, filtering by default to same aspect ratio (ratio difference < 0.001), same refresh rate, and minimum height to fit at least one RDP session plus window chrome; `--include-mismatch-modes` / `-m` drops the ratio and refresh-rate filters while still requiring a usable height
5. Computes the maximum integer zoom factor each monitor resolution supports (largest N where N * RDP height + chrome height <= monitor resolution height, capped at MaxZoom, currently 2)
6. Computes a taskbar-fit zoom for each monitor resolution: the fractional zoom where `base height * zoom + decoration height + 48 * DPI scale = monitor height`, leaving exactly 48 DPI-scaled pixels for the Windows taskbar
7. Calculates area usage percentages and ranks results
