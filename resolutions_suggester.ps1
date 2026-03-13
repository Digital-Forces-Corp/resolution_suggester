$source = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Forms;

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

    // Define a struct to hold resolution details with named properties
    public struct ResolutionInfo
    {
        public int Width;
        public int Height;
        public int BitsPerPel;
        public int Frequency;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    public static void ListFilteredResolutions()
    {
        const int rdp_height = 600;
        const int title_height = 30; 
        const int minimum_height = rdp_height + title_height; 
        const int rdp_width = 800; // Add new constant for RDP width
        DEVMODE devMode = new DEVMODE();
        DEVMODE currentSettings = new DEVMODE(); // To store current settings
        int modeIndex = 0;
        HashSet<string> resolutions = new HashSet<string>();
        List<ResolutionInfo> resolutionList = new List<ResolutionInfo>(); // For sorting by height        
        const int ENUM_CURRENT_SETTINGS = -1;
        EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref currentSettings);
        int currentFrequency = currentSettings.dmDisplayFrequency;
        double currentRatio = (double)currentSettings.dmPelsWidth / currentSettings.dmPelsHeight;
        Console.WriteLine("Current Ratio: " + currentRatio.ToString("F2") + ", Current Frequency: " + currentFrequency + "Hz");

        while (EnumDisplaySettings(null, modeIndex, ref devMode))
        {
            if (devMode.dmDisplayFrequency == currentFrequency && devMode.dmPelsHeight >= minimum_height)
            {
                double ratio = (double)devMode.dmPelsWidth / devMode.dmPelsHeight;

                if (Math.Abs(ratio - currentRatio) < 0.001)
                {
                    string resolutionKey = devMode.dmPelsWidth + "x" + devMode.dmPelsHeight; // Use a consistent key format
                    if (resolutions.Add(resolutionKey))
                    {
                        // Add a new ResolutionInfo instance to the list
                        resolutionList.Add(new ResolutionInfo
                        {
                            Width = devMode.dmPelsWidth,
                            Height = devMode.dmPelsHeight,
                            BitsPerPel = devMode.dmBitsPerPel,
                            Frequency = devMode.dmDisplayFrequency
                        });
                    }
                }
            }
            modeIndex++;
        }

        var sortedResolutions = resolutionList.OrderBy(r => r.Height).ToList();

        foreach (var resolution in sortedResolutions)
        {
            double ratio = (double)resolution.Height / minimum_height;
            int integer_zoom_factor = (int)Math.Floor(ratio); // Find the largest integer zoom factor that fits
            int zoomed_height = minimum_height * integer_zoom_factor; // Calculate height at that integer zoom

            // Calculate width and height usage percentages
            int width_usage = (int)Math.Round((double)rdp_width / resolution.Width * 100);
            int width_usage_two = (int)Math.Round((double)(2 * rdp_width) / resolution.Width * 100);
            int overlap = width_usage_two > 100 ? width_usage_two - 100 : 0;
            int height_usage = (int)Math.Round((double)zoomed_height / resolution.Height * 100);

            // Print in requested format
            string usage_str = resolution.Width + "x" + resolution.Height + ", " + (integer_zoom_factor * 100) + "% zoom, Uses: " + width_usage + "% width ";
            if (width_usage_two > 100) {
                usage_str += "(" + overlap + "% overlap if two), ";
            } else {
                usage_str += "(" + width_usage_two + "% if two), ";
            }
            usage_str += height_usage + "% height";
            Console.WriteLine(usage_str);
        }
    }
}
"@

# Compile the C# code only if the type doesn't already exist
if (-not ([System.Type]::GetType('DisplayResolutions', $false))) {
    Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies System.Windows.Forms, System.Linq, System.Collections, System.Drawing.Primitives, System.Console
}

[DisplayResolutions]::ListFilteredResolutions()
