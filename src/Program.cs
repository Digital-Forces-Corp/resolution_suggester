using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

const int MaxZoom = 2;
const double ChromeWidth96Dpi = 14.0;
const double ChromeHeight96Dpi = 55.0 / 1.5;
const double RatioTolerance = 0.001;
const int ENUM_CURRENT_SETTINGS = -1;
const int MDT_EFFECTIVE_DPI = 0;
const int PROCESS_PER_MONITOR_DPI_AWARE = 2;
const int MaxRdpDimension = 8192;
const uint MONITOR_DEFAULTTONEAREST = 2;

// Parse arguments: resolution_suggester [--rdp-resolution WxH] [paths...]
int rdpWidth = 800;
int rdpHeight = 600;
var pathArgs = new List<string>();
string? testMonitor = null;
string? testModes = null;

for (int argIndex = 0; argIndex < args.Length; argIndex++)
{
    if (args[argIndex] == "--help" || args[argIndex] == "-h")
    {
        Console.WriteLine("Usage: resolution_suggester [-r WxH|W|WxN:D] [paths...]");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --rdp-resolution, -r  RDP resolution (default: 800x600)");
        Console.WriteLine("                    WxH       explicit (e.g. 800x600, 1280x1024)");
        Console.WriteLine("                    W         width-only, height from monitor aspect ratio (e.g. 1280)");
        Console.WriteLine("                    WxN:D     width with aspect ratio (e.g. 1280x4:3)");
        Console.WriteLine("  --help, -h            Show this help");
        Console.WriteLine();
        Console.WriteLine("Arguments:");
        Console.WriteLine("  paths              .rdp files or directories containing .rdp files");
        Console.WriteLine("                     When provided, enables interactive mode to update");
        Console.WriteLine("                     winposstr and RDP resolution settings in the .rdp file");
        return 0;
    }
    else if ((args[argIndex] == "--rdp-resolution" || args[argIndex] == "-r") && (argIndex + 1 >= args.Length || args[argIndex + 1].StartsWith("--") || args[argIndex + 1] == "-h"))
    {
        var commonRdpResolutions = new (int W, int H, string Ratio, string Name)[]
        {
            (800,  600,  "4:3",   "SVGA"),
            (1024, 768,  "4:3",   "XGA"),
            (1280, 720,  "16:9",  "HD"),
            (1280, 800,  "16:10", "WXGA"),
            (1280, 1024, "5:4",   "SXGA"),
            (1366, 768,  "~16:9", "HD"),
            (1440, 900,  "16:10", "WXGA+"),
            (1600, 900,  "16:9",  "HD+"),
            (1680, 1050, "16:10", "WSXGA+"),
            (1600, 1200, "4:3",   "UXGA"),
            (1920, 1080, "16:9",  "FHD"),
            (1920, 1200, "16:10", "WUXGA"),
            (2560, 1080, "~21:9", "UWFHD"),
            (2560, 1440, "16:9",  "QHD"),
            (2560, 1600, "16:10", "WQXGA"),
        };
        Console.WriteLine("Common resolutions:");
        for (int i = 0; i < commonRdpResolutions.Length; i++)
        {
            var r = commonRdpResolutions[i];
            Console.WriteLine($"  {i + 1,2}. {r.W}x{r.H,-5} {r.Ratio,-5}  {r.Name}");
        }
        Console.Write("Select RDP resolution: ");
        string? resChoice = Console.ReadLine();
        if (!int.TryParse(resChoice, out int resNum) || resNum < 1 || resNum > commonRdpResolutions.Length)
        {
            Console.WriteLine("Invalid selection.");
            return 1;
        }
        rdpWidth = commonRdpResolutions[resNum - 1].W;
        rdpHeight = commonRdpResolutions[resNum - 1].H;
    }
    else if (args[argIndex] == "--rdp-resolution" || args[argIndex] == "-r")
    {
        argIndex++;
        string[] parts = args[argIndex].Split('x');
        if (parts.Length == 1 && int.TryParse(parts[0], out rdpWidth))
        {
            if (rdpWidth <= 0)
            {
                Console.WriteLine("RDP width must be a positive integer.");
                return 1;
            }
            if (rdpWidth > MaxRdpDimension)
            {
                Console.WriteLine($"RDP width exceeds maximum of {MaxRdpDimension}.");
                return 1;
            }
            rdpHeight = 0; // derive from monitor aspect ratio after detection
        }
        else if (parts.Length == 2 && int.TryParse(parts[0], out rdpWidth) && parts[1].Contains(':'))
        {
            // WxN:D format: width with explicit aspect ratio (e.g. 1280x4:3)
            if (rdpWidth <= 0)
            {
                Console.WriteLine("RDP width must be a positive integer.");
                return 1;
            }
            string[] ratioParts = parts[1].Split(':');
            if (ratioParts.Length == 2 && int.TryParse(ratioParts[0], out int ratioW) && int.TryParse(ratioParts[1], out int ratioH) && ratioW > 0 && ratioH > 0)
            {
                rdpHeight = (int)((long)rdpWidth * ratioH / ratioW);
            }
            else
            {
                Console.WriteLine("Invalid aspect ratio. Use N:D (e.g. 16:9, 4:3).");
                return 1;
            }
            if (rdpWidth <= 0 || rdpHeight <= 0)
            {
                Console.WriteLine("RDP width and height must be positive integers.");
                return 1;
            }
            if (rdpWidth > MaxRdpDimension || rdpHeight > MaxRdpDimension)
            {
                Console.WriteLine($"RDP dimensions exceed maximum of {MaxRdpDimension}x{MaxRdpDimension}.");
                return 1;
            }
        }
        else if (parts.Length != 2 || !int.TryParse(parts[0], out rdpWidth) || !int.TryParse(parts[1], out rdpHeight))
        {
            Console.WriteLine("Invalid RDP resolution format. Use WxH, W, or WxN:D (e.g. 800x600, 1280, 1280x4:3).");
            return 1;
        }
        else if (rdpWidth <= 0 || rdpHeight <= 0)
        {
            Console.WriteLine("RDP width and height must be positive integers.");
            return 1;
        }
        else if (rdpWidth > MaxRdpDimension || rdpHeight > MaxRdpDimension)
        {
            Console.WriteLine($"RDP dimensions exceed maximum of {MaxRdpDimension}x{MaxRdpDimension}.");
            return 1;
        }
    }
    else if (args[argIndex] == "--test-monitor" && argIndex + 1 < args.Length)
    {
        argIndex++;
        testMonitor = args[argIndex];
    }
    else if (args[argIndex] == "--test-modes" && argIndex + 1 < args.Length)
    {
        argIndex++;
        testModes = args[argIndex];
    }
    else
    {
        pathArgs.Add(args[argIndex]);
    }
}

