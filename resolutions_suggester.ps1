param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Args0
)

$MaxZoom = 2

# Parse arguments: resolutions_suggester.ps1 [-r WxH|W|WxN:D] [--help] [paths...]
$rdpWidth = 800
$rdpHeight = 600
$pathArgs = @()
$testMonitor = $null
$testModes = $null
$argIndex = 0

while ($argIndex -lt $Args0.Count) {
    $arg = $Args0[$argIndex]
    if ($arg -eq '--help' -or $arg -eq '-h') {
        Write-Host "Usage: resolutions_suggester.ps1 [-r WxH|W|WxN:D] [paths...]"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  --resolution, -r  RDP resolution (default: 800x600)"
        Write-Host "                    WxH       explicit (e.g. 800x600, 1280x1024)"
        Write-Host "                    W         width-only, height from monitor aspect ratio (e.g. 1280)"
        Write-Host "                    WxN:D     width with aspect ratio (e.g. 1280x4:3)"
        Write-Host "  --help, -h            Show this help"
        Write-Host ""
        Write-Host "Arguments:"
        Write-Host "  paths              .rdp files or directories containing .rdp files"
        Write-Host "                     When provided, enables interactive mode to update"
        Write-Host "                     winposstr and resolution settings in the .rdp file"
        return
    }
    elseif (($arg -eq '--resolution' -or $arg -eq '-r') -and ($argIndex + 1 -ge $Args0.Count -or $Args0[$argIndex + 1].StartsWith('-'))) {
        $commonResolutions = @(
            @{ W = 800;  H = 600;  Ratio = '4:3';   Name = 'SVGA' }
            @{ W = 1024; H = 768;  Ratio = '4:3';   Name = 'XGA' }
            @{ W = 1280; H = 720;  Ratio = '16:9';  Name = 'HD' }
            @{ W = 1280; H = 800;  Ratio = '16:10'; Name = 'WXGA' }
            @{ W = 1280; H = 1024; Ratio = '5:4';   Name = 'SXGA' }
            @{ W = 1366; H = 768;  Ratio = '~16:9'; Name = 'HD' }
            @{ W = 1440; H = 900;  Ratio = '16:10'; Name = 'WXGA+' }
            @{ W = 1600; H = 900;  Ratio = '16:9';  Name = 'HD+' }
            @{ W = 1680; H = 1050; Ratio = '16:10'; Name = 'WSXGA+' }
            @{ W = 1600; H = 1200; Ratio = '4:3';   Name = 'UXGA' }
            @{ W = 1920; H = 1080; Ratio = '16:9';  Name = 'FHD' }
            @{ W = 1920; H = 1200; Ratio = '16:10'; Name = 'WUXGA' }
            @{ W = 2560; H = 1080; Ratio = '~21:9'; Name = 'UWFHD' }
            @{ W = 2560; H = 1440; Ratio = '16:9';  Name = 'QHD' }
            @{ W = 2560; H = 1600; Ratio = '16:10'; Name = 'WQXGA' }
        )
        Write-Host "Common resolutions:"
        for ($resIndex = 0; $resIndex -lt $commonResolutions.Count; $resIndex++) {
            $resItem = $commonResolutions[$resIndex]
            $num = ($resIndex + 1).ToString().PadLeft(2)
            $heightStr = "$($resItem.W)x$($resItem.H)"
            $ratioStr = $resItem.Ratio
            Write-Host "  $num. $($heightStr.PadRight(10)) $($ratioStr.PadRight(6)) $($resItem.Name)"
        }
        Write-Host "Select resolution: " -NoNewline
        $resChoice = [Console]::In.ReadLine()
        $resNum = 0
        if (-not [int]::TryParse($resChoice, [ref]$resNum) -or $resNum -lt 1 -or $resNum -gt $commonResolutions.Count) {
            Write-Host "Invalid selection."
            exit 1
        }
        $rdpWidth = $commonResolutions[$resNum - 1].W
        $rdpHeight = $commonResolutions[$resNum - 1].H
    }
    elseif ($arg -eq '--resolution' -or $arg -eq '-r') {
        $argIndex++
        $parts = $Args0[$argIndex] -split 'x'
        if ($parts.Count -eq 1) {
            $widthVal = 0
            if ([int]::TryParse($parts[0], [ref]$widthVal)) {
                $rdpWidth = $widthVal
                $rdpHeight = 0  # derive from monitor aspect ratio after detection
            }
            else {
                Write-Host "Invalid resolution format. Use WxH, W, or WxN:D (e.g. 800x600, 1280, 1280x4:3)."
                exit 1
            }
        }
        elseif ($parts.Count -eq 2 -and $parts[1].Contains(':')) {
            $widthVal = 0
            if (-not [int]::TryParse($parts[0], [ref]$widthVal)) {
                Write-Host "Invalid resolution format. Use WxH, W, or WxN:D (e.g. 800x600, 1280, 1280x4:3)."
                exit 1
            }
            $rdpWidth = $widthVal
            $ratioParts = $parts[1] -split ':'
            $ratioW = 0
            $ratioH = 0
            if ($ratioParts.Count -eq 2 -and [int]::TryParse($ratioParts[0], [ref]$ratioW) -and [int]::TryParse($ratioParts[1], [ref]$ratioH) -and $ratioW -gt 0 -and $ratioH -gt 0) {
                $rdpHeight = [int]($rdpWidth * $ratioH / $ratioW)
            }
            else {
                Write-Host "Invalid aspect ratio. Use N:D (e.g. 16:9, 4:3)."
                exit 1
            }
        }
        elseif ($parts.Count -eq 2) {
            $wVal = 0
            $hVal = 0
            if ([int]::TryParse($parts[0], [ref]$wVal) -and [int]::TryParse($parts[1], [ref]$hVal)) {
                $rdpWidth = $wVal
                $rdpHeight = $hVal
            }
            else {
                Write-Host "Invalid resolution format. Use WxH, W, or WxN:D (e.g. 800x600, 1280, 1280x4:3)."
                exit 1
            }
        }
        else {
            Write-Host "Invalid resolution format. Use WxH, W, or WxN:D (e.g. 800x600, 1280, 1280x4:3)."
            return
        }
    }
    elseif ($arg -eq '--test-monitor' -and $argIndex + 1 -lt $Args0.Count) {
        $argIndex++
        $testMonitor = $Args0[$argIndex]
    }
    elseif ($arg -eq '--test-modes' -and $argIndex + 1 -lt $Args0.Count) {
        $argIndex++
        $testModes = $Args0[$argIndex]
    }
    else {
        $pathArgs += $arg
    }
    $argIndex++
}

