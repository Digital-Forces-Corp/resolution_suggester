using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class DisplayMonitor
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

    public class DisplayMode
    {
        public int Width;
        public int Height;
    }

    public class MonitorData
    {
        public string MonitorNumber;
        public int CurrentWidth;
        public int CurrentHeight;
        public int CurrentFrequency;
        public double DpiScale;
        public List<DisplayMode> AvailableModes;
        public string Error;
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

    public static MonitorData GetMonitorData()
    {
        const int ENUM_CURRENT_SETTINGS = -1;

        SetProcessDpiAwareness(2); // PROCESS_PER_MONITOR_DPI_AWARE

        IntPtr consoleHandle = GetConsoleWindow();
        IntPtr monitorHandle = MonitorFromWindow(consoleHandle, 2); // MONITOR_DEFAULTTONEAREST

        MONITORINFOEX monitorInfo = new MONITORINFOEX();
        monitorInfo.cbSize = Marshal.SizeOf(monitorInfo);
        if (!GetMonitorInfo(monitorHandle, ref monitorInfo))
        {
            return new MonitorData { Error = "ERROR: Failed to retrieve monitor info." };
        }

        string deviceName = monitorInfo.szDevice;
        string monitorNumber = deviceName.Replace("\\\\.\\DISPLAY", "#");

        DEVMODE currentSettings = new DEVMODE();
        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentSettings) || currentSettings.dmPelsHeight == 0)
        {
            return new MonitorData { Error = "ERROR: Failed to retrieve display settings for " + deviceName };
        }

        uint dpiX, dpiY;
        GetDpiForMonitor(monitorHandle, 0, out dpiX, out dpiY); // MDT_EFFECTIVE_DPI

        int currentFrequency = currentSettings.dmDisplayFrequency;
        int currentWidth = currentSettings.dmPelsWidth;
        int currentHeight = currentSettings.dmPelsHeight;
        double currentRatio = (double)currentWidth / currentHeight;

        var modes = new List<DisplayMode>();
        var seen = new HashSet<string>();
        DEVMODE devMode = new DEVMODE();
        int modeIndex = 0;

        while (EnumDisplaySettings(deviceName, modeIndex, ref devMode))
        {
            if (devMode.dmDisplayFrequency == currentFrequency && devMode.dmPelsHeight > 0)
            {
                double ratio = (double)devMode.dmPelsWidth / devMode.dmPelsHeight;

                if (Math.Abs(ratio - currentRatio) < 0.001)
                {
                    string key = devMode.dmPelsWidth + "x" + devMode.dmPelsHeight;
                    if (seen.Add(key))
                    {
                        modes.Add(new DisplayMode
                        {
                            Width = devMode.dmPelsWidth,
                            Height = devMode.dmPelsHeight
                        });
                    }
                }
            }
            modeIndex++;
        }

        return new MonitorData
        {
            MonitorNumber = monitorNumber,
            CurrentWidth = currentWidth,
            CurrentHeight = currentHeight,
            CurrentFrequency = currentFrequency,
            DpiScale = dpiX / 96.0,
            AvailableModes = modes
        };
    }
}