// Resolve .rdp file paths
var rdpPaths = new List<string>();
foreach (string pathArg in pathArgs)
{
    string resolved = Path.GetFullPath(pathArg);
    if (Directory.Exists(resolved))
    {
        rdpPaths.AddRange(Directory.GetFiles(resolved, "*.rdp"));
    }
    else
    {
        rdpPaths.Add(resolved);
    }
}

// Detect monitor (or use synthetic data for testing)
string monitorNumber;
int currentWidth, currentHeight, currentFrequency;
double dpiScale, chromeWidth, chromeHeight;
double currentRatio;
int minimumHeight;
var seen = new HashSet<string>();
var modes = new List<(int Width, int Height)>();

if (testMonitor != null)
{
    // Parse --test-monitor: WxH@FHz@Ddpi (e.g. 2560x1440@60Hz@96dpi)
    var tmMatch = Regex.Match(testMonitor, @"^(\d+)x(\d+)@(\d+)Hz@(\d+)dpi$");
    if (!tmMatch.Success)
    {
        Console.WriteLine("Invalid --test-monitor format. Use WxH@FHz@Ddpi (e.g. 2560x1440@60Hz@96dpi).");
        return 1;
    }
    currentWidth = int.Parse(tmMatch.Groups[1].Value);
    currentHeight = int.Parse(tmMatch.Groups[2].Value);
    currentFrequency = int.Parse(tmMatch.Groups[3].Value);
    uint dpiX = uint.Parse(tmMatch.Groups[4].Value);
    if (dpiX == 0)
    {
        Console.WriteLine("DPI must be a positive integer.");
        return 1;
    }
    dpiScale = dpiX / 96.0;
    chromeWidth = ChromeWidth96Dpi * dpiScale;
    chromeHeight = ChromeHeight96Dpi * dpiScale;
    minimumHeight = (int)Math.Ceiling(rdpHeight + chromeHeight);
    monitorNumber = "#0";

    // Parse --test-modes: WxH,WxH@FHz,... (frequency defaults to currentFrequency if omitted)
    if (testModes == null)
    {
        Console.WriteLine("--test-modes is required when --test-monitor is used.");
        return 1;
    }
    currentRatio = (double)currentWidth / currentHeight;
    foreach (string modeStr in testModes.Split(','))
    {
        var modeMatch = Regex.Match(modeStr, @"^(\d+)x(\d+)(?:@(\d+)Hz)?$");
        if (!modeMatch.Success)
        {
            Console.WriteLine($"Invalid mode in --test-modes: {modeStr}. Use WxH or WxH@FHz.");
            return 1;
        }
        int modeW = int.Parse(modeMatch.Groups[1].Value);
        int modeH = int.Parse(modeMatch.Groups[2].Value);
        int modeFreq = modeMatch.Groups[3].Success ? int.Parse(modeMatch.Groups[3].Value) : currentFrequency;

        if (ModeMatchesFilter(modeW, modeH, modeFreq, currentFrequency, minimumHeight, currentRatio, RatioTolerance))
        {
            string key = $"{modeW}x{modeH}";
            if (seen.Add(key))
                modes.Add((modeW, modeH));
        }
    }
}
else
{
    int dpiAwarenessResult = NativeMethods.SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);
    if (dpiAwarenessResult != 0 && dpiAwarenessResult != unchecked((int)0x80070005)) // E_ACCESSDENIED = already set
    {
        Console.Error.WriteLine($"WARNING: SetProcessDpiAwareness failed with HRESULT 0x{dpiAwarenessResult:X8}.");
    }

    IntPtr monitorHandle = NativeMethods.MonitorFromPoint(new NativeMethods.POINT { x = 0, y = 1 }, MONITOR_DEFAULTTONEAREST);

    var monitorInfo = new NativeMethods.MONITORINFOEX();
    monitorInfo.cbSize = Marshal.SizeOf<NativeMethods.MONITORINFOEX>();
    if (!NativeMethods.GetMonitorInfo(monitorHandle, ref monitorInfo))
    {
        Console.WriteLine("ERROR: Failed to retrieve monitor info.");
        return 1;
    }

    string deviceName = monitorInfo.szDevice;
    monitorNumber = deviceName.Replace("\\\\.\\DISPLAY", "#");

    var currentSettings = new NativeMethods.DEVMODE();
    currentSettings.dmSize = (short)Marshal.SizeOf<NativeMethods.DEVMODE>();
    if (!NativeMethods.EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentSettings) || currentSettings.dmPelsHeight == 0)
    {
        Console.WriteLine($"ERROR: Failed to retrieve display settings for {deviceName}");
        return 1;
    }

    int dpiResult = NativeMethods.GetDpiForMonitor(monitorHandle, MDT_EFFECTIVE_DPI, out uint dpiX, out _);
    if (dpiResult != 0)
    {
        Console.WriteLine($"ERROR: GetDpiForMonitor failed with HRESULT 0x{dpiResult:X8}.");
        return 1;
    }
    dpiScale = dpiX / 96.0;
    chromeWidth = ChromeWidth96Dpi * dpiScale;
    chromeHeight = ChromeHeight96Dpi * dpiScale;
    minimumHeight = (int)Math.Ceiling(rdpHeight + chromeHeight);

    currentFrequency = currentSettings.dmDisplayFrequency;
    currentWidth = currentSettings.dmPelsWidth;
    currentHeight = currentSettings.dmPelsHeight;

    currentRatio = (double)currentWidth / currentHeight;
    var devMode = new NativeMethods.DEVMODE();
    devMode.dmSize = (short)Marshal.SizeOf<NativeMethods.DEVMODE>();
    int modeIndex = 0;
    while (NativeMethods.EnumDisplaySettings(deviceName, modeIndex, ref devMode))
    {
        if (ModeMatchesFilter(devMode.dmPelsWidth, devMode.dmPelsHeight, devMode.dmDisplayFrequency, currentFrequency, minimumHeight, currentRatio, RatioTolerance))
        {
            string key = $"{devMode.dmPelsWidth}x{devMode.dmPelsHeight}";
            if (seen.Add(key))
                modes.Add((devMode.dmPelsWidth, devMode.dmPelsHeight));
        }
        modeIndex++;
    }
}

