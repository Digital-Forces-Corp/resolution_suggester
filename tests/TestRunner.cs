using System.Text.RegularExpressions;

// Find the exe and PS1: build first, then locate in bin
string projectDir = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", ".."));
string repoRoot = Path.GetFullPath(Path.Combine(projectDir, ".."));
string exePath = Path.Combine(repoRoot, "src", "bin", "Debug", "net8.0-windows", "win-x64", "resolution_suggester.exe");
string ps1Path = Path.Combine(repoRoot, "resolutions_suggester.ps1");
string tsvPath = Path.Combine(projectDir, "pairwise-output.tsv");

if (!File.Exists(exePath))
{
    Console.WriteLine($"ERROR: exe not found at {exePath}");
    Console.WriteLine("Run: dotnet build src/resolution_suggester.csproj");
    return 1;
}

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

// Run tests against C# exe
Console.WriteLine();
Console.WriteLine("=== C# implementation ===");
totalFailed += RunTestSuite("csharp", rows, realMonitor, exePath, ps1Path, tsvPath);

// Run tests against PS1 script
Console.WriteLine();
Console.WriteLine("=== PowerShell implementation ===");
totalFailed += RunTestSuite("ps1", rows, realMonitor, exePath, ps1Path, tsvPath);

return totalFailed > 0 ? 1 : 0;

static int RunTestSuite(
    string impl,
    List<TestCase.PictRow> rows,
    MonitorOracle.MonitorData? realMonitor,
    string exePath,
    string ps1Path,
    string tsvPath)
{
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    var failures = new List<(int Index, TestCase.PictRow Row, List<Assertions.AssertResult> Results)>();

    for (int i = 0; i < rows.Count; i++)
    {
        var row = rows[i];
        string label = $"[{i + 1}/{rows.Count}] {row.Monitor} | {row.ResolutionArg} | {row.MonitorResSel} | {row.Side} | {row.FileCount} | {row.FileSel} | {row.RdpSettings}";

        // Skip real monitor tests if no monitor detected
        if (row.Monitor == "real" && realMonitor == null)
        {
            Console.WriteLine($"  SKIP {label}");
            skipped++;
            continue;
        }

        string tempDir = "";
        try
        {
            // Setup
            tempDir = FixtureManager.SetupTempDir(row.RdpSettings, row.FileCount);

            // Build args and stdin
            string cliArgs = TestCase.BuildCliArgs(row, tempDir, impl);
            string? stdin = TestCase.BuildStdin(row);

            // Resolve TWO_WINDOW_FIRST placeholder:
            // Run a non-interactive dry run to count one-window options, then use count + 1.
            if (stdin != null && stdin.Contains("TWO_WINDOW_FIRST"))
            {
                string dryArgs = TestCase.BuildCliArgs(row with { FileCount = "zero" }, tempDir, impl);
                string? dryStdin = row.ResolutionArg == "picker" ? "3\n" : null;
                var dryResult = RunImpl(impl, exePath, ps1Path, dryArgs, dryStdin);
                int oneWindowCount = CountOptionLines(dryResult.Stdout, "1 RDP");
                stdin = stdin.Replace("TWO_WINDOW_FIRST", (oneWindowCount + 1).ToString());
            }

            // Run
            var result = RunImpl(impl, exePath, ps1Path, cliArgs, stdin);

            // Assert
            var assertResults = Assertions.AssertAll(row, result, tempDir, realMonitor, impl);
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
        }
        finally
        {
            if (tempDir.Length > 0)
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
            Console.WriteLine($"\n  Test {index}: {row.Monitor} | {row.ResolutionArg} | {row.MonitorResSel} | {row.Side} | {row.FileCount} | {row.FileSel} | {row.RdpSettings}");
            foreach (var r in results.Where(r => !r.Passed))
                Console.WriteLine($"    {r.Message}");
        }
    }

    return failed;
}

static ProcessRunner.RunResult RunImpl(string impl, string exePath, string ps1Path, string args, string? stdin)
{
    if (impl == "ps1")
    {
        // PowerShell -File mode: args are treated literally (no @ splatting issues),
        // Write-Host output goes to stdout when captured via ProcessStartInfo
        return ProcessRunner.Run("powershell.exe", $"-NoProfile -File \"{ps1Path}\" {args}", stdin);
    }
    return ProcessRunner.Run(exePath, args, stdin);
}

static int CountOptionLines(string stdout, string sectionMarker)
{
    var lines = stdout.Split('\n');
    bool inSection = false;
    int count = 0;
    foreach (string line in lines)
    {
        if (line.Contains($"--- Available monitor resolutions for {sectionMarker}"))
        {
            inSection = true;
            continue;
        }
        if (inSection && line.TrimStart().StartsWith("---"))
            break;
        if (inSection && line.Trim().Length > 0)
            count++;
    }
    return count;
}
