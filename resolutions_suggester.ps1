param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Paths,
    [string]$Resolution = '800x600'
)

$resolutionParts = $Resolution -split 'x'
if ($resolutionParts.Count -ne 2) {
    Write-Host "Invalid resolution format. Use WxH (e.g. 800x600, 1280x1024)."
    return
}
$rdpWidth = [int]$resolutionParts[0]
$rdpHeight = [int]$resolutionParts[1]

$rdpPaths = @()
if ($Paths) {
    foreach ($pathArg in $Paths) {
        $resolved = (Resolve-Path $pathArg).Path
        if (Test-Path $resolved -PathType Container) {
            $rdpPaths += @(Get-ChildItem $resolved -Filter '*.rdp' | Select-Object -ExpandProperty FullName)
        } else {
            $rdpPaths += $resolved
        }
    }
}

$source = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Linq;
public class DisplayResolutions
{
    [StructLayout(LayoutKind.Sequential)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public class ResolutionInfo
    {
        public int Width;
        public int Height;
        public int ZoomFactor;
        public int WidthUsage;
        public int WidthUsageTwo;
        public int HeightUsage;
        public int AreaOnePercent;
        public int AreaTwoPercent;
        public bool IsCurrent;
    }

    public class DisplayResult
    {
        public string MonitorNumber;
        public int CurrentWidth;
        public int CurrentHeight;
        public string CurrentRatioDisplay;
        public double DpiScale;
        public int CurrentFrequency;
        public double ChromeWidth;
        public double ChromeHeight;
        public int RdpWidth;
        public int RdpHeight;
        public List<ResolutionInfo> Computed;
        public string Error;
    }

    public struct RECT
    {
        public int left, top, right, bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int awareness);

    [DllImport("shcore.dll")]
    public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    static int Gcd(int a, int b) { while (b != 0) { int t = b; b = a % b; a = t; } return a; }

    const int max_zoom = 2;

    public static DisplayResult GetResolutionData(int rdp_width, int rdp_height)
    {
        double chrome_width_96dpi = 14.0;
        double chrome_height_96dpi = 55.0 / 1.5;
        DEVMODE devMode = new DEVMODE();
        DEVMODE currentSettings = new DEVMODE();
        int modeIndex = 0;
        HashSet<string> resolutions = new HashSet<string>();
        List<ResolutionInfo> resolutionList = new List<ResolutionInfo>();
        const int ENUM_CURRENT_SETTINGS = -1;

        SetProcessDpiAwareness(2); // PROCESS_PER_MONITOR_DPI_AWARE

        IntPtr consoleHandle = GetConsoleWindow();
        IntPtr monitorHandle = MonitorFromWindow(consoleHandle, 2); // MONITOR_DEFAULTTONEAREST

        MONITORINFOEX monitorInfo = new MONITORINFOEX();
        monitorInfo.cbSize = Marshal.SizeOf(monitorInfo);
        if (!GetMonitorInfo(monitorHandle, ref monitorInfo))
        {
            return new DisplayResult { Error = "ERROR: Failed to retrieve monitor info." };
        }

        string deviceName = monitorInfo.szDevice;
        string monitorNumber = deviceName.Replace("\\\\.\\DISPLAY", "#");

        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentSettings) || currentSettings.dmPelsHeight == 0)
        {
            return new DisplayResult { Error = "ERROR: Failed to retrieve display settings for " + deviceName };
        }

        uint dpiX, dpiY;
        GetDpiForMonitor(monitorHandle, 0, out dpiX, out dpiY); // MDT_EFFECTIVE_DPI
        double dpiScale = dpiX / 96.0;
        double chromeWidth = chrome_width_96dpi * dpiScale;
        double chromeHeight = chrome_height_96dpi * dpiScale;
        int minimum_height = (int)Math.Ceiling(rdp_height + chromeHeight);

        int currentFrequency = currentSettings.dmDisplayFrequency;
        int currentWidth = currentSettings.dmPelsWidth;
        int currentHeight = currentSettings.dmPelsHeight;
        int ratioGcd = Gcd(currentWidth, currentHeight);
        string currentRatioDisplay = (currentWidth / ratioGcd) + ":" + (currentHeight / ratioGcd);
        double currentRatio = (double)currentWidth / currentHeight;