if (currentWidth == 0 || currentHeight == 0)
{
    Console.WriteLine("ERROR: Monitor dimensions are zero.");
    return 1;
}

int ratioGcd = Gcd(currentWidth, currentHeight);
string currentRatioDisplay = $"{currentWidth / ratioGcd}:{currentHeight / ratioGcd}";

// Derive height from monitor aspect ratio when only width was specified
if (rdpHeight == 0)
{
    rdpHeight = (int)Math.Round(rdpWidth / currentRatio);
    minimumHeight = (int)Math.Ceiling(rdpHeight + chromeHeight);

    // Re-filter modes with updated minimumHeight
    var filteredModes = new List<(int Width, int Height)>();
    foreach (var mode in modes)
    {
        if (mode.Height >= minimumHeight)
            filteredModes.Add(mode);
    }
    modes = filteredModes;
}

// Compute monitor resolution options for each mode
var computed = new List<MonitorResolution>();
foreach (var mode in modes)
{
    int zoomFactor = Math.Min((int)Math.Floor((mode.Height - chromeHeight) / rdpHeight), MaxZoom);
    double windowWidth = rdpWidth * zoomFactor + chromeWidth;
    double windowHeight = rdpHeight * zoomFactor + chromeHeight;
    int widthUsage = (int)Math.Round(windowWidth / mode.Width * 100);
    int widthUsageTwo = (int)Math.Round(2 * windowWidth / mode.Width * 100);
    int heightUsage = (int)Math.Round(windowHeight / mode.Height * 100);
    int areaOne = Math.Min(widthUsage, 100) * heightUsage;
    int areaTwo = Math.Min(widthUsageTwo, 100) * heightUsage;

    computed.Add(new MonitorResolution
    {
        Width = mode.Width,
        Height = mode.Height,
        ZoomFactor = zoomFactor,
        WidthUsage = widthUsage,
        WidthUsageTwo = widthUsageTwo,
        HeightUsage = heightUsage,
        AreaOnePercent = (int)Math.Round(areaOne / 100.0),
        AreaTwoPercent = (int)Math.Round(areaTwo / 100.0),
        IsCurrent = mode.Width == currentWidth && mode.Height == currentHeight
    });
}