# Resolve .rdp file paths
$rdpPaths = @()
foreach ($pathArg in $pathArgs) {
    $resolved = [System.IO.Path]::GetFullPath($pathArg)
    if (Test-Path $resolved -PathType Container) {
        $rdpPaths += @(Get-ChildItem $resolved -Filter '*.rdp' | Select-Object -ExpandProperty FullName)
    } else {
        $rdpPaths += $resolved
    }
}

function Get-Gcd([int]$a, [int]$b) { while ($b -ne 0) { $t = $b; $b = $a % $b; $a = $t } return $a }

if ($testMonitor) {
    # Parse --test-monitor: WxH@FHz@Ddpi (e.g. 2560x1440@60Hz@96dpi)
    if ($testMonitor -notmatch '^(\d+)x(\d+)@(\d+)Hz@(\d+)dpi$') {
        Write-Host "Invalid --test-monitor format. Use WxH@FHz@Ddpi (e.g. 2560x1440@60Hz@96dpi)."
        exit 1
    }
    $currentWidth = [int]$Matches[1]
    $currentHeight = [int]$Matches[2]
    $currentFrequency = [int]$Matches[3]
    $dpiX = [int]$Matches[4]
    $dpiScale = $dpiX / 96.0
    $chromeWidth = 14.0 * $dpiScale
    $chromeHeight = (55.0 / 1.5) * $dpiScale
    $minimumHeight = [int][Math]::Ceiling($rdpHeight + $chromeHeight)
    $monitorNumber = "#0"

    $ratioGcd = Get-Gcd $currentWidth $currentHeight
    $currentRatioDisplay = "$($currentWidth / $ratioGcd):$($currentHeight / $ratioGcd)"
    $currentRatio = [double]$currentWidth / $currentHeight

    if (-not $testModes) {
        Write-Host "--test-modes is required when --test-monitor is used."
        exit 1
    }

    # Parse --test-modes and filter
    $seen = @{}
    $modes = @()
    foreach ($modeStr in $testModes.Split(',')) {
        if ($modeStr -notmatch '^(\d+)x(\d+)(?:@(\d+)Hz)?$') {
            Write-Host "Invalid mode in --test-modes: $modeStr. Use WxH or WxH@FHz."
            exit 1
        }
        $modeW = [int]$Matches[1]
        $modeH = [int]$Matches[2]
        $modeFreq = if ($Matches[3]) { [int]$Matches[3] } else { $currentFrequency }

        if ($modeFreq -eq $currentFrequency -and $modeH -ge $minimumHeight -and $modeH -gt 0) {
            $ratio = [double]$modeW / $modeH
            if ([Math]::Abs($ratio - $currentRatio) -lt 0.001) {
                $key = "${modeW}x${modeH}"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $modes += @{ Width = $modeW; Height = $modeH }
                }
            }
        }
    }

    # Derive height from monitor aspect ratio when only width was specified
    if ($rdpHeight -eq 0) {
        $rdpHeight = [int][Math]::Round($rdpWidth / $currentRatio)
        $minimumHeight = [int][Math]::Ceiling($rdpHeight + $chromeHeight)

        # Re-filter modes with updated minimumHeight
        $filteredModes = @()
        foreach ($mode in $modes) {
            if ($mode.Height -ge $minimumHeight) {
                $filteredModes += $mode
            }
        }
        $modes = $filteredModes
    }

    # Compute scenarios for each mode
    $computed = @()
    foreach ($mode in $modes) {
        $zoom = [Math]::Min([int][Math]::Floor(($mode.Height - $chromeHeight) / $rdpHeight), $MaxZoom)
        $winWidth = $rdpWidth * $zoom + $chromeWidth
        $winHeight = $rdpHeight * $zoom + $chromeHeight
        $widthUsage = [int][Math]::Round($winWidth / $mode.Width * 100)
        $widthUsageTwo = [int][Math]::Round(2 * $winWidth / $mode.Width * 100)
        $heightUsage = [int][Math]::Round($winHeight / $mode.Height * 100)
        $areaOne = [int][Math]::Truncate($widthUsage * $heightUsage / 100)
        $areaTwo = [int][Math]::Truncate([Math]::Min($widthUsageTwo, 100) * $heightUsage / 100)

        $computed += [PSCustomObject]@{
            Width = $mode.Width
            Height = $mode.Height
            ZoomFactor = $zoom
            WidthUsage = $widthUsage
            WidthUsageTwo = $widthUsageTwo
            HeightUsage = $heightUsage
            AreaOnePercent = $areaOne
            AreaTwoPercent = $areaTwo
            IsCurrent = ($mode.Width -eq $currentWidth -and $mode.Height -eq $currentHeight)
        }
    }

    $result = [PSCustomObject]@{
        MonitorNumber = $monitorNumber
        CurrentWidth = $currentWidth
        CurrentHeight = $currentHeight
        CurrentRatioDisplay = $currentRatioDisplay
        CurrentRatio = $currentRatio
        DpiScale = $dpiScale
        CurrentFrequency = $currentFrequency
        ChromeWidth = $chromeWidth
        ChromeHeight = $chromeHeight
        RdpWidth = $rdpWidth
        RdpHeight = $rdpHeight
        Computed = $computed
    }
}
else {

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
        public double CurrentRatio;
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

        int currentFrequency = currentSettings.dmDisplayFrequency;
        int currentWidth = currentSettings.dmPelsWidth;
        int currentHeight = currentSettings.dmPelsHeight;
        int ratioGcd = Gcd(currentWidth, currentHeight);
        string currentRatioDisplay = (currentWidth / ratioGcd) + ":" + (currentHeight / ratioGcd);
        double currentRatio = (double)currentWidth / currentHeight;

        // Derive height from monitor aspect ratio when only width was specified
        if (rdp_height == 0)
        {
            rdp_height = (int)Math.Round(rdp_width / currentRatio);
        }

        int minimum_height = (int)Math.Ceiling(rdp_height + chromeHeight);

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

        int max_zoom = 2;
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
            CurrentRatio = currentRatio,
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
    exit 1
}

} # end else (real monitor P/Invoke path)