        while (EnumDisplaySettings(deviceName, modeIndex, ref devMode))
        {
            if (devMode.dmDisplayFrequency == currentFrequency && devMode.dmPelsHeight >= minimum_height && devMode.dmPelsHeight > 0)
            {
                double ratio = (double)devMode.dmPelsWidth / devMode.dmPelsHeight;

                if (Math.Abs(ratio - currentRatio) < 0.001)
                {
                    string resolutionKey = devMode.dmPelsWidth + "x" + devMode.dmPelsHeight;
                    if (resolutions.Add(resolutionKey))
                    {
                        resolutionList.Add(new ResolutionInfo
                        {
                            Width = devMode.dmPelsWidth,
                            Height = devMode.dmPelsHeight
                        });
                    }
                }
            }
            modeIndex++;
        }

        var computed = new List<ResolutionInfo>();

        foreach (var resolution in resolutionList)
        {
            int zoomFactor = Math.Min((int)Math.Floor((resolution.Height - chromeHeight) / rdp_height), max_zoom);
            double windowWidth = rdp_width * zoomFactor + chromeWidth;
            double windowHeight = rdp_height * zoomFactor + chromeHeight;
            int widthUsage = (int)Math.Round(windowWidth / resolution.Width * 100);
            int widthUsageTwo = (int)Math.Round(2 * windowWidth / resolution.Width * 100);
            int heightUsage = (int)Math.Round(windowHeight / resolution.Height * 100);
            int areaOne = widthUsage * heightUsage;
            int areaTwo = Math.Min(widthUsageTwo, 100) * heightUsage;

            computed.Add(new ResolutionInfo
            {
                Width = resolution.Width,
                Height = resolution.Height,
                ZoomFactor = zoomFactor,
                WidthUsage = widthUsage,
                WidthUsageTwo = widthUsageTwo,
                HeightUsage = heightUsage,
                AreaOnePercent = areaOne / 100,
                AreaTwoPercent = areaTwo / 100,
                IsCurrent = (resolution.Width == currentWidth && resolution.Height == currentHeight)
            });
        }

        return new DisplayResult
        {
            MonitorNumber = monitorNumber,
            CurrentWidth = currentWidth,
            CurrentHeight = currentHeight,
            CurrentRatioDisplay = currentRatioDisplay,
            DpiScale = dpiScale,
            CurrentFrequency = currentFrequency,
            ChromeWidth = chromeWidth,
            ChromeHeight = chromeHeight,
            RdpWidth = rdp_width,
            RdpHeight = rdp_height,
            Computed = computed
        };
    }
}
"@

# Generate a type name unique to this version of the source code
$sourceHash = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($source)
    )
).Replace('-', '').Substring(0, 8)
$typeName = "DisplayResolutions_$sourceHash"
$source = $source.Replace('class DisplayResolutions', "class $typeName")

