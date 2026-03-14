using System.Text;
using System.Text.RegularExpressions;

static class Assertions
{
    const int MaxZoom = 2;
    const double ChromeWidth96Dpi = 14.0;
    const double ChromeHeight96Dpi = 55.0 / 1.5;

    public record AssertResult(bool Passed, string Message);

    static AssertResult Ok() => new(true, "");
    static AssertResult Fail(string msg) => new(false, msg);

    public static List<AssertResult> AssertAll(
        TestCase.PictRow row,
        ProcessRunner.RunResult result,
        string tempDir,
        MonitorOracle.MonitorData? realMonitor,
        string impl = "csharp")
    {
        var results = new List<AssertResult>();

        // --- ResolutionArg early exits ---
        if (row.ResolutionArg == "help")
        {
            results.Add(AssertExitCode(result, 0));
            // Help text differs between implementations
            results.Add(AssertContains(result.Stdout, "[-r WxH|W|WxN:D] [paths...]", "help text"));
            return results;
        }
        if (row.ResolutionArg == "invalid_format")
        {
            results.Add(AssertExitCode(result, 1));
            results.Add(AssertContains(result.Stdout, "Invalid RDP resolution format", "invalid format error"));
            return results;
        }
        if (row.ResolutionArg == "invalid_ratio")
        {
            results.Add(AssertExitCode(result, 1));
            results.Add(AssertContains(result.Stdout, "Invalid aspect ratio", "invalid ratio error"));
            return results;
        }

        // --- Nonexistent file: crash after interactive prompts ---
        if (row.FileCount == "nonexistent")
        {
            results.Add(AssertNotExitCode(result, 0));
            return results;
        }

        // --- Invalid selection ---
        if (row.MonitorResSel == "invalid_selection")
        {
            results.Add(AssertExitCode(result, 1));
            results.Add(AssertContains(result.Stdout, "Invalid selection.", "invalid selection"));
            return results;
        }

        // --- Invalid file selection ---
        if (row.FileSel == "invalid_file")
        {
            results.Add(AssertExitCode(result, 1));
            results.Add(AssertContains(result.Stdout, "Invalid selection.", "invalid file selection"));
            return results;
        }

        // --- Invalid side ---
        if (row.Side == "invalid_side")
        {
            results.Add(AssertExitCode(result, 1));
            results.Add(AssertContains(result.Stdout, "Invalid selection.", "invalid side"));
            return results;
        }

        // --- Normal flow ---
        results.Add(AssertExitCode(result, 0));

        // Header line
        if (row.Monitor == "real" && realMonitor != null)
        {
            results.Add(AssertContains(result.Stdout, "Current Monitor #", "monitor header"));
            results.Add(AssertContains(result.Stdout, $"Ratio: {realMonitor.RatioDisplay}", "ratio in header"));
            results.Add(AssertContains(result.Stdout, $"Frequency: {realMonitor.Frequency}Hz", "frequency in header"));
            string dpiPct = (realMonitor.Dpi / 96.0 * 100).ToString("F0");
            results.Add(AssertContains(result.Stdout, $"DPI Scale {dpiPct}%", "DPI in header"));
        }
        else if (row.Monitor != "real")
        {
            var mon = SyntheticMonitor.All[row.Monitor];
            string expectedDpi = (mon.Dpi / 96.0 * 100).ToString("F0");
            string expectedHeader = $"Current Monitor #0, {mon.Width}x{mon.Height}, Ratio: 16:9, Frequency: {mon.Frequency}Hz, DPI Scale {expectedDpi}%";
            results.Add(AssertContains(result.Stdout, expectedHeader, "synthetic header"));

            // Noise modes must not appear in monitor resolution output
            // Skip when picker is active (picker menu lists common resolutions that match noise dimensions)
            if (row.ResolutionArg != "picker")
            {
                foreach (string noise in mon.NoiseModes)
                {
                    string noiseDimensions = noise.Split('@')[0]; // strip frequency qualifier
                    // Skip noise check if dimensions match monitor resolution (they naturally appear in header/monitor resolution lists)
                    if (noiseDimensions == $"{mon.Width}x{mon.Height}")
                        continue;
                    results.Add(AssertNotContains(result.Stdout, noiseDimensions, $"noise mode {noise}"));
                }
            }
        }

        // Picker menu
        if (row.ResolutionArg == "picker")
        {
            results.Add(AssertContains(result.Stdout, "Common resolutions:", "picker menu"));
        }

        // Winposstr reference lines (always present for non-error cases)
        int rdpW = GetExpectedRdpWidth(row);
        int rdpH = GetExpectedRdpHeight(row, realMonitor, row.Monitor != "real" ? SyntheticMonitor.All[row.Monitor] : null);
        results.Add(AssertContains(result.Stdout, $"RDP {rdpW}x{rdpH}", "winposstr reference label"));

        // Verify exact winposstr reference line values for synthetic monitors
        if (row.Monitor != "real")
        {
            var mon = SyntheticMonitor.All[row.Monitor];
            double dpiScaleRef = mon.Dpi / 96.0;
            double chromeWRef = ChromeWidth96Dpi * dpiScaleRef;
            double chromeHRef = ChromeHeight96Dpi * dpiScaleRef;
            for (int zoom = 1; zoom <= MaxZoom; zoom++)
            {
                int refWinW = (int)Math.Ceiling(rdpW * zoom + chromeWRef);
                int refWinH = (int)Math.Ceiling(rdpH * zoom + chromeHRef);
                int refX1 = mon.Width - 1;
                int refX0 = refX1 - refWinW;
                string expectedLine = $"RDP {rdpW}x{rdpH} {zoom * 100}% rdp zoom: winposstr:s:0,1,0,0,{refWinW},{refWinH}  2nd: winposstr:s:0,1,{refX0},0,{refX1},{refWinH}";
                results.Add(AssertContains(result.Stdout, expectedLine, $"winposstr reference zoom {zoom * 100}%"));
            }
        }

        // .rdp file assertions (only when files are involved and flow completes)
        if (row.FileCount != "zero")
        {
            results.Add(AssertContains(result.Stdout, "Updated ", "update confirmation"));
            results.AddRange(AssertRdpFile(row, tempDir, rdpW, rdpH));
        }

        return results;
    }

