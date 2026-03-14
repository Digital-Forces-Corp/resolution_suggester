param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$InputArgs
)

$MaxZoom = 2
$ChromeHeightAt96Dpi = 55.0 / 1.5
$ChromeWidthAt96Dpi = 14.0
$RatioTolerance = 0.001
$MaxRdpDimension = 8192
$InvalidResolutionFormatMsg = "Invalid RDP resolution format. Use WxH, W, or WxN:D (e.g. 800x600, 1280, 1280x4:3)."

# Parse arguments: resolutions_suggester.ps1 [-r WxH|W|WxN:D] [--help] [paths...]
$rdpWidth = 800
$rdpHeight = 600
$pathArgs = @()
$testMonitor = $null
$testModes = $null
$argIndex = 0

while ($argIndex -lt $InputArgs.Count) {
    $arg = $InputArgs[$argIndex]
    if ($arg -eq '--help' -or $arg -eq '-h') {
        Write-Host "Usage: resolutions_suggester.ps1 [-r WxH|W|WxN:D] [paths...]"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  --rdp-resolution, -r  RDP resolution (default: 800x600)"
        Write-Host "                    WxH       explicit (e.g. 800x600, 1280x1024)"
        Write-Host "                    W         width-only, height from monitor aspect ratio (e.g. 1280)"
        Write-Host "                    WxN:D     width with aspect ratio (e.g. 1280x4:3)"
        Write-Host "  --help, -h            Show this help"
        Write-Host ""
        Write-Host "Arguments:"
        Write-Host "  paths              .rdp files or directories containing .rdp files"
        Write-Host "                     When provided, enables interactive mode to update"
        Write-Host "                     winposstr and RDP resolution settings in the .rdp file"
        return
    }
    elseif (($arg -eq '--rdp-resolution' -or $arg -eq '-r') -and (($argIndex + 1 -ge $InputArgs.Count) -or ($argIndex + 1 -lt $InputArgs.Count -and $InputArgs[$argIndex + 1].StartsWith('--')) -or ($argIndex + 1 -lt $InputArgs.Count -and $InputArgs[$argIndex + 1] -eq '-h'))) {
        $commonRdpResolutions = @(
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
        for ($resIndex = 0; $resIndex -lt $commonRdpResolutions.Count; $resIndex++) {
            $resItem = $commonRdpResolutions[$resIndex]
            $num = ($resIndex + 1).ToString().PadLeft(2)
            $resolutionStr = "$($resItem.W)x$($resItem.H)"
            $ratioStr = $resItem.Ratio
            Write-Host "  $num. $($resolutionStr.PadRight(10)) $($ratioStr.PadRight(6)) $($resItem.Name)"
        }
        Write-Host "Select RDP resolution: " -NoNewline
        $resChoice = [Console]::In.ReadLine()
        if ($null -eq $resChoice) {
            Write-Host "ERROR: No input received."
            exit 1
        }
        $resNum = 0
        if (-not [int]::TryParse($resChoice, [ref]$resNum) -or $resNum -lt 1 -or $resNum -gt $commonRdpResolutions.Count) {
            Write-Host "Invalid selection."
            exit 1
        }
        $rdpWidth = $commonRdpResolutions[$resNum - 1].W
        $rdpHeight = $commonRdpResolutions[$resNum - 1].H
    }
    elseif ($arg -eq '--rdp-resolution' -or $arg -eq '-r') {
        $argIndex++
        $parts = $InputArgs[$argIndex] -split 'x'
        if ($parts.Count -eq 1) {
            $widthVal = 0
            if ([int]::TryParse($parts[0], [ref]$widthVal)) {
                $rdpWidth = $widthVal
                if ($rdpWidth -le 0) {
                    Write-Host "RDP width must be a positive integer."
                    exit 1
                }
                if ($rdpWidth -gt $MaxRdpDimension) {
                    Write-Host "RDP width exceeds maximum of $MaxRdpDimension."
                    exit 1
                }
                $rdpHeight = 0  # derive from monitor aspect ratio after detection
            }
            else {
                Write-Host $InvalidResolutionFormatMsg
                exit 1
            }
        }
        elseif ($parts.Count -eq 2 -and $parts[1].Contains(':')) {
            $widthVal = 0
            if (-not [int]::TryParse($parts[0], [ref]$widthVal)) {
                Write-Host $InvalidResolutionFormatMsg
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
            if ($rdpWidth -le 0 -or $rdpHeight -le 0) {
                Write-Host "RDP width and height must be positive integers."
                exit 1
            }
            if ($rdpWidth -gt $MaxRdpDimension -or $rdpHeight -gt $MaxRdpDimension) {
                Write-Host "RDP dimensions exceed maximum of ${MaxRdpDimension}x${MaxRdpDimension}."
                exit 1
            }
        }
        elseif ($parts.Count -eq 2) {
            $wVal = 0
            $hVal = 0
            if ([int]::TryParse($parts[0], [ref]$wVal) -and [int]::TryParse($parts[1], [ref]$hVal)) {
                $rdpWidth = $wVal
                $rdpHeight = $hVal
                if ($rdpWidth -le 0 -or $rdpHeight -le 0) {
                    Write-Host "RDP width and height must be positive integers."
                    exit 1
                }
                if ($rdpWidth -gt $MaxRdpDimension -or $rdpHeight -gt $MaxRdpDimension) {
                    Write-Host "RDP dimensions exceed maximum of ${MaxRdpDimension}x${MaxRdpDimension}."
                    exit 1
                }
            }
            else {
                Write-Host $InvalidResolutionFormatMsg
                exit 1
            }
        }
        else {
            Write-Host $InvalidResolutionFormatMsg
            exit 1
        }
    }
    elseif ($arg -eq '--test-monitor' -and $argIndex + 1 -lt $InputArgs.Count) {
        $argIndex++
        $testMonitor = $InputArgs[$argIndex]
    }
    elseif ($arg -eq '--test-monitor') {
        Write-Host "--test-monitor requires a value (WxH@FHz@Ddpi)."
        exit 1
    }
    elseif ($arg -eq '--test-modes' -and $argIndex + 1 -lt $InputArgs.Count) {
        $argIndex++
        $testModes = $InputArgs[$argIndex]
    }
    elseif ($arg -eq '--test-modes') {
        Write-Host "--test-modes requires a value (WxH,WxH@FHz,...)."
        exit 1
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

function Get-FilteredModes([array]$Modes, [int]$TargetFrequency, [int]$MinimumHeight, [double]$TargetRatio, [double]$RatioToleranceParam) {
    $seen = @{}
    $filtered = @()
    foreach ($modeEntry in $Modes) {
        $modeW = $modeEntry.Width
        $modeH = $modeEntry.Height
        $modeFreq = $modeEntry.Frequency

        if ($modeFreq -eq $TargetFrequency -and $modeH -ge $MinimumHeight -and $modeH -gt 0) {
            $ratio = [double]$modeW / $modeH
            if ([Math]::Abs($ratio - $TargetRatio) -lt $RatioToleranceParam) {
                $key = "${modeW}x${modeH}"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $filtered += @{ Width = $modeW; Height = $modeH }
                }
            }
        }
    }
    return ,$filtered
}

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
    $chromeWidth = $ChromeWidthAt96Dpi * $dpiScale
    $chromeHeight = $ChromeHeightAt96Dpi * $dpiScale
    $minimumHeight = [int][Math]::Ceiling($rdpHeight + $chromeHeight)
    $monitorNumber = "#0"

    $ratioGcd = Get-Gcd $currentWidth $currentHeight
    $currentRatioDisplay = "$($currentWidth / $ratioGcd):$($currentHeight / $ratioGcd)"
    $currentRatio = [double]$currentWidth / $currentHeight

    if (-not $testModes) {
        Write-Host "--test-modes is required when --test-monitor is used."
        exit 1
    }

    # Parse --test-modes into mode entries with frequency
    $parsedModes = @()
    foreach ($modeStr in $testModes.Split(',')) {
        if ($modeStr -notmatch '^(\d+)x(\d+)(?:@(\d+)Hz)?$') {
            Write-Host "Invalid mode in --test-modes: $modeStr. Use WxH or WxH@FHz."
            exit 1
        }
        $modeW = [int]$Matches[1]
        $modeH = [int]$Matches[2]
        $modeFreq = if ($Matches[3]) { [int]$Matches[3] } else { $currentFrequency }

        $parsedModes += @{ Width = $modeW; Height = $modeH; Frequency = $modeFreq }
    }

    $modes = Get-FilteredModes -Modes $parsedModes -TargetFrequency $currentFrequency -MinimumHeight $minimumHeight -TargetRatio $currentRatio -RatioToleranceParam $RatioTolerance

    # Derive height from monitor aspect ratio when only width was specified
    if ($rdpHeight -eq 0) {
        if ($currentRatio -eq 0) { Write-Host "ERROR: Monitor reported zero height."; exit 1 }
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

    # Compute monitor resolution options for each mode
    $computed = @()
    foreach ($mode in $modes) {
        $zoom = [Math]::Min([int][Math]::Floor(($mode.Height - $chromeHeight) / $rdpHeight), $MaxZoom)
        if ($zoom -lt 1) { continue }
        $winWidth = $rdpWidth * $zoom + $chromeWidth
        $winHeight = $rdpHeight * $zoom + $chromeHeight
        $widthUsage = [int][Math]::Round($winWidth / $mode.Width * 100)
        $widthUsageTwo = [int][Math]::Round(2 * $winWidth / $mode.Width * 100)
        $heightUsage = [int][Math]::Round($winHeight / $mode.Height * 100)
        $areaOne = [Math]::Min($widthUsage, 100) * $heightUsage
        $areaTwo = [Math]::Min($widthUsageTwo, 100) * $heightUsage

        $computed += [PSCustomObject]@{
            Width = $mode.Width
            Height = $mode.Height
            ZoomFactor = $zoom
            WidthUsage = $widthUsage
            WidthUsageTwo = $widthUsageTwo
            HeightUsage = $heightUsage
            AreaOnePercent = [int][Math]::Round($areaOne / 100.0)
            AreaTwoPercent = [int][Math]::Round($areaTwo / 100.0)
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
public class MonitorResolutions
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

    public class MonitorResolution
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
        public List<MonitorResolution> Computed;
        public string Error;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int x;
        public int y;
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

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int awareness);

    [DllImport("shcore.dll")]
    public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    const double RatioTolerance = 0.001;

    static int Gcd(int a, int b) { while (b != 0) { int t = b; b = a % b; a = t; } return a; }

    public static DisplayResult GetMonitorData(int rdp_width, int rdp_height, int max_zoom, double chrome_width_96dpi, double chrome_height_96dpi)
    {
        DEVMODE devMode = new DEVMODE();
        devMode.dmSize = (short)Marshal.SizeOf(devMode);
        DEVMODE currentSettings = new DEVMODE();
        currentSettings.dmSize = (short)Marshal.SizeOf(currentSettings);
        int modeIndex = 0;
        HashSet<string> addedMonitorResolutions = new HashSet<string>();
        List<MonitorResolution> monitorResolutions = new List<MonitorResolution>();
        const int ENUM_CURRENT_SETTINGS = -1;

        int dpiAwarenessResult = SetProcessDpiAwareness(2); // PROCESS_PER_MONITOR_DPI_AWARE
        if (dpiAwarenessResult != 0 && dpiAwarenessResult != unchecked((int)0x80070005)) // E_ACCESSDENIED = already set
        {
            return new DisplayResult { Error = string.Format("WARNING: SetProcessDpiAwareness failed with HRESULT 0x{0:X8}.", dpiAwarenessResult) };
        }

        IntPtr monitorHandle = MonitorFromPoint(new POINT { x = 0, y = 1 }, 2); // MONITOR_DEFAULTTONEAREST

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
        int dpiResult = GetDpiForMonitor(monitorHandle, 0, out dpiX, out dpiY); // MDT_EFFECTIVE_DPI
        if (dpiResult != 0)
        {
            return new DisplayResult { Error = string.Format("ERROR: GetDpiForMonitor failed with HRESULT 0x{0:X8}.", dpiResult) };
        }
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

                if (Math.Abs(ratio - currentRatio) < RatioTolerance)
                {
                    string monitorResolutionKey = devMode.dmPelsWidth + "x" + devMode.dmPelsHeight;
                    if (addedMonitorResolutions.Add(monitorResolutionKey))
                    {
                        monitorResolutions.Add(new MonitorResolution
                        {
                            Width = devMode.dmPelsWidth,
                            Height = devMode.dmPelsHeight
                        });
                    }
                }
            }
            modeIndex++;
        }

        // max_zoom passed as parameter from $MaxZoom
        var computed = new List<MonitorResolution>();

        foreach (var monitorResolution in monitorResolutions)
        {
            int zoomFactor = Math.Min((int)Math.Floor((monitorResolution.Height - chromeHeight) / rdp_height), max_zoom);
            if (zoomFactor < 1) continue;
            double windowWidth = rdp_width * zoomFactor + chromeWidth;
            double windowHeight = rdp_height * zoomFactor + chromeHeight;
            int widthUsage = (int)Math.Round(windowWidth / monitorResolution.Width * 100);
            int widthUsageTwo = (int)Math.Round(2 * windowWidth / monitorResolution.Width * 100);
            int heightUsage = (int)Math.Round(windowHeight / monitorResolution.Height * 100);
            int areaOne = Math.Min(widthUsage, 100) * heightUsage;
            int areaTwo = Math.Min(widthUsageTwo, 100) * heightUsage;

            computed.Add(new MonitorResolution
            {
                Width = monitorResolution.Width,
                Height = monitorResolution.Height,
                ZoomFactor = zoomFactor,
                WidthUsage = widthUsage,
                WidthUsageTwo = widthUsageTwo,
                HeightUsage = heightUsage,
                AreaOnePercent = (int)Math.Round(areaOne / 100.0),
                AreaTwoPercent = (int)Math.Round(areaTwo / 100.0),
                IsCurrent = (monitorResolution.Width == currentWidth && monitorResolution.Height == currentHeight)
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
$typeName = "MonitorResolutions_$sourceHash"
$source = $source.Replace('class MonitorResolutions', "class $typeName")

if (-not ($typeName -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies System.Linq, System.Collections, System.Drawing.Primitives, System.Console
}

$type = $typeName -as [type]
if ($null -eq $type) { Write-Host "ERROR: Failed to load P/Invoke type '$typeName'."; exit 1 }
$result = $type::GetMonitorData($rdpWidth, $rdpHeight, $MaxZoom, $ChromeWidthAt96Dpi, $ChromeHeightAt96Dpi)
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

# Display winposstr reference for current monitor resolution at each zoom level
$rdpLabel = "RDP ${rdpWidth}x${rdpHeight}"
for ($zoom = 1; $zoom -le $MaxZoom; $zoom++) {
    $winW = [Math]::Ceiling($rdpWidth * $zoom + $result.ChromeWidth)
    $winH = [Math]::Ceiling($rdpHeight * $zoom + $result.ChromeHeight)
    $x1 = $result.CurrentWidth - 1
    $x0 = $x1 - $winW
    Write-Host "$rdpLabel $($zoom * 100)% rdp zoom: winposstr:s:0,1,0,0,$winW,$winH  2nd: winposstr:s:0,1,$x0,0,$x1,$winH"
}

$interactive = $rdpPaths.Count -gt 0
$monitorResolutions = @()
$optionNumber = 1

# Display 1-window options sorted by area
$oneWindowSorted = @($result.Computed | Sort-Object -Property AreaOnePercent -Descending)
Write-Host "`n--- Available monitor resolutions for 1 $rdpLabel with same ratio and frequency sorted by area used ---"
foreach ($res in $oneWindowSorted) {
    $marker = if ($res.IsCurrent) { "*" } else { "" }
    $prefix = if ($interactive) { "  $optionNumber. " } else { "" }
    Write-Host "$prefix$marker$($res.Width)x$($res.Height), $($res.AreaOnePercent)% area ($($res.WidthUsage)% width, $($res.HeightUsage)% height), $($res.ZoomFactor * 100)% rdp zoom"
    $monitorResolutions += $res
    $optionNumber++
}

# Display 2-window options sorted by area
$twoWindowSorted = @($result.Computed | Sort-Object -Property AreaTwoPercent -Descending)
Write-Host "`n--- Available monitor resolutions for 2 $rdpLabel with same ratio and frequency sorted by area used ---"
foreach ($res in $twoWindowSorted) {
    $marker = if ($res.IsCurrent) { "*" } else { "" }
    $widthCapped = [Math]::Min($res.WidthUsageTwo, 100)
    $overlapNote = if ($res.WidthUsageTwo -gt 100) { ", $($res.WidthUsageTwo - 100)% overlap" } else { "" }
    $prefix = if ($interactive) { "  $optionNumber. " } else { "" }
    Write-Host "$prefix$marker$($res.Width)x$($res.Height), $($res.AreaTwoPercent)% area ($widthCapped% width, $($res.HeightUsage)% height$overlapNote), $($res.ZoomFactor * 100)% rdp zoom"
    $monitorResolutions += $res
    $optionNumber++
}

if (-not $interactive) {
    return
}

# Interactive mode: select monitor resolution, rdp file, and position
Write-Host ""
Write-Host "Select monitor resolution: " -NoNewline
$choiceText = [Console]::In.ReadLine()
if ($null -eq $choiceText) {
    Write-Host "ERROR: No input received."
    exit 1
}
$choiceNum = 0
if (-not [int]::TryParse($choiceText, [ref]$choiceNum) -or $choiceNum -lt 1 -or $choiceNum -gt $monitorResolutions.Count) {
    Write-Host "Invalid selection."
    exit 1
}
$monitorResolutionSelected = $monitorResolutions[$choiceNum - 1]

# If multiple RDP files, ask which one
$targetPath = $rdpPaths[0]
if ($rdpPaths.Count -gt 1) {
    Write-Host ""
    for ($rdpIndex = 0; $rdpIndex -lt $rdpPaths.Count; $rdpIndex++) {
        Write-Host "  $($rdpIndex + 1). $($rdpPaths[$rdpIndex])"
    }
    Write-Host "Select RDP file: " -NoNewline
    $rdpChoiceText = [Console]::In.ReadLine()
    if ($null -eq $rdpChoiceText) {
        Write-Host "ERROR: No input received."
        exit 1
    }
    $rdpChoiceNum = 0
    if (-not [int]::TryParse($rdpChoiceText, [ref]$rdpChoiceNum) -or $rdpChoiceNum -lt 1 -or $rdpChoiceNum -gt $rdpPaths.Count) {
        Write-Host "Invalid selection."
        exit 1
    }
    $targetPath = $rdpPaths[$rdpChoiceNum - 1]
}

# Ask left or right
Write-Host "Left or Right? (L/R): " -NoNewline
$sideInput = [Console]::In.ReadLine()
$side = if ($null -eq $sideInput) { '' } else { $sideInput.Trim().ToUpper() }
if ($side -ne 'L' -and $side -ne 'R') {
    Write-Host "Invalid selection."
    exit 1
}

# Compute winposstr for the selected monitor resolution and position
$winW = [int][Math]::Ceiling($rdpWidth * $monitorResolutionSelected.ZoomFactor + $result.ChromeWidth)
$winH = [int][Math]::Ceiling($rdpHeight * $monitorResolutionSelected.ZoomFactor + $result.ChromeHeight)
if ($side -eq 'L') {
    $winposstr = "winposstr:s:0,1,0,0,$winW,$winH"
} else {
    $x1 = $monitorResolutionSelected.Width - 1
    $x0 = [Math]::Max(0, $x1 - $winW)
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

try {
    $lines | Set-Content $targetPath -Encoding Unicode
}
catch {
    Write-Host "ERROR: Failed to write ${targetPath}: $($_.Exception.Message)"
    exit 1
}
Write-Host "Updated $targetPath with $winposstr"
