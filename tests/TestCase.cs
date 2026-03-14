static class TestCase
{
    public const string PickerSelection = "3"; // entry 3 = 1280x720

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
            rows.Add(new PictRow(cols[0], cols[1], cols[2], cols[3], cols[4], cols[5], cols[6]));
        }
        return rows;
    }

    public static string BuildCliArgs(PictRow row, string tempDir, string impl = "csharp")
    {
        var args = new List<string>();

        // --test-monitor / --test-modes for synthetic monitors
        // -File mode passes args literally, no quoting needed for either impl
        if (row.Monitor != "real")
        {
            var mon = SyntheticMonitor.All[row.Monitor];
            args.Add($"--test-monitor {mon.TestMonitorArg}");
            args.Add($"--test-modes {mon.TestModesArg}");
        }

        // Resolution arg (picker goes after file paths so parser sees it as last arg with no value)
        switch (row.ResolutionArg)
        {
            case "explicit_WxH": args.Add("-r 1024x768"); break;
            case "width_only": args.Add("-r 1280"); break;
            case "WxN_D": args.Add("-r 1280x4:3"); break;
            case "help": args.Add("-h"); break;
            case "invalid_format": args.Add("-r notaresolution"); break;
            case "invalid_ratio": args.Add("-r 1280x0:0"); break;
            // "picker" added after file paths below
            // "default": no -r flag
        }

        // File paths
        switch (row.FileCount)
        {
            case "one":
                args.Add($"\"{Path.Combine(tempDir, "test1.rdp")}\"");
                break;
            case "two":
                args.Add($"\"{Path.Combine(tempDir, "test1.rdp")}\"");
                args.Add($"\"{Path.Combine(tempDir, "test2.rdp")}\"");
                break;
            case "directory":
                args.Add($"\"{Path.Combine(tempDir, "testdir")}\"");
                break;
            case "nonexistent":
                args.Add($"\"{Path.Combine(tempDir, "nonexistent.rdp")}\"");
                break;
            // "zero": no file args
        }

        // Picker must come after file paths so arg parser sees -r as last arg (no next value)
        if (row.ResolutionArg == "picker")
            args.Add("-r");

        return string.Join(" ", args);
    }

    public static string? BuildStdin(PictRow row)
    {
        // Early-exit cases: no stdin needed
        if (row.ResolutionArg == "help" || row.ResolutionArg == "invalid_format" || row.ResolutionArg == "invalid_ratio")
            return null;
        // Zero files with no picker means non-interactive (no stdin needed)
        if (row.FileCount == "zero" && row.ResolutionArg != "picker")
            return null;

        var parts = new List<string>();

        // Picker: resolution selection comes first
        if (row.ResolutionArg == "picker")
            parts.Add(PickerSelection); // entry 3 = 1280x720

        // Monitor resolution selection (prompt order: monitor resolution, file, side)
        switch (row.MonitorResSel)
        {
            case "one_window": parts.Add("1"); break;
            case "two_window":
                // Two-window options are numbered after one-window options.
                // The exact number depends on how many modes pass filtering.
                // Use a placeholder that TestRunner resolves after parsing stdout.
                parts.Add("TWO_WINDOW_FIRST");
                break;
            case "invalid_selection": parts.Add("999"); break;
        }

        // Invalid selection exits early — no more prompts
        if (row.MonitorResSel == "invalid_selection")
            return string.Join("\n", parts) + "\n";

        // File selection (only prompted when 2+ files)
        if (row.FileCount == "two" || row.FileCount == "directory")
        {
            switch (row.FileSel)
            {
                case "first": parts.Add("1"); break;
                case "second": parts.Add("2"); break;
                case "invalid_file": parts.Add("999"); break;
            }

            // Invalid file exits early
            if (row.FileSel == "invalid_file")
                return string.Join("\n", parts) + "\n";
        }

        // Side selection
        switch (row.Side)
        {
            case "L": parts.Add("L"); break;
            case "R": parts.Add("R"); break;
            case "invalid_side": parts.Add("X"); break;
        }

        return string.Join("\n", parts) + "\n";
    }
}
