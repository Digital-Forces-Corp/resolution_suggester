using System.Runtime.InteropServices;

static class MonitorOracle
{
    [StructLayout(LayoutKind.Sequential)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType;
        public int dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }

    public struct RECT { public int left, top, right, bottom; }

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

    [DllImport("kernel32.dll")]
    static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("shcore.dll")]
    static extern int SetProcessDpiAwareness(int awareness);

    [DllImport("shcore.dll")]
    static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    public record MonitorData(int Width, int Height, int Frequency, uint Dpi, string RatioDisplay);

    public static MonitorData GetCurrentMonitor()
    {
        SetProcessDpiAwareness(2);
        IntPtr consoleHandle = GetConsoleWindow();
        IntPtr monitorHandle = MonitorFromWindow(consoleHandle, 2);

        var monitorInfo = new MONITORINFOEX();
        monitorInfo.cbSize = Marshal.SizeOf(monitorInfo);
        if (!GetMonitorInfo(monitorHandle, ref monitorInfo))
            throw new Exception("Failed to get monitor info");

        var devMode = new DEVMODE();
        if (!EnumDisplaySettings(monitorInfo.szDevice, -1, ref devMode))
            throw new Exception("Failed to get display settings");

        GetDpiForMonitor(monitorHandle, 0, out uint dpiX, out _);

        int gcd = Gcd(devMode.dmPelsWidth, devMode.dmPelsHeight);
        string ratio = $"{devMode.dmPelsWidth / gcd}:{devMode.dmPelsHeight / gcd}";

        return new MonitorData(devMode.dmPelsWidth, devMode.dmPelsHeight, devMode.dmDisplayFrequency, dpiX, ratio);
    }

    static int Gcd(int a, int b) { while (b != 0) { int t = b; b = a % b; a = t; } return a; }
}