if (-not ($typeName -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies System.Linq, System.Collections, System.Drawing.Primitives, System.Console
}

$result = Invoke-Expression "[$typeName]::GetResolutionData($rdpWidth, $rdpHeight)"
if ($result.Error) {
    Write-Host $result.Error
    return
}

# Display current monitor info
$dpiPercent = ($result.DpiScale * 100).ToString("F0")
Write-Host "Current Monitor $($result.MonitorNumber), $($result.CurrentWidth)x$($result.CurrentHeight), Ratio: $($result.CurrentRatioDisplay), DPI Scale $dpiPercent%, Frequency: $($result.CurrentFrequency)Hz"

# Display winposstr reference for current resolution at each zoom level
$rdpLabel = "RDP $($result.RdpWidth)x$($result.RdpHeight)"
$maxZoom = Invoke-Expression "[$typeName]::max_zoom"
for ($zoom = 1; $zoom -le $maxZoom; $zoom++) {
    $winW = [Math]::Ceiling($result.RdpWidth * $zoom + $result.ChromeWidth)
    $winH = [Math]::Ceiling($result.RdpHeight * $zoom + $result.ChromeHeight)
    $x1 = $result.CurrentWidth - 1
    $x0 = $x1 - $winW
    Write-Host "$rdpLabel $($zoom * 100)% rdp zoom: winposstr:s:0,1,0,0,$winW,$winH  2nd: winposstr:s:0,1,$x0,0,$x1,$winH"
}

$interactive = $rdpPaths.Count -gt 0
$scenarios = @()
$scenarioNumber = 1

# Display 1-window scenarios sorted by area
$oneWindowSorted = @($result.Computed | Sort-Object -Property AreaOnePercent -Descending)
Write-Host "`n--- Best for 1 $rdpLabel window (sorted by area used) ---"
foreach ($res in $oneWindowSorted) {
    $marker = if ($res.IsCurrent) { "*" } else { "" }
    $prefix = if ($interactive) { "  $scenarioNumber. " } else { "" }
    Write-Host "$prefix$marker$($res.Width)x$($res.Height), $($res.AreaOnePercent)% area ($($res.WidthUsage)% width, $($res.HeightUsage)% height), $($res.ZoomFactor * 100)% rdp zoom"
    $scenarios += @{ Resolution = $res; Type = '1-window' }
    $scenarioNumber++
}

# Display 2-window scenarios sorted by area
$twoWindowSorted = @($result.Computed | Sort-Object -Property AreaTwoPercent -Descending)
Write-Host "`n--- Best for 2 $rdpLabel windows (sorted by area used) ---"
foreach ($res in $twoWindowSorted) {
    $marker = if ($res.IsCurrent) { "*" } else { "" }
    $widthCapped = [Math]::Min($res.WidthUsageTwo, 100)
    $overlapNote = if ($res.WidthUsageTwo -gt 100) { ", $($res.WidthUsageTwo - 100)% overlap" } else { "" }
    $prefix = if ($interactive) { "  $scenarioNumber. " } else { "" }
    Write-Host "$prefix$marker$($res.Width)x$($res.Height), $($res.AreaTwoPercent)% area ($widthCapped% width, $($res.HeightUsage)% height$overlapNote), $($res.ZoomFactor * 100)% rdp zoom"
    $scenarios += @{ Resolution = $res; Type = '2-window' }
    $scenarioNumber++
}

if (-not $interactive) {
    return
}

# Interactive mode: select scenario, rdp file, and position
Write-Host ""
Write-Host "Select scenario number: " -NoNewline
$choiceText = [Console]::In.ReadLine()
$choiceNum = 0
if (-not [int]::TryParse($choiceText, [ref]$choiceNum) -or $choiceNum -lt 1 -or $choiceNum -gt $scenarios.Count) {
    Write-Host "Invalid selection."
    return
}
$selected = $scenarios[$choiceNum - 1]
$selectedRes = $selected.Resolution

# If multiple RDP files, ask which one
$targetPath = $rdpPaths[0]
if ($rdpPaths.Count -gt 1) {
    Write-Host ""
    for ($rdpIndex = 0; $rdpIndex -lt $rdpPaths.Count; $rdpIndex++) {
        Write-Host "  $($rdpIndex + 1). $($rdpPaths[$rdpIndex])"
    }
    Write-Host "Select RDP file: " -NoNewline
    $rdpChoiceText = [Console]::In.ReadLine()
    $rdpChoiceNum = 0
    if (-not [int]::TryParse($rdpChoiceText, [ref]$rdpChoiceNum) -or $rdpChoiceNum -lt 1 -or $rdpChoiceNum -gt $rdpPaths.Count) {
        Write-Host "Invalid selection."
        return
    }
    $targetPath = $rdpPaths[$rdpChoiceNum - 1]
}

# Ask left or right
Write-Host "Left or Right? (L/R): " -NoNewline
$side = [Console]::In.ReadLine().Trim().ToUpper()
if ($side -ne 'L' -and $side -ne 'R') {
    Write-Host "Invalid selection."
    return
}

# Compute winposstr for the selected resolution and position
$winW = [int][Math]::Ceiling($result.RdpWidth * $selectedRes.ZoomFactor + $result.ChromeWidth)
$winH = [int][Math]::Ceiling($result.RdpHeight * $selectedRes.ZoomFactor + $result.ChromeHeight)
if ($side -eq 'L') {
    $winposstr = "winposstr:s:0,1,0,0,$winW,$winH"
} else {
    $x1 = $selectedRes.Width - 1
    $x0 = $x1 - $winW
    $winposstr = "winposstr:s:0,1,$x0,0,$x1,$winH"
}

# Update the .rdp file, ensuring all documented settings are present
$lines = @(Get-Content $targetPath -Encoding Unicode)

$requiredSettings = @(
    @{ Key = 'smart sizing'; Value = 'smart sizing:i:0' }
    @{ Key = 'allow font smoothing'; Value = 'allow font smoothing:i:1' }
    @{ Key = 'desktopwidth'; Value = "desktopwidth:i:$($result.RdpWidth)" }
    @{ Key = 'desktopheight'; Value = "desktopheight:i:$($result.RdpHeight)" }
    @{ Key = 'winposstr'; Value = $winposstr }
)

foreach ($setting in $requiredSettings) {
    $keyPattern = "^$([regex]::Escape($setting.Key)):"
    $matchIndex = -1
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        if ($lines[$lineIndex] -match $keyPattern) {
            $matchIndex = $lineIndex
            break
        }
    }
    if ($matchIndex -ge 0) {
        $lines[$matchIndex] = $setting.Value
    } else {
        $lines += $setting.Value
    }
}

$lines | Set-Content $targetPath -Encoding Unicode
Write-Host "Updated $targetPath with $winposstr"
