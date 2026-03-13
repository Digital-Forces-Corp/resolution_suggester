# Resolution Suggester

Analyzes available display resolutions on the current monitor and recommends settings for running 1 or 2 RDP windows at a given base resolution (default 800x600) with zoom levels up to whatever the monitor can fit.

An RDP session at a given resolution does not fit in exactly that many pixels on screen. The window's title bar and borders add pixels in both dimensions, so the actual footprint is larger (e.g., 800x600 becomes 814x637 at 100% DPI). These decorations scale proportionally with the monitor's DPI setting — at 200% DPI the borders are twice as large in pixels — so the program factors in the current DPI when calculating window sizes.

## What It Does

1. Detects the monitor where the console is running (DPI-aware, multi-monitor safe)
2. Enumerates all available resolutions matching the current aspect ratio and refresh rate
3. Calculates how much screen area an RDP window uses at each resolution and zoom level
4. Ranks resolutions by area efficiency for single-window and dual-window layouts
5. Outputs ready-to-use `winposstr` values for `.rdp` files to position windows at each zoom level

## Install

```
winget install DigitalForcesCorp.ResolutionSuggester
```

Or download `resolution_suggester.exe` from the [latest release](https://github.com/Digital-Forces-Corp/resolution_suggester/releases/latest).

## Requirements

- Windows 10 or later

No external dependencies. The published executable is self-contained (bundles the .NET runtime). The program calls Windows display APIs directly via P/Invoke.

## Usage

```
resolution_suggester                        # default 800x600
resolution_suggester --resolution 1280x1024 # 1280x1024
```

`--resolution` accepts `WxH` format. Default is `800x600`.

## Output

```
Current Monitor #1, 2560x1440, Ratio: 16:9, DPI Scale 100%, Frequency: 60Hz
RDP 800x600 100% rdp zoom: winposstr:s:0,1,0,0,814,637  2nd: winposstr:s:0,1,1746,0,2559,637
RDP 800x600 200% rdp zoom: winposstr:s:0,1,0,0,1614,1237  2nd: winposstr:s:0,1,946,0,2559,1237

--- Best for 1 RDP 800x600 window (sorted by area used) ---
*2560x1440, 64% area (31% width, 204% height), 200% rdp zoom
 1920x1080, 42% area (42% width, 102% height), 100% rdp zoom

--- Best for 2 RDP 800x600 windows (sorted by area used) ---
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
smart sizing:i:0
allow font smoothing:i:1
desktopwidth:i:800
desktopheight:i:600
winposstr:s:0,1,0,0,814,637
```

- `smart sizing` \- scales the remote desktop to fit the window without changing the remote resolution
- `allow font smoothing` \- enables ClearType rendering in the session
- `desktopwidth` / `desktopheight` \- the remote session resolution (must match the `--resolution` value passed to the program)
- `winposstr` \- window position on the local monitor; format: `flags,showCmd,left,top,right,bottom`

## How It Works

The program:

1. Calls `SetProcessDpiAwareness` for accurate pixel measurements on scaled displays
2. Identifies the current monitor using `MonitorFromWindow` on the console window handle
3. Reads current display settings and DPI via `EnumDisplaySettings` and `GetDpiForMonitor`
4. Enumerates all display modes for that monitor, filtering to same aspect ratio (within 0.1%), same refresh rate, and minimum height to fit at least one RDP session plus window borders and title bar
5. Computes the maximum integer zoom factor each resolution supports (largest N where N \* base height + decoration height <= resolution height, capped at 2)
6. Calculates area usage percentages and ranks results

## Building

Requires .NET 8 SDK.

```
dotnet publish src/resolution_suggester.csproj -c Release -o publish
```

Produces a self-contained, trimmed single-file executable (~12MB).
