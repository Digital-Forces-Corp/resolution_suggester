# Resolution Suggester

Analyzes available monitor resolutions on the current monitor and recommends settings for running 1 or 2 RDP windows at a given base resolution (default 800x600) with zoom levels up to whatever the monitor can fit.

An RDP session at a given RDP resolution does not fit in exactly that many pixels on screen. The window's title bar and borders add pixels in both dimensions, so the actual footprint is larger (e.g., 800x600 becomes 814x637 at 100% DPI). These decorations scale proportionally with the monitor's DPI setting — at 200% DPI the borders are twice as large in pixels — so the program factors in the current DPI when calculating window sizes.

## What It Does

1. Detects the monitor where the console is running (DPI and multi-monitor aware)
2. Enumerates all available monitor resolutions matching the current aspect ratio and refresh rate
3. Calculates how much screen area an RDP window uses at each monitor resolution and appropriate zoom level
4. Ranks monitor resolutions by area efficiency for single-window and dual-window layouts
5. Outputs ready-to-use `winposstr` values for `.rdp` files to position windows at each zoom level
6. Optionally edits `.rdp` files directly when file paths are passed as arguments (interactive mode)

## Install

PowerShell script (~12KB, no dependencies):

```powershell
curl.exe -Lo c:\dfc\scripts\resolutions_suggester.ps1 https://raw.githubusercontent.com/Digital-Forces-Corp/resolution_suggester/main/resolutions_suggester.ps1
```

Self-contained executable (~12MB, no dependencies):

```
curl.exe -Lo c:\dfc\scripts\resolution_suggester.exe https://github.com/Digital-Forces-Corp/resolution_suggester/releases/latest/download/resolution_suggester.exe
```

Or via winget (installs to winget's default location on PATH, not `c:\dfc\scripts`):

```
winget install DigitalForcesCorp.ResolutionSuggester
```

## Requirements

- Windows 10 or later

## Usage

```
resolution_suggester -h                 # show help
resolution_suggester                    # default 800x600
resolution_suggester -r 1280x1024       # 1280x1024
resolution_suggester server.rdp         # interactive: choose monitor resolution, and L/R position
resolution_suggester C:\Users\me\rdp\   # interactive: choose monitor resolution, L/R position, and .rdp file
```

`--rdp-resolution` / `-r` accepts `WxH` format. Default is `800x600`. The PowerShell script uses `-r` the same way.

When `.rdp` file paths or directories are passed, the program enters interactive mode. It numbers each monitor resolution in the output, then prompts to choose a monitor resolution, an `.rdp` file (if multiple), and left/right window position. The selected `winposstr`, RDP resolution, and display settings are written directly into the `.rdp` file.

## Output

```
Current Monitor #1, 2560x1440, Ratio: 16:9, Frequency: 60Hz, DPI Scale 100%
RDP 800x600 100% rdp zoom: winposstr:s:0,1,0,0,814,637  2nd: winposstr:s:0,1,1745,0,2559,637
RDP 800x600 200% rdp zoom: winposstr:s:0,1,0,0,1614,1237  2nd: winposstr:s:0,1,945,0,2559,1237

--- Available monitor resolutions for 1 RDP 800x600 with same ratio and frequency sorted by area used ---
*2560x1440, 54% area (63% width, 86% height), 200% rdp zoom
 1920x1080, 24% area (42% width, 59% height), 100% rdp zoom

--- Available monitor resolutions for 2 RDP 800x600 with same ratio and frequency sorted by area used ---
*2560x1440, 86% area (100% width, 86% height, 26% overlap), 200% rdp zoom
 1920x1080, 50% area (85% width, 59% height), 100% rdp zoom
```

### Reading the Output

- Header line: monitor number, current monitor resolution, aspect ratio, DPI scale, refresh rate
- `winposstr` lines: ready-to-use values for positioning the 1st and 2nd RDP windows at each zoom level
- Ranked lists: available monitor resolutions sorted by how efficiently they fill the screen for 1 or 2 RDP windows; numbered in interactive mode
- `*` marks the current monitor resolution
- Percentage values: `width` = horizontal space used, `height` = vertical space used, `area` = combined fill
- `overlap` (in dual-window list) = percentage the two windows overlap horizontally when they exceed monitor width

### Applying winposstr Values

To apply manually (interactive mode writes these automatically), add these lines to an `.rdp` file:

```
smart sizing:i:0
allow font smoothing:i:1
desktopwidth:i:800
desktopheight:i:600
winposstr:s:0,1,0,0,814,637
```

- `smart sizing` \- scales the remote desktop to fit the window without changing the remote resolution
- `allow font smoothing` \- enables ClearType rendering in the session
- `desktopwidth` / `desktopheight` \- the remote session resolution (must match the `-r` value passed to the program)
- `winposstr` \- window position on the local monitor; format: `flags,showCmd,left,top,right,bottom`

## How It Works

The program:

1. Calls `SetProcessDpiAwareness` to enable DPI awareness (per-monitor v2 if available, otherwise system DPI aware)
2. Identifies the current monitor using `MonitorFromWindow` on the console window handle
3. Reads current display settings and DPI via `EnumDisplaySettings` and `GetDpiForMonitor`
4. Enumerates all display modes for that monitor, filtering to same aspect ratio (within 0.1%), same refresh rate, and minimum height to fit at least one RDP session plus window borders and title bar
5. Computes the maximum integer zoom factor each monitor resolution supports (largest N where N \* base height + decoration height <= monitor resolution height, capped at 2)
6. Calculates area usage percentages and ranks results

## Releasing a New Version To Windows Package Manager (winget)

Pushing a `v*` tag triggers the [release workflow](.github/workflows/release.yml), which:

1. Builds the self-contained executable on `windows-latest`
2. Creates a GitHub Release with auto-generated release notes and the `.exe` attached
3. Submits the new version to winget via `winget-releaser` (requires `WINGET_TOKEN` GitHub repository secret)

```
git tag v1.2.0
git push origin v1.2.0
```

## Building the Executable

Requires .NET 8 SDK. The PowerShell script needs no build step.

```
dotnet publish src/resolution_suggester.csproj -c Release
```

Produces `c:\dfc\scripts\resolution_suggester.exe`.