// Display current monitor info
string dpiPercent = (dpiScale * 100).ToString("F0");
Console.WriteLine($"Current Monitor {monitorNumber}, {currentWidth}x{currentHeight}, Ratio: {currentRatioDisplay}, Frequency: {currentFrequency}Hz, DPI Scale {dpiPercent}%");

// Display winposstr reference for current monitor resolution at each zoom level
string rdpLabel = $"RDP {rdpWidth}x{rdpHeight}";
for (int zoom = 1; zoom <= MaxZoom; zoom++)
{
    int winW = (int)Math.Ceiling(rdpWidth * zoom + chromeWidth);
    int winH = (int)Math.Ceiling(rdpHeight * zoom + chromeHeight);
    int x1 = currentWidth - 1;
    int x0 = x1 - winW;
    Console.WriteLine($"{rdpLabel} {zoom * 100}% rdp zoom: winposstr:s:0,1,0,0,{winW},{winH}  2nd: winposstr:s:0,1,{x0},0,{x1},{winH}");
}

bool interactive = rdpPaths.Count > 0;
var monitorResolutions = new List<MonitorResolution>();
int optionNumber = 1;

// Display 1-window options sorted by area
var oneWindowSorted = computed.OrderByDescending(r => r.AreaOnePercent).ToList();
Console.WriteLine($"\n--- Available monitor resolutions for 1 {rdpLabel} with same ratio and frequency sorted by area used ---");
PrintResolutionOptions(oneWindowSorted, ref optionNumber, interactive ? monitorResolutions : null, interactive, windowCount: 1);