    static int GetExpectedRdpWidth(TestCase.PictRow row)
    {
        return row.ResolutionArg switch
        {
            "explicit_WxH" => 1024,
            "width_only" => 1280,
            "WxN_D" => 1280,
            "picker" => 1280,
            _ => 800
        };
    }

    static int GetExpectedRdpHeight(TestCase.PictRow row, MonitorOracle.MonitorData? realMonitor, SyntheticMonitor.MonitorDef? synthMonitor)
    {
        return row.ResolutionArg switch
        {
            "explicit_WxH" => 768,
            "WxN_D" => 960,
            "picker" => 720,
            "width_only" => ComputeWidthOnlyHeight(1280, realMonitor, synthMonitor),
            _ => 600
        };
    }

    static int ComputeWidthOnlyHeight(int width, MonitorOracle.MonitorData? realMonitor, SyntheticMonitor.MonitorDef? synthMonitor)
    {
        double ratio;
        if (synthMonitor != null)
            ratio = (double)synthMonitor.Width / synthMonitor.Height;
        else if (realMonitor != null)
            ratio = (double)realMonitor.Width / realMonitor.Height;
        else
            throw new Exception("No monitor data for width_only height computation");
        return (int)Math.Round(width / ratio);
    }

    static readonly string FixturesDir = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "fixtures");

    static List<AssertResult> AssertRdpFile(TestCase.PictRow row, string tempDir, int rdpW, int rdpH)
    {
        var results = new List<AssertResult>();

        // Determine which file was targeted
        string targetFile;
        if (row.FileCount == "directory")
        {
            string subdir = Path.Combine(tempDir, "testdir");
            string[] rdpFiles = Directory.GetFiles(subdir, "*.rdp").OrderBy(f => f).ToArray();
            int fileIndex = row.FileSel == "second" ? 1 : 0;
            targetFile = rdpFiles[fileIndex];

            // Verify non-targeted file is untouched (byte-identical to its original fixture)
            if (rdpFiles.Length > 1)
            {
                int otherIndex = fileIndex == 0 ? 1 : 0;
                // In directory setup, test1.rdp uses the rdpSettings fixture, test2.rdp is always test2.rdp
                string otherFixture = Path.GetFileName(rdpFiles[otherIndex]) == "test2.rdp"
                    ? Path.Combine(FixturesDir, "test2.rdp")
                    : Path.Combine(FixturesDir, GetFixtureFileName(row.RdpSettings));
                results.AddRange(AssertFileUnchanged(rdpFiles[otherIndex], otherFixture));
            }
        }
        else if (row.FileCount == "two")
        {
            int fileIndex = row.FileSel == "second" ? 1 : 0;
            string[] files = { Path.Combine(tempDir, "test1.rdp"), Path.Combine(tempDir, "test2.rdp") };
            targetFile = files[fileIndex];

            // Verify non-targeted file is byte-identical to its original fixture
            int otherIndex = fileIndex == 0 ? 1 : 0;
            string otherFixture = otherIndex == 0
                ? Path.Combine(FixturesDir, GetFixtureFileName(row.RdpSettings))
                : Path.Combine(FixturesDir, "test2.rdp");
            results.AddRange(AssertFileUnchanged(files[otherIndex], otherFixture));
        }
        else
        {
            targetFile = Path.Combine(tempDir, "test1.rdp");
        }

        if (!File.Exists(targetFile))
        {
            results.Add(Fail($"Target .rdp file not found: {targetFile}"));
            return results;
        }

        // Verify encoding: UTF-16 LE with BOM
        byte[] rawBytes = File.ReadAllBytes(targetFile);
        if (rawBytes.Length < 2 || rawBytes[0] != 0xFF || rawBytes[1] != 0xFE)
        {
            results.Add(Fail($"File {targetFile} missing UTF-16 LE BOM"));
        }

        string[] lines = File.ReadAllLines(targetFile, Encoding.Unicode);

        // Compute expected winposstr
        int dpi = row.Monitor == "real" ? 96 : SyntheticMonitor.All[row.Monitor].Dpi; // real monitor DPI handled separately
        double dpiScale = dpi / 96.0;
        double chromeW = ChromeWidth96Dpi * dpiScale;
        double chromeH = ChromeHeight96Dpi * dpiScale;

        // For the selected monitor resolution, we need to know which mode was selected.
        // Parse the selection from stdout to get the mode dimensions.
        // (Simplified: for one_window pick first option, for two_window pick first two-window option)
        // This is handled by the stdout parsing below.

        // Check required settings exist exactly once
        results.Add(AssertLineCount(lines, "smart sizing:i:0", 1, "smart sizing"));
        results.Add(AssertLineCount(lines, "allow font smoothing:i:1", 1, "allow font smoothing"));
        results.Add(AssertLineCount(lines, $"desktopwidth:i:{rdpW}", 1, "desktopwidth"));
        results.Add(AssertLineCount(lines, $"desktopheight:i:{rdpH}", 1, "desktopheight"));
        results.Add(AssertLineMatchCount(lines, "^winposstr:s:", 1, "winposstr"));

        // Verify exact winposstr value for synthetic monitors
        if (row.Monitor != "real")
        {
            var mon = SyntheticMonitor.All[row.Monitor];
            string expectedWinposstr = ComputeExpectedWinposstr(row, mon, rdpW, rdpH);
            results.Add(AssertLineCount(lines, expectedWinposstr, 1, "exact winposstr value"));
        }

        return results;
    }

    static string GetFixtureFileName(string rdpSettings) => rdpSettings switch
    {
        "all_present" => "test1.rdp",
        "none_present" => "test2.rdp",
        "partial" => "test1_partial.rdp",
        _ => throw new ArgumentException($"Unknown RdpSettings: {rdpSettings}")
    };

    /// Compute the exact expected winposstr for a synthetic monitor test case.
    /// Uses the same math as Program.cs but computed independently.
    static string ComputeExpectedWinposstr(TestCase.PictRow row, SyntheticMonitor.MonitorDef mon, int rdpW, int rdpH)
    {
        double dpiScale = mon.Dpi / 96.0;
        double chromeW = ChromeWidth96Dpi * dpiScale;
        double chromeH = ChromeHeight96Dpi * dpiScale;

        // Determine which mode was selected (option 1 = first mode by area for one_window, etc.)
        // The selected mode is the first entry in the sorted option list.
        // For simplicity, compute all modes' area and pick the right one.
        var matchingModes = new List<(int W, int H)>();
        double monitorRatio = (double)mon.Width / mon.Height;
        int minimumHeight = (int)Math.Ceiling(rdpH + chromeH);

        foreach (string modeStr in mon.TestModesArg.Split(','))
        {
            var match = Regex.Match(modeStr, @"^(\d+)x(\d+)(?:@(\d+)Hz)?$");
            int modeW = int.Parse(match.Groups[1].Value);
            int modeH = int.Parse(match.Groups[2].Value);
            int modeFreq = match.Groups[3].Success ? int.Parse(match.Groups[3].Value) : mon.Frequency;
            if (modeFreq != mon.Frequency) continue;
            if (modeH < minimumHeight) continue;
            double ratio = (double)modeW / modeH;
            if (Math.Abs(ratio - monitorRatio) >= 0.001) continue;
            matchingModes.Add((modeW, modeH));
        }

        // Compute monitor resolution info for each mode
        var monitorResolutions = new List<(int W, int H, int Zoom, int AreaOne, int AreaTwo)>();
        foreach (var (modeW, modeH) in matchingModes)
        {
            int zoom = Math.Min((int)Math.Floor((modeH - chromeH) / rdpH), MaxZoom);
            double winWidth = rdpW * zoom + chromeW;
            double winHeight = rdpH * zoom + chromeH;
            int widthUsage = (int)Math.Round(winWidth / modeW * 100);
            int widthUsageTwo = (int)Math.Round(2 * winWidth / modeW * 100);
            int heightUsage = (int)Math.Round(winHeight / modeH * 100);
            int areaOne = widthUsage * heightUsage / 100;
            int areaTwo = Math.Min(widthUsageTwo, 100) * heightUsage / 100;
            monitorResolutions.Add((modeW, modeH, zoom, areaOne, areaTwo));
        }

        // Sort and pick the selected monitor resolution
        (int selW, int selH, int selZoom, int, int) selectedMode;
        if (row.MonitorResSel == "one_window")
        {
            // Option 1 = first by area descending (one-window)
            selectedMode = monitorResolutions.OrderByDescending(s => s.AreaOne).First();
        }
        else
        {
            // Two-window: first by AreaTwo descending
            selectedMode = monitorResolutions.OrderByDescending(s => s.AreaTwo).First();
        }

        int winW = (int)Math.Ceiling(rdpW * selectedMode.selZoom + chromeW);
        int winH = (int)Math.Ceiling(rdpH * selectedMode.selZoom + chromeH);

        if (row.Side == "L")
        {
            return $"winposstr:s:0,1,0,0,{winW},{winH}";
        }
        else // R
        {
            int x1 = selectedMode.selW - 1;
            int x0 = x1 - winW;
            return $"winposstr:s:0,1,{x0},0,{x1},{winH}";
        }
    }

    static List<AssertResult> AssertFileUnchanged(string filePath, string originalFixturePath)
    {
        var results = new List<AssertResult>();
        if (!File.Exists(filePath))
        {
            results.Add(Fail($"Non-targeted file missing: {filePath}"));
            return results;
        }
        byte[] actual = File.ReadAllBytes(filePath);
        byte[] expected = File.ReadAllBytes(originalFixturePath);
        if (!actual.SequenceEqual(expected))
        {
            results.Add(Fail($"Non-targeted file {Path.GetFileName(filePath)} was modified (not byte-identical to fixture)"));
        }
        return results;
    }

    static AssertResult AssertExitCode(ProcessRunner.RunResult result, int expected)
    {
        return result.ExitCode == expected
            ? Ok()
            : Fail($"Expected exit code {expected}, got {result.ExitCode}. stderr: {result.Stderr}");
    }

    static AssertResult AssertNotExitCode(ProcessRunner.RunResult result, int notExpected)
    {
        return result.ExitCode != notExpected
            ? Ok()
            : Fail($"Expected exit code != {notExpected}, but got {result.ExitCode}");
    }

    static AssertResult AssertContains(string text, string substring, string label)
    {
        return text.Contains(substring)
            ? Ok()
            : Fail($"[{label}] Expected stdout to contain \"{substring}\"");
    }

    static AssertResult AssertNotContains(string text, string substring, string label)
    {
        return !text.Contains(substring)
            ? Ok()
            : Fail($"[{label}] Expected stdout NOT to contain \"{substring}\"");
    }

    static AssertResult AssertLineCount(string[] lines, string exactLine, int expected, string label)
    {
        int count = lines.Count(l => l == exactLine);
        return count == expected
            ? Ok()
            : Fail($"[{label}] Expected \"{exactLine}\" to appear {expected} time(s), found {count}");
    }

    static AssertResult AssertLineMatchCount(string[] lines, string pattern, int expected, string label)
    {
        int count = lines.Count(l => Regex.IsMatch(l, pattern));
        return count == expected
            ? Ok()
            : Fail($"[{label}] Expected pattern \"{pattern}\" to match {expected} line(s), found {count}");
    }
}
