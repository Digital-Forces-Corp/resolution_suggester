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

    public struct ResolutionInfo
    {
        public int Width;
        public int Height;
        public int ZoomFactor;
        public int WidthUsage;
        public int WidthUsageTwo;
        public int HeightUsage;
        public int AreaOne;
        public int AreaTwo;
        public bool IsCurrent;
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

    public static void ListFilteredResolutions()
    {
        const int rdp_height = 600;
        const int rdp_width = 800;
        double chrome_width_base = 14.0;
        double chrome_height_base = 55.0 / 1.5;
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
            Console.WriteLine("ERROR: Failed to retrieve monitor info.");
            return;
        }

        string deviceName = monitorInfo.szDevice;
        string monitorNumber = deviceName.Replace("\\\\.\\DISPLAY", "#");

        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentSettings) || currentSettings.dmPelsHeight == 0)
        {
            Console.WriteLine("ERROR: Failed to retrieve display settings for " + deviceName);
            return;
        }

        uint dpiX, dpiY;
        GetDpiForMonitor(monitorHandle, 0, out dpiX, out dpiY); // MDT_EFFECTIVE_DPI
        double dpiScale = dpiX / 96.0;
        double chromeWidth = chrome_width_base * dpiScale;
        double chromeHeight = chrome_height_base * dpiScale;
        int minimum_height = (int)Math.Ceiling(rdp_height + chromeHeight);

        int currentFrequency = currentSettings.dmDisplayFrequency;
        int currentWidth = currentSettings.dmPelsWidth;
        int currentHeight = currentSettings.dmPelsHeight;
        int ratioGcd = Gcd(currentWidth, currentHeight);
        string currentRatioDisplay = (currentWidth / ratioGcd) + ":" + (currentHeight / ratioGcd);
        Console.WriteLine("Current Monitor " + monitorNumber + ", " + currentWidth + "x" + currentHeight + ", Ratio: " + currentRatioDisplay + ", DPI Scale " + (dpiScale * 100).ToString("F0") + "%, Frequency: " + currentFrequency + "Hz");
        int minWindowWidth = (int)Math.Ceiling(rdp_width + chromeWidth);
        int minWindowHeight = (int)Math.Ceiling(rdp_height + chromeHeight);
        string rdpLabel = "RDP " + rdp_width + "x" + rdp_height;
        for (int zoom = 1; zoom <= 3; zoom++)
        {
            int winW = (int)Math.Ceiling(rdp_width * zoom + chromeWidth);
            int winH = (int)Math.Ceiling(rdp_height * zoom + chromeHeight);
            int x1 = currentWidth - 1;
            int x0 = x1 - winW;
            Console.WriteLine(rdpLabel + " " + (zoom * 100) + "% rdp zoom: winposstr:s:0,1,0,0," + winW + "," + winH + "  2nd: winposstr:s:0,1," + x0 + ",0," + x1 + "," + winH);
        }
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
            int zoomFactor = (int)Math.Floor((resolution.Height - chromeHeight) / rdp_height);
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
                AreaOne = areaOne,
                AreaTwo = areaTwo,
                IsCurrent = (resolution.Width == currentWidth && resolution.Height == currentHeight)
            });
        }

        Console.WriteLine("\n--- Best for 1 RDP window (sorted by area used) ---");
        foreach (var r in computed.OrderByDescending(r => r.AreaOne))
        {
            string marker = r.IsCurrent ? "*" : "";
            Console.WriteLine(marker + r.Width + "x" + r.Height + ", " + (r.AreaOne / 100) + "% area (" + r.WidthUsage + "% width, " + r.HeightUsage + "% height), " + (r.ZoomFactor * 100) + "% rdp zoom");
        }

        Console.WriteLine("\n--- Best for 2 RDP windows (sorted by area used) ---");
        foreach (var r in computed.OrderByDescending(r => r.AreaTwo))
        {
            string marker = r.IsCurrent ? "*" : "";
            string overlapNote = r.WidthUsageTwo > 100
                ? ", " + (r.WidthUsageTwo - 100) + "% overlap"
                : "";
            Console.WriteLine(marker + r.Width + "x" + r.Height + ", " + (r.AreaTwo / 100) + "% area (" + Math.Min(r.WidthUsageTwo, 100) + "% width, " + r.HeightUsage + "% height" + overlapNote + "), " + (r.ZoomFactor * 100) + "% rdp zoom");
        }
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

Invoke-Expression "[$typeName]::ListFilteredResolutions()"
