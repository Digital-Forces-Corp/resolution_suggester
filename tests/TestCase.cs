static class TestCase
{
    public const string PickerSelection = "3"; // entry 3 = 1280x720
    public const string MonitorReal = "real";

    public const string FixtureTest1 = "test1.rdp";
    public const string FixtureTest2 = "test2.rdp";
    public const string FixtureTestDir = "testdir";
    public const string FixtureNonexistent = "nonexistent.rdp";

    public const string ResHelp = "help";
    public const string ResInvalidFormat = "invalid_format";
    public const string ResInvalidRatio = "invalid_ratio";
    public const string ResPicker = "picker";
    public const string ResExplicitWxH = "explicit_WxH";
    public const string ResWidthOnly = "width_only";
    public const string ResWxND = "WxN_D";
    public const string ResDefault = "default";

    public const string SelOneWindow = "one_window";
    public const string SelTwoWindow = "two_window";
    public const string SelInvalid = "invalid_selection";

    public const string SideLeft = "L";
    public const string SideRight = "R";
    public const string SideInvalid = "invalid_side";

    public const string FileSelFirst = "first";
    public const string FileSelSecond = "second";
    public const string FileSelInvalid = "invalid_file";

    public record PictRow(
        string Monitor,
        string ResolutionArg,
        string MonitorResSel,
        string Side,
        string FileCount,
        string FileSel,
        string RdpSettings
    );

    public static List<PictRow> LoadFromTsv(string tsvPath)
    {
        var rows = new List<PictRow>();
        var lines = File.ReadAllLines(tsvPath);
        // Skip header
        for (int i = 1; i < lines.Length; i++)
        {
            string line = lines[i].Trim();
            if (line.Length == 0) continue;
            string[] cols = line.Split('\t');
            if (cols.Length < 7)
                throw new InvalidDataException($"Line {i + 1}: expected 7 columns, got {cols.Length}. Raw line: {line}");
            rows.Add(new PictRow(cols[0], cols[1], cols[2], cols[3], cols[4], cols[5], cols[6]));
        }
        if (rows.Count == 0)
            throw new InvalidDataException($"TSV file contains no data rows: {tsvPath}");
        return rows;
    }

    public static string BuildCliArgs(PictRow row, string tempDir)
    {
        var args = new List<string>();

        // --test-monitor / --test-modes for synthetic monitors
        // -File mode passes args literally, no quoting needed for PS1
        if (row.Monitor != MonitorReal)
        {
            if (!SyntheticMonitor.All.TryGetValue(row.Monitor, out var mon))
                throw new InvalidOperationException($"Unknown monitor: {row.Monitor}");
            args.Add($"--test-monitor {mon.TestMonitorArg}");
            args.Add($"--test-modes {mon.TestModesArg}");
        }

        // Resolution arg (picker goes after file paths so parser sees it as last arg with no value)
        switch (row.ResolutionArg)
        {
            case ResExplicitWxH: args.Add("-r 1024x768"); break;
            case ResWidthOnly: args.Add("-r 1280"); break;
            case ResWxND: args.Add("-r 1280x4:3"); break;
            case ResHelp: args.Add("-h"); break;
            case ResInvalidFormat: args.Add("-r notaresolution"); break;
            case ResInvalidRatio: args.Add("-r 1280x0:0"); break;
            case ResPicker: break;
            case ResDefault: break;
            default: throw new InvalidOperationException($"Unknown ResolutionArg value: {row.ResolutionArg}");
        }

        // File paths
        switch (row.FileCount)
        {
            case FixtureManager.FileCountOne:
                args.Add($"\"{Path.Combine(tempDir, FixtureTest1)}\"");
                break;
            case FixtureManager.FileCountTwo:
                args.Add($"\"{Path.Combine(tempDir, FixtureTest1)}\"");
                args.Add($"\"{Path.Combine(tempDir, FixtureTest2)}\"");
                break;
            case FixtureManager.FileCountDirectory:
                args.Add($"\"{Path.Combine(tempDir, FixtureTestDir)}\"");
                break;
            case FixtureManager.FileCountNonexistent:
                args.Add($"\"{Path.Combine(tempDir, FixtureNonexistent)}\"");
                break;
            // FileCountZero: no file args
            case FixtureManager.FileCountZero: break;
            default: throw new InvalidOperationException($"Unknown FileCount value: {row.FileCount}");
        }

        // Picker must come after file paths so arg parser sees -r as last arg (no next value)
        if (row.ResolutionArg == ResPicker)
            args.Add("-r");

        return string.Join(" ", args);
    }

    public static string? BuildStdin(PictRow row)
    {
        // Early-exit cases: no stdin needed
        if (row.ResolutionArg == ResHelp || row.ResolutionArg == ResInvalidFormat || row.ResolutionArg == ResInvalidRatio)
            return null;
        // Zero files with no picker means non-interactive (no stdin needed)
        if (row.FileCount == FixtureManager.FileCountZero && row.ResolutionArg != ResPicker)
            return null;

        var parts = new List<string>();

        // Picker: resolution selection comes first
        if (row.ResolutionArg == ResPicker)
            parts.Add(PickerSelection); // entry 3 = 1280x720

        // Monitor resolution selection (prompt order: monitor resolution, file, side)
        switch (row.MonitorResSel)
        {
            case SelOneWindow: parts.Add("1"); break;
            case SelTwoWindow:
                // Two-window options are numbered after one-window options.
                // The exact number depends on how many modes pass filtering.
                // Use a placeholder that TestRunner resolves after parsing stdout.
                parts.Add("TWO_WINDOW_FIRST");
                break;
            case SelInvalid: parts.Add("999"); break;
            default: throw new InvalidOperationException($"Unknown MonitorResSel value: {row.MonitorResSel}");
        }

        // Invalid selection exits early — no more prompts
        if (row.MonitorResSel == SelInvalid)
            return string.Join("\n", parts) + "\n";

        // File selection (only prompted when 2+ files)
        if (row.FileCount == FixtureManager.FileCountTwo || row.FileCount == FixtureManager.FileCountDirectory)
        {
            switch (row.FileSel)
            {
                case FileSelFirst: parts.Add("1"); break;
                case FileSelSecond: parts.Add("2"); break;
                case FileSelInvalid: parts.Add("999"); break;
                default: throw new InvalidOperationException($"Unknown FileSel value: {row.FileSel}");
            }

            // Invalid file exits early
            if (row.FileSel == FileSelInvalid)
                return string.Join("\n", parts) + "\n";
        }

        // Side selection
        switch (row.Side)
        {
            case SideLeft: parts.Add(SideLeft); break;
            case SideRight: parts.Add(SideRight); break;
            case SideInvalid: parts.Add("X"); break;
            default: throw new InvalidOperationException($"Unknown Side value: {row.Side}");
        }

        return string.Join("\n", parts) + "\n";
    }
}