// Display 2-window options sorted by area
var twoWindowSorted = computed.OrderByDescending(r => r.AreaTwoPercent).ToList();
Console.WriteLine($"\n--- Available monitor resolutions for 2 {rdpLabel} with same ratio and frequency sorted by area used ---");
PrintResolutionOptions(twoWindowSorted, ref optionNumber, interactive ? monitorResolutions : null, interactive, windowCount: 2);

if (!interactive)
    return 0;

// Interactive mode: select monitor resolution, rdp file, and position
Console.WriteLine();
Console.Write("Select monitor resolution: ");
string? choiceText = Console.ReadLine();
if (choiceText == null)
{
    Console.WriteLine("No input received.");
    return 1;
}
if (!int.TryParse(choiceText, out int choiceNum) || choiceNum < 1 || choiceNum > monitorResolutions.Count)
{
    Console.WriteLine("Invalid selection.");
    return 1;
}
var monitorResolutionSelected = monitorResolutions[choiceNum - 1];

// If multiple RDP files, ask which one
string targetPath = rdpPaths[0];
if (rdpPaths.Count > 1)
{
    Console.WriteLine();
    for (int rdpIndex = 0; rdpIndex < rdpPaths.Count; rdpIndex++)
    {
        Console.WriteLine($"  {rdpIndex + 1}. {rdpPaths[rdpIndex]}");
    }
    Console.Write("Select RDP file: ");
    string? rdpChoiceText = Console.ReadLine();
    if (rdpChoiceText == null)
    {
        Console.WriteLine("No input received.");
        return 1;
    }
    if (!int.TryParse(rdpChoiceText, out int rdpChoiceNum) || rdpChoiceNum < 1 || rdpChoiceNum > rdpPaths.Count)
    {
        Console.WriteLine("Invalid selection.");
        return 1;
    }
    targetPath = rdpPaths[rdpChoiceNum - 1];
}

// Ask left or right
Console.Write("Left or Right? (L/R): ");
string? side = Console.ReadLine()?.Trim().ToUpper();
if (side != "L" && side != "R")
{
    Console.WriteLine("Invalid selection.");
    return 1;
}

// Compute winposstr for the selected monitor resolution and position
int selectedWinW = (int)Math.Ceiling(rdpWidth * monitorResolutionSelected.ZoomFactor + chromeWidth);
int selectedWinH = (int)Math.Ceiling(rdpHeight * monitorResolutionSelected.ZoomFactor + chromeHeight);
string winposstr;
if (side == "L")
{
    winposstr = $"winposstr:s:0,1,0,0,{selectedWinW},{selectedWinH}";
}
else
{
    int sx1 = monitorResolutionSelected.Width - 1;
    int sx0 = Math.Max(0, sx1 - selectedWinW);
    winposstr = $"winposstr:s:0,1,{sx0},0,{sx1},{selectedWinH}";
}