# Update rdpWidth/rdpHeight in case they were derived from monitor aspect ratio
$rdpWidth = $result.RdpWidth
$rdpHeight = $result.RdpHeight

# Display current monitor info
$dpiPercent = ($result.DpiScale * 100).ToString("F0")
Write-Host "Current Monitor $($result.MonitorNumber), $($result.CurrentWidth)x$($result.CurrentHeight), Ratio: $($result.CurrentRatioDisplay), Frequency: $($result.CurrentFrequency)Hz, DPI Scale $dpiPercent%"

# Display winposstr reference for current resolution at each zoom level
$rdpLabel = "RDP ${rdpWidth}x${rdpHeight}"
for ($zoom = 1; $zoom -le $MaxZoom; $zoom++) {
    $winW = [Math]::Ceiling($rdpWidth * $zoom + $result.ChromeWidth)
    $winH = [Math]::Ceiling($rdpHeight * $zoom + $result.ChromeHeight)
    $x1 = $result.CurrentWidth - 1
    $x0 = $x1 - $winW
    Write-Host "$rdpLabel $($zoom * 100)% rdp zoom: winposstr:s:0,1,0,0,$winW,$winH  2nd: winposstr:s:0,1,$x0,0,$x1,$winH"
}

$interactive = $rdpPaths.Count -gt 0
$scenarios = @()
$scenarioNumber = 1

