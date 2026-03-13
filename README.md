# Resolution Suggester

Analyzes available display resolutions on the current monitor and recommends settings for running 1 or 2 RDP windows at 800x600 base resolution with zoom levels from 100% to 300%.

An 800x600 RDP session does not fit in 800x600 pixels on screen. The window's title bar and borders add pixels in both dimensions, so the actual footprint is larger (e.g., 814x637 at 100% DPI). These decorations scale proportionally with the monitor's DPI setting — at 200% DPI the borders are twice as large in pixels — so the script factors in the current DPI when calculating window sizes.

## What It Does

1. Detects the monitor where the console is running (DPI-aware, multi-monitor safe)
2. Enumerates all available resolutions matching the current aspect ratio and refresh rate
3. Calculates how much screen area an RDP window uses at each resolution and zoom level
4. Ranks resolutions by area efficiency for single-window and dual-window layouts
5. Outputs ready-to-use `winposstr` values for `.rdp` files to position windows at each zoom level

## Requirements

- Windows 10 or later
- PowerShell 5.1

No external dependencies. The script compiles embedded C# at runtime using `Add-Type` and calls Windows display APIs directly via P/Invoke.

## Usage

```powershell
.\resolutions_suggester.ps1
```

## Output

```
Current Monitor #1, 2560x1440, Ratio: 16:9, DPI Scale 100%, Frequency: 60Hz
RDP 800x600 100% rdp zoom: winposstr:s:0,1,0,0,814,637  2nd: winposstr:s:0,1,1746,0,2559,637
RDP 800x600 200% rdp zoom: winposstr:s:0,1,0,0,1614,1237  2nd: winposstr:s:0,1,946,0,2559,1237
RDP 800x600 300% rdp zoom: winposstr:s:0,1,0,0,2414,1837  2nd: winposstr:s:0,1,146,0,2559,1837

--- Best for 1 RDP window (sorted by area used) ---
*2560x1440, 64% area (31% width, 204% height), 200% rdp zoom
 1920x1080, 42% area (42% width, 102% height), 100% rdp zoom

--- Best for 2 RDP windows (sorted by area used) ---
*2560x1440, 100% area (100% width, 102% height), 100% rdp zoom
 1920x1080, 84% area (84% width, 102% height), 100% rdp zoom
```

### Reading the Output

- Header line: monitor number, current resolution, aspect ratio, DPI scale, refresh rate
- `winposstr` lines: copy these into `.rdp` files to position the 1st and 2nd RDP windows at each zoom level
- Ranked lists: resolutions sorted by how efficiently they fill the screen for 1 or 2 RDP windows
- `*` marks the current resolution
- Percentage values: `width` = horizontal space used, `height` = vertical space used, `area` = combined fill
- `overlap` (in dual-window list) = percentage the two windows overlap horizontally when they exceed monitor width

### Applying winposstr Values

Add these lines to an `.rdp` file:

```
smart sizing:i:1
allow font smoothing:i:1
desktopwidth:i:800
desktopheight:i:600
winposstr:s:0,1,0,0,814,637
```

- `smart sizing` \- scales the remote desktop to fit the window without changing the remote resolution
- `allow font smoothing` \- enables ClearType rendering in the session
- `desktopwidth` / `desktopheight` \- the remote session resolution (800x600 matches the script's base)
- `winposstr` \- window position on the local monitor; format: `flags,showCmd,left,top,right,bottom`

## How It Works

The script compiles a C# class at runtime that:

1. Calls `SetProcessDpiAwareness` for accurate pixel measurements on scaled displays
2. Identifies the current monitor using `MonitorFromWindow` on the console window handle
3. Reads current display settings and DPI via `EnumDisplaySettings` and `GetDpiForMonitor`
4. Enumerates all display modes for that monitor, filtering to same aspect ratio (within 0.1%), same refresh rate, and minimum height to fit at least one 600px RDP session plus window borders and title bar
5. Computes the maximum integer zoom factor each resolution supports (largest N where N \* 600 + decoration height <= resolution height)
6. Calculates area usage percentages and ranks results

The type name includes a hash of the source code so the script can be re-run in the same PowerShell session without type-loading conflicts.
