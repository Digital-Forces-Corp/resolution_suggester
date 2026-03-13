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

// Parse arguments: resolution_suggester [--resolution WxH] [paths...]
int rdpWidth = 800;
int rdpHeight = 600;
var pathArgs = new List<string>();

for (int argIndex = 0; argIndex < args.Length; argIndex++)
{
    if (args[argIndex] == "--resolution" && argIndex + 1 < args.Length)
    {
        argIndex++;
        string[] parts = args[argIndex].Split('x');
        if (parts.Length != 2 || !int.TryParse(parts[0], out rdpWidth) || !int.TryParse(parts[1], out rdpHeight))
        {
            Console.WriteLine("Invalid resolution format. Use WxH (e.g. 800x600, 1280x1024).");
            return 1;
        }
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

// Detect monitor
NativeMethods.SetProcessDpiAwareness(2); // PROCESS_PER_MONITOR_DPI_AWARE

IntPtr consoleHandle = NativeMethods.GetConsoleWindow();
IntPtr monitorHandle = NativeMethods.MonitorFromWindow(consoleHandle, 2); // MONITOR_DEFAULTTONEAREST

var monitorInfo = new NativeMethods.MONITORINFOEX();
monitorInfo.cbSize = Marshal.SizeOf(monitorInfo);
if (!NativeMethods.GetMonitorInfo(monitorHandle, ref monitorInfo))
{
    Console.WriteLine("ERROR: Failed to retrieve monitor info.");
    return 1;
}

string deviceName = monitorInfo.szDevice;
string monitorNumber = deviceName.Replace("\\\\.\\DISPLAY", "#");

var currentSettings = new NativeMethods.DEVMODE();
if (!NativeMethods.EnumDisplaySettings(deviceName, -1, ref currentSettings) || currentSettings.dmPelsHeight == 0)
{
    Console.WriteLine($"ERROR: Failed to retrieve display settings for {deviceName}");
    return 1;
}

NativeMethods.GetDpiForMonitor(monitorHandle, 0, out uint dpiX, out _); // MDT_EFFECTIVE_DPI
double dpiScale = dpiX / 96.0;
double chromeWidth = ChromeWidth96Dpi * dpiScale;
double chromeHeight = ChromeHeight96Dpi * dpiScale;
int minimumHeight = (int)Math.Ceiling(rdpHeight + chromeHeight);

int currentFrequency = currentSettings.dmDisplayFrequency;
int currentWidth = currentSettings.dmPelsWidth;
int currentHeight = currentSettings.dmPelsHeight;
int ratioGcd = Gcd(currentWidth, currentHeight);
string currentRatioDisplay = $"{currentWidth / ratioGcd}:{currentHeight / ratioGcd}";
double currentRatio = (double)currentWidth / currentHeight;

// Enumerate available display modes
var seen = new HashSet<string>();
var modes = new List<(int Width, int Height)>();
var devMode = new NativeMethods.DEVMODE();
int modeIndex = 0;

while (NativeMethods.EnumDisplaySettings(deviceName, modeIndex, ref devMode))
{
    if (devMode.dmDisplayFrequency == currentFrequency && devMode.dmPelsHeight >= minimumHeight && devMode.dmPelsHeight > 0)
    {
        double ratio = (double)devMode.dmPelsWidth / devMode.dmPelsHeight;
        if (Math.Abs(ratio - currentRatio) < 0.001)
        {
            string key = $"{devMode.dmPelsWidth}x{devMode.dmPelsHeight}";
            if (seen.Add(key))
            {
                modes.Add((devMode.dmPelsWidth, devMode.dmPelsHeight));
            }
        }
    }
    modeIndex++;
}

// Compute scenarios for each mode
var computed = new List<ResolutionInfo>();
foreach (var mode in modes)
{
    int zoomFactor = Math.Min((int)Math.Floor((mode.Height - chromeHeight) / rdpHeight), MaxZoom);
    double windowWidth = rdpWidth * zoomFactor + chromeWidth;
    double windowHeight = rdpHeight * zoomFactor + chromeHeight;
    int widthUsage = (int)Math.Round(windowWidth / mode.Width * 100);
    int widthUsageTwo = (int)Math.Round(2 * windowWidth / mode.Width * 100);
    int heightUsage = (int)Math.Round(windowHeight / mode.Height * 100);
    int areaOne = widthUsage * heightUsage;
    int areaTwo = Math.Min(widthUsageTwo, 100) * heightUsage;

    computed.Add(new ResolutionInfo
    {
        Width = mode.Width,
        Height = mode.Height,
        ZoomFactor = zoomFactor,
        WidthUsage = widthUsage,
        WidthUsageTwo = widthUsageTwo,
        HeightUsage = heightUsage,
        AreaOnePercent = areaOne / 100,
        AreaTwoPercent = areaTwo / 100,
        IsCurrent = mode.Width == currentWidth && mode.Height == currentHeight
    });
}

// Display current monitor info
string dpiPercent = (dpiScale * 100).ToString("F0");
Console.WriteLine($"Current Monitor {monitorNumber}, {currentWidth}x{currentHeight}, Ratio: {currentRatioDisplay}, DPI Scale {dpiPercent}%, Frequency: {currentFrequency}Hz");

// Display winposstr reference for current resolution at each zoom level
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
var scenarios = new List<(ResolutionInfo Resolution, string Type)>();
int scenarioNumber = 1;

// Display 1-window scenarios sorted by area
var oneWindowSorted = computed.OrderByDescending(r => r.AreaOnePercent).ToList();
Console.WriteLine($"\n--- Best for 1 {rdpLabel} window (sorted by area used) ---");
foreach (var res in oneWindowSorted)
{
    string marker = res.IsCurrent ? "*" : "";
    string prefix = interactive ? $"  {scenarioNumber}. " : "";
    Console.WriteLine($"{prefix}{marker}{res.Width}x{res.Height}, {res.AreaOnePercent}% area ({res.WidthUsage}% width, {res.HeightUsage}% height), {res.ZoomFactor * 100}% rdp zoom");
    scenarios.Add((res, "1-window"));
    scenarioNumber++;
}

// Display 2-window scenarios sorted by area
var twoWindowSorted = computed.OrderByDescending(r => r.AreaTwoPercent).ToList();
Console.WriteLine($"\n--- Best for 2 {rdpLabel} windows (sorted by area used) ---");
foreach (var res in twoWindowSorted)
{
    string marker = res.IsCurrent ? "*" : "";
    int widthCapped = Math.Min(res.WidthUsageTwo, 100);
    string overlapNote = res.WidthUsageTwo > 100 ? $", {res.WidthUsageTwo - 100}% overlap" : "";
    string prefix = interactive ? $"  {scenarioNumber}. " : "";
    Console.WriteLine($"{prefix}{marker}{res.Width}x{res.Height}, {res.AreaTwoPercent}% area ({widthCapped}% width, {res.HeightUsage}% height{overlapNote}), {res.ZoomFactor * 100}% rdp zoom");
    scenarios.Add((res, "2-window"));
    scenarioNumber++;
}

if (!interactive)
    return 0;

// Interactive mode: select scenario, rdp file, and position
Console.WriteLine();
Console.Write("Select scenario number: ");
string? choiceText = Console.ReadLine();
if (!int.TryParse(choiceText, out int choiceNum) || choiceNum < 1 || choiceNum > scenarios.Count)
{
    Console.WriteLine("Invalid selection.");
    return 1;
}
var selectedRes = scenarios[choiceNum - 1].Resolution;

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

// Compute winposstr for the selected resolution and position
int selectedWinW = (int)Math.Ceiling(rdpWidth * selectedRes.ZoomFactor + chromeWidth);
int selectedWinH = (int)Math.Ceiling(rdpHeight * selectedRes.ZoomFactor + chromeHeight);
string winposstr;
if (side == "L")
{
    winposstr = $"winposstr:s:0,1,0,0,{selectedWinW},{selectedWinH}";
}
else
{
    int sx1 = selectedRes.Width - 1;
    int sx0 = sx1 - selectedWinW;
    winposstr = $"winposstr:s:0,1,{sx0},0,{sx1},{selectedWinH}";
}

// Update the .rdp file, ensuring all documented settings are present
var lines = File.ReadAllLines(targetPath, Encoding.Unicode).ToList();

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

File.WriteAllLines(targetPath, lines, Encoding.Unicode);
Console.WriteLine($"Updated {targetPath} with {winposstr}");
return 0;

static int Gcd(int a, int b)
{
    while (b != 0) { int t = b; b = a % b; a = t; }
    return a;
}

class ResolutionInfo
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
}