# Display 1-window scenarios sorted by area
$oneWindowSorted = @($result.Computed | Sort-Object -Property AreaOnePercent -Descending)
Write-Host "`n--- Available resolutions for 1 $rdpLabel with same ratio and frequency sorted by area used ---"
foreach ($res in $oneWindowSorted) {
    $marker = if ($res.IsCurrent) { "*" } else { "" }
    $prefix = if ($interactive) { "  $scenarioNumber. " } else { "" }
    Write-Host "$prefix$marker$($res.Width)x$($res.Height), $($res.AreaOnePercent)% area ($($res.WidthUsage)% width, $($res.HeightUsage)% height), $($res.ZoomFactor * 100)% rdp zoom"
    $scenarios += @{ Resolution = $res; Type = '1-window' }
    $scenarioNumber++
}

# Display 2-window scenarios sorted by area
$twoWindowSorted = @($result.Computed | Sort-Object -Property AreaTwoPercent -Descending)
Write-Host "`n--- Available resolutions for 2 $rdpLabel with same ratio and frequency sorted by area used ---"
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
    exit 1
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
        exit 1
    }
    $targetPath = $rdpPaths[$rdpChoiceNum - 1]
}

# Ask left or right
Write-Host "Left or Right? (L/R): " -NoNewline
$side = [Console]::In.ReadLine().Trim().ToUpper()
if ($side -ne 'L' -and $side -ne 'R') {
    Write-Host "Invalid selection."
    exit 1
}

# Compute winposstr for the selected resolution and position
$winW = [int][Math]::Ceiling($rdpWidth * $selectedRes.ZoomFactor + $result.ChromeWidth)
$winH = [int][Math]::Ceiling($rdpHeight * $selectedRes.ZoomFactor + $result.ChromeHeight)
if ($side -eq 'L') {
    $winposstr = "winposstr:s:0,1,0,0,$winW,$winH"
} else {
    $x1 = $selectedRes.Width - 1
    $x0 = $x1 - $winW
    $winposstr = "winposstr:s:0,1,$x0,0,$x1,$winH"
}

# Update the .rdp file, ensuring all documented settings are present
if (-not (Test-Path $targetPath)) {
    Write-Host "File not found: $targetPath"
    exit 1
}
$lines = @(Get-Content $targetPath -Encoding Unicode)

$requiredSettings = @(
    @{ Key = 'smart sizing'; Value = 'smart sizing:i:0' }
    @{ Key = 'allow font smoothing'; Value = 'allow font smoothing:i:1' }
    @{ Key = 'desktopwidth'; Value = "desktopwidth:i:${rdpWidth}" }
    @{ Key = 'desktopheight'; Value = "desktopheight:i:${rdpHeight}" }
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
