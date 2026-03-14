using System.Collections.Generic;

static class SyntheticMonitor
{
    public record MonitorDef(
        int Width,
        int Height,
        int Frequency,
        int Dpi,
        string TestMonitorArg,
        string TestModesArg,
        string[] NoiseModes      // modes that must NOT appear in output
    );

    public static readonly Dictionary<string, MonitorDef> All = new()
    {
        ["synth_2560x1440_96dpi"] = new MonitorDef(
            2560, 1440, 60, 96,
            "2560x1440@60Hz@96dpi",
            "2560x1440,1920x1080,1280x720,1920x1200,2560x1440@75Hz",
            new[] { "1920x1200", "2560x1440@75Hz" }
        ),
        ["synth_2560x1440_192dpi"] = new MonitorDef(
            2560, 1440, 60, 192,
            "2560x1440@60Hz@192dpi",
            "2560x1440,1920x1080,1280x720,1920x1200,2560x1440@75Hz",
            new[] { "1920x1200", "2560x1440@75Hz" }
        ),
        ["synth_1920x1080_96dpi"] = new MonitorDef(
            1920, 1080, 60, 96,
            "1920x1080@60Hz@96dpi",
            "1920x1080,1280x720,1280x800,1920x1080@144Hz",
            new[] { "1280x800", "1920x1080@144Hz" }
        ),
        ["synth_1920x1080_192dpi"] = new MonitorDef(
            1920, 1080, 60, 192,
            "1920x1080@60Hz@192dpi",
            "1920x1080,1280x720,1280x800,1920x1080@144Hz",
            new[] { "1280x800", "1920x1080@144Hz" }
        ),
    };
}
