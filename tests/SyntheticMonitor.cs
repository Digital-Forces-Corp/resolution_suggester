using System.Collections.Generic;

static class SyntheticMonitor
{
    public record MonitorDef(
        int Width,
        int Height,
        int Frequency,
        int Dpi,
        string TestModesArg,
        string[] NoiseModes      // modes that must NOT appear in output
    )
    {
        public string TestMonitorArg => $"{Width}x{Height}@{Frequency}Hz@{Dpi}dpi";
    }

    static readonly string Modes2560x1440 = "2560x1440,1920x1080,1280x720,1920x1200,2560x1440@75Hz";
    static readonly string[] Noise2560x1440 = new[] { "1920x1200" };
    static readonly string Modes1920x1080 = "1920x1080,1280x720,1280x800,1920x1080@144Hz";
    static readonly string[] Noise1920x1080 = new[] { "1280x800" };

    public static readonly Dictionary<string, MonitorDef> All = new()
    {
        ["synth_2560x1440_96dpi"] = new MonitorDef(
            2560, 1440, 60, 96,
            Modes2560x1440,
            Noise2560x1440
        ),
        ["synth_2560x1440_192dpi"] = new MonitorDef(
            2560, 1440, 60, 192,
            Modes2560x1440,
            Noise2560x1440
        ),
        ["synth_1920x1080_96dpi"] = new MonitorDef(
            1920, 1080, 60, 96,
            Modes1920x1080,
            Noise1920x1080
        ),
        ["synth_1920x1080_192dpi"] = new MonitorDef(
            1920, 1080, 60, 192,
            Modes1920x1080,
            Noise1920x1080
        ),
    };
}
