using System.Runtime.InteropServices;

static class MonitorOracle
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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor, rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    [DllImport("user32.dll")]
    static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int x;
        public int y;
    }

    [DllImport("user32.dll")]
    static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

    [DllImport("shcore.dll")]
    static extern int SetProcessDpiAwareness(int awareness);

    [DllImport("shcore.dll")]
    static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    public record MonitorData(int Width, int Height, int Frequency, uint Dpi, string RatioDisplay);

    public static MonitorData GetCurrentMonitor()
    {
        int dpiAwarenessResult = SetProcessDpiAwareness(2);
        if (dpiAwarenessResult != 0 && dpiAwarenessResult != unchecked((int)0x80070005)) // E_ACCESSDENIED = already set
            throw new Exception($"SetProcessDpiAwareness failed with HRESULT 0x{dpiAwarenessResult:X8}");
        IntPtr monitorHandle = MonitorFromPoint(new POINT { x = 0, y = 0 }, 1); // MONITOR_DEFAULTTOPRIMARY — matches subprocess with no console window

        var monitorInfo = new MONITORINFOEX();
        monitorInfo.cbSize = Marshal.SizeOf(monitorInfo);
        if (!GetMonitorInfo(monitorHandle, ref monitorInfo))
            throw new Exception("Failed to get monitor info");

        var devMode = new DEVMODE();
        if (!EnumDisplaySettings(monitorInfo.szDevice, -1, ref devMode))
            throw new Exception("Failed to get display settings");

        int hr = GetDpiForMonitor(monitorHandle, 0, out uint dpiX, out _);
        if (hr != 0)
            throw new Exception($"GetDpiForMonitor failed with HRESULT 0x{hr:X8}");

        int gcd = Gcd(devMode.dmPelsWidth, devMode.dmPelsHeight);
        string ratio = $"{devMode.dmPelsWidth / gcd}:{devMode.dmPelsHeight / gcd}";

        return new MonitorData(devMode.dmPelsWidth, devMode.dmPelsHeight, devMode.dmDisplayFrequency, dpiX, ratio);
    }

    static int Gcd(int a, int b) { while (b != 0) { int t = b; b = a % b; a = t; } return a; }
}
