using System.Text.RegularExpressions;

const string OneRdpSectionMarker = "1 RDP";

string projectDir = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", ".."));
string repoRoot = Path.GetFullPath(Path.Combine(projectDir, ".."));
string ps1Path = Path.Combine(repoRoot, "resolutions_suggester.ps1");
string tsvPath = Path.Combine(projectDir, "pairwise-output.tsv");

if (!File.Exists(ps1Path))
{
    Console.WriteLine($"ERROR: PS1 not found at {ps1Path}");
    return 1;
}

if (!File.Exists(tsvPath))
{
    Console.WriteLine($"ERROR: TSV not found at {tsvPath}");
    return 1;
}

// Get real monitor data once (used for all "real" monitor tests)
MonitorOracle.MonitorData? realMonitor = null;
try
{
    realMonitor = MonitorOracle.GetCurrentMonitor();
    Console.WriteLine($"Real monitor: {realMonitor.Width}x{realMonitor.Height}, {realMonitor.Frequency}Hz, {realMonitor.Dpi}dpi, {realMonitor.RatioDisplay}");
}
catch (Exception ex)
{
    Console.WriteLine($"WARNING: Could not detect real monitor: {ex.Message}");
    Console.WriteLine("Tests with Monitor=real will be skipped.");
}

var rows = TestCase.LoadFromTsv(tsvPath);
Console.WriteLine($"Loaded {rows.Count} test cases from {tsvPath}");

int totalFailed = 0;

Console.WriteLine();
Console.WriteLine("=== PowerShell implementation ===");
totalFailed += RunTestSuite(rows, realMonitor, ps1Path);

return totalFailed > 0 ? 1 : 0;

static int RunTestSuite(
    List<TestCase.PictRow> rows,
    MonitorOracle.MonitorData? realMonitor,
    string ps1Path)
{
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    var failures = new List<(int Index, TestCase.PictRow Row, List<Assertions.AssertResult> Results)>();

    for (int i = 0; i < rows.Count; i++)
    {
        var row = rows[i];
        string label = $"[{i + 1}/{rows.Count}] {FormatTestLabel(row)}";

        // Skip real monitor tests if no monitor detected
        if (row.Monitor == TestCase.MonitorReal && realMonitor == null)
        {
            Console.WriteLine($"  SKIP {label}");
            skipped++;
            continue;
        }

        string? tempDir = null;
        try
        {
            // Setup
            tempDir = FixtureManager.SetupTempDir(row.RdpSettings, row.FileCount);

            // Build args and stdin
            string cliArgs = TestCase.BuildCliArgs(row, tempDir);
            string? stdin = TestCase.BuildStdin(row);

            // Resolve TWO_WINDOW_FIRST placeholder:
            // Run a non-interactive dry run to count one-window options, then use count + 1.
            if (stdin != null && stdin.Contains("TWO_WINDOW_FIRST"))
            {
                string dryArgs = TestCase.BuildCliArgs(row with { FileCount = "zero" }, tempDir);
                string? dryStdin = row.ResolutionArg == "picker" ? TestCase.PickerSelection + "\n1\nL\n" : "1\nL\n";
                var dryResult = RunPs1(ps1Path, dryArgs, dryStdin);
                if (dryResult.ExitCode != 0)
                    throw new InvalidOperationException($"Dry-run exited with code {dryResult.ExitCode}: {dryResult.Stderr}");
                int oneWindowCount = CountOptionLines(dryResult.Stdout, OneRdpSectionMarker);
                if (oneWindowCount == 0)
                    throw new InvalidOperationException("Dry-run produced no one-window options for two_window test");
                stdin = stdin.Replace("TWO_WINDOW_FIRST", (oneWindowCount + 1).ToString());
            }

            // Run
            var result = RunPs1(ps1Path, cliArgs, stdin);

            // Assert
            var assertResults = Assertions.AssertAll(row, result, tempDir, realMonitor);
            var failedAsserts = assertResults.Where(r => !r.Passed).ToList();

            if (failedAsserts.Count == 0)
            {
                Console.WriteLine($"  PASS {label}");
                passed++;
            }
            else
            {
                Console.WriteLine($"  FAIL {label}");
                foreach (var f in failedAsserts)
                    Console.WriteLine($"       {f.Message}");
                failed++;
                failures.Add((i + 1, row, assertResults));
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  ERROR {label}: {ex.Message}");
            failed++;
            var errorResult = new Assertions.AssertResult(false, ex.ToString());
            failures.Add((i + 1, row, new List<Assertions.AssertResult> { errorResult }));
        }
        finally
        {
            if (tempDir != null)
                FixtureManager.Cleanup(tempDir);
        }
    }

    Console.WriteLine();
    Console.WriteLine($"Results: {passed} passed, {failed} failed, {skipped} skipped out of {rows.Count}");

    if (failures.Count > 0)
    {
        Console.WriteLine();
        Console.WriteLine("=== FAILURES ===");
        foreach (var (index, row, results) in failures)
        {
            Console.WriteLine($"\n  Test {index}: {FormatTestLabel(row)}");
            foreach (var r in results.Where(r => !r.Passed))
                Console.WriteLine($"    {r.Message}");
        }
    }

    return failed;
}

static ProcessRunner.RunResult RunPs1(string ps1Path, string args, string? stdin)
{
    // PowerShell -File mode: args are treated literally (no @ splatting issues),
    // Write-Host output goes to stdout when captured via ProcessStartInfo
    return ProcessRunner.Run("powershell.exe", $"-NoProfile -File \"{ps1Path}\" {args}", stdin);
}

static string FormatTestLabel(TestCase.PictRow row) =>
    $"{row.Monitor} | {row.ResolutionArg} | {row.MonitorResSel} | {row.Side} | {row.FileCount} | {row.FileSel} | {row.RdpSettings}";

static int CountOptionLines(string stdout, string sectionMarker)
{
    var lines = stdout.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
    bool inSection = false;
    bool sectionFound = false;
    int count = 0;
    foreach (string line in lines)
    {
        if (line.Contains($"--- Available monitor resolutions for {sectionMarker}"))
        {
            inSection = true;
            sectionFound = true;
            continue;
        }
        if (inSection && line.Trim().StartsWith("---"))
            break;
        if (inSection && Regex.IsMatch(line.Trim(), @"^\*?\d+x\d+,"))
            count++;
    }
    if (!sectionFound)
        throw new InvalidOperationException($"Section marker '{sectionMarker}' not found in output");
    return count;
}
