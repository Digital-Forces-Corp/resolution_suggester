# RDP Window Probe

A PowerShell-based diagnostic suite and test harness designed to automate, probe, measure, and analyze the window dimension and scaling behaviors of the Windows Remote Desktop Client (MSTSC) under varying connection configurations.

## Workspace Overview

The tools in this codebase help diagnose how MSTSC negotiates client dimensions, screen resolution, and DPI-scaling overrides:

* **[rdp_window_probe.ps1](rdp_window_probe.ps1)**: An automated testing script. It accepts configuration matrices (Smart-sizing, different initial sizing dimensions, Winpos parameters) and sweeps through them by spawning unique client instances. Using C# P/Invoke, it programmatically monitors window status, measures exact outer and client window areas, and logs results to a timestamped CSV.
* **[resize_open_mstsc.ps1](resize_open_mstsc.ps1)**: A playground and diagnostic script used to analyze dynamic resizing issues. It details research attempts to programmatically resize active sessions and documents edge cases where MSTSC snaps windows back to their original size instead of scaling/renegotiating desktop real estate.
* **[set_rdp_warning.ps1](set_rdp_warning.ps1)**: A helper script that manages Registry values under HKLM and HKCU to suppress interactive RDP warnings, webauthn consent alerts, and prompt-blocking dialogs so that automation runs uninhibited.

## Script Parameters Reference

### `rdp_window_probe.ps1`
Runs a configuration sweep or a targeted test over defined RDP window metrics.
* **`BaseRdpPath`**: `[string]` Path to the baseline `.rdp` file configuration. Defaults to `ticket_highest_speed.rdp`.
* **`OutputCsvPath`**: `[string]` Path where the resulting spreadsheet will be saved. Defaults to a timestamped file name.
* **`TargetAddress`**: `[string]` Remote address/IP overrides in the generated probe targets.
* **`SingleCase`**: `[switch]` Run a custom localized configuration rather than running the full matrix sweep.
* **`SmartSizing`**: `[int]` Single-case configuration for Smart Sizing (`0` or `1`). Defaults to `0`.
* **`WinposShowCmd`**: `[int]` Single-case window mode visibility parameter (`1` for normal window, `3` for maximized). Defaults to `1`.
* **`WinposSize`**: `[string]` Single-case initial window geometry specification in `WxH` format (e.g. `'800x600'`). Defaults to `'800x600'`.
* **`SmartSize125`**: `[string]` Single-case post-launch scaling override (`'yes'` or `'no'`). Defaults to `'no'`.
* **`SmartSizingValues`**: `[int[]]` Array of Smart Sizing choices for full-sweep matrices. Defaults to `@(0, 1)`.
* **`WinposShowCmdValues`**: `[int[]]` Array of `WinposShowCmd` configuration values to iterate. Defaults to `@(1, 3)`.
* **`WinposSizes`**: `[string[]]` Array of resolutions (`WxH`) to iterate in sweeps. Defaults to `@('800x600', '1600x1200')`.
* **`SmartSize125Values`**: `[string[]]` Array of post-launch window scale factors to iterate. Defaults to `@('no', 'yes')`.
* **`SettleMilliseconds`**: `[int]` Duration in milliseconds to wait for the window state to settle after post-launch window scaling. Defaults to `2000`.
* **`ListOnly`**: `[switch]` Display the matrix sweep plans to the terminal and exit. Does not invoke MSTSC instances.
* **`KeepTempFiles`**: `[switch]` Retain temporary generated configuration `.rdp` scripts inside `TEMP/rdp_window_probe`.

### `resize_open_mstsc.ps1`
Diagnostics harness to locate and programmatically scale active connections.
* **`Scale`**: `[double]` Dynamic sizing multiplier (e.g. `1.25`).
* **`WindowClass`**: `[string]` Windows class name targeting the active session frame. Defaults to `'TscShellContainerClass'`.

### `set_rdp_warning.ps1`
Manages system warnings prompts.
* **`Action`**: `[string]` Accepts `'enabled'` (restores warnings) or `'disabled'` (suppresses warnings). Defaults to displaying current status only.

## Templates & Outputs

* **[ticket_highest_speed.rdp](ticket_highest_speed.rdp)**: The default baseline RDP configuration file.
* **[ticket_barest_still_asks_webauthn.rdp](ticket_barest_still_asks_webauthn.rdp)**: Alternate configuration testing bare security footprints and web authentication.
* **CSV Logging**: Result logs (e.g. `rdp-window-probe-*.csv`) capturing Target IP, Host Windows Version, SmartSizing, dimensions (`OuterWidth`/`OuterHeight`/`ClientWidth`/`ClientHeight`), and window status or exceptions encountered.

## Usage

### 1. Configure warning suppression (Optional)
To avoid manual interactions and allow automation to execute cleanly, run the elevated warning suppression utility:
```powershell
.\set_rdp_warning.ps1 disabled
```

### 2. Running a series of probes
Execute the probe script to test a batch of configurations:
```powershell
.\rdp_window_probe.ps1 -TargetAddress "your.remote.host.ip"
```
Or list the test scenarios without initiating connections:
```powershell
.\rdp_window_probe.ps1 -ListOnly
```