// Update the .rdp file, ensuring all documented settings are present
List<string> lines;
try
{
    lines = File.ReadAllLines(targetPath, Encoding.Unicode).ToList();
}
catch (IOException ex)
{
    return PrintFileError(targetPath, ex);
}
catch (UnauthorizedAccessException ex)
{
    return PrintFileError(targetPath, ex);
}

var requiredSettings = new (string Key, string Value)[]
{
    ("smart sizing", "smart sizing:i:0"),
    ("allow font smoothing", "allow font smoothing:i:1"),
    ("desktopwidth", $"desktopwidth:i:{rdpWidth}"),
    ("desktopheight", $"desktopheight:i:{rdpHeight}"),
    ("winposstr", winposstr)
};

foreach (var setting in requiredSettings)
{
    string pattern = $"^{Regex.Escape(setting.Key)}:";
    int matchIndex = -1;
    for (int lineIndex = 0; lineIndex < lines.Count; lineIndex++)
    {
        if (Regex.IsMatch(lines[lineIndex], pattern))
        {
            matchIndex = lineIndex;
            break;
        }
    }
    if (matchIndex >= 0)
        lines[matchIndex] = setting.Value;
    else
        lines.Add(setting.Value);
}

try
{
    File.WriteAllLines(targetPath, lines, Encoding.Unicode);
}
catch (IOException ex)
{
    return PrintFileError(targetPath, ex);
}
catch (UnauthorizedAccessException ex)
{
    return PrintFileError(targetPath, ex);
}
Console.WriteLine($"Updated {targetPath} with {winposstr}");
return 0;

static void PrintResolutionOptions(List<MonitorResolution> sorted, ref int optionNumber, List<MonitorResolution>? monitorResolutions, bool interactive, int windowCount)
{
    foreach (var res in sorted)
    {
        string marker = res.IsCurrent ? "*" : "";
        string prefix = interactive ? $"  {optionNumber}. " : "";
        if (windowCount == 1)
        {
            Console.WriteLine($"{prefix}{marker}{res.Width}x{res.Height}, {res.AreaOnePercent}% area ({res.WidthUsage}% width, {res.HeightUsage}% height), {res.ZoomFactor * 100}% rdp zoom");
        }
        else
        {
            int widthCapped = Math.Min(res.WidthUsageTwo, 100);
            string overlapNote = res.WidthUsageTwo > 100 ? $", {res.WidthUsageTwo - 100}% overlap" : "";
            Console.WriteLine($"{prefix}{marker}{res.Width}x{res.Height}, {res.AreaTwoPercent}% area ({widthCapped}% width, {res.HeightUsage}% height{overlapNote}), {res.ZoomFactor * 100}% rdp zoom");
        }
        if (monitorResolutions != null)
        {
            monitorResolutions.Add(res);
            optionNumber++;
        }
    }
}

static int PrintFileError(string path, Exception ex)
{
    Console.WriteLine($"ERROR: Failed to access {path}: {ex.Message}");
    return 1;
}

static bool ModeMatchesFilter(int width, int height, int frequency, int targetFrequency, int minimumHeight, double targetRatio, double ratioTolerance)
{
    if (frequency != targetFrequency || height < minimumHeight || height <= 0 || width <= 0)
        return false;
    double ratio = (double)width / height;
    return Math.Abs(ratio - targetRatio) < ratioTolerance;
}

static int Gcd(int a, int b)
{
    while (b != 0) { int t = b; b = a % b; a = t; }
    return a;
}

class MonitorResolution
{
    public int Width { get; set; }
    public int Height { get; set; }
    public int ZoomFactor { get; set; }
    public int WidthUsage { get; set; }
    public int WidthUsageTwo { get; set; }
    public int HeightUsage { get; set; }
    public int AreaOnePercent { get; set; }
    public int AreaTwoPercent { get; set; }
    public bool IsCurrent { get; set; }
}

static class NativeMethods
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
}
