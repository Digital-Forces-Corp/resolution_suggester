static class FixtureManager
{
    public const string FileCountOne = "one";
    public const string FileCountTwo = "two";
    public const string FileCountDirectory = "directory";
    public const string FileCountNonexistent = "nonexistent";
    public const string FileCountZero = "zero";

    public const string FixtureAllPresent = "test1.rdp";
    public const string FixtureNonePresent = "test2.rdp";
    public const string FixturePartial = "test1_partial.rdp";

    internal static readonly string FixturesDir = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "fixtures"));

    public static string SetupTempDir(string rdpSettings, string fileCount)
    {
        string tempDir = Path.Combine(Path.GetTempPath(), "res_suggest_test_" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(tempDir);

        string fixtureFile = rdpSettings switch
        {
            "all_present" => FixtureAllPresent,
            "none_present" => FixtureNonePresent,
            "partial" => FixturePartial,
            _ => throw new ArgumentException($"Unknown RdpSettings: {rdpSettings}")
        };

        if (fileCount == FileCountNonexistent || fileCount == FileCountZero)
            return tempDir;

        string sourceFile = Path.Combine(FixturesDir, fixtureFile);

        if (fileCount == FileCountDirectory)
        {
            string subdir = Path.Combine(tempDir, TestCase.FixtureTestDir);
            Directory.CreateDirectory(subdir);
            File.Copy(sourceFile, Path.Combine(subdir, TestCase.FixtureTest1));
            // Second file always uses test2.rdp (none_present) so we can verify which was modified
            File.Copy(Path.Combine(FixturesDir, TestCase.FixtureTest2), Path.Combine(subdir, TestCase.FixtureTest2));
            return tempDir;
        }

        if (fileCount == FileCountOne)
        {
            File.Copy(sourceFile, Path.Combine(tempDir, TestCase.FixtureTest1));
            return tempDir;
        }

        if (fileCount == FileCountTwo)
        {
            File.Copy(sourceFile, Path.Combine(tempDir, TestCase.FixtureTest1));
            File.Copy(Path.Combine(FixturesDir, TestCase.FixtureTest2), Path.Combine(tempDir, TestCase.FixtureTest2));
            return tempDir;
        }

        throw new ArgumentException($"Unknown fileCount: {fileCount}");
    }

    public static void Cleanup(string tempDir)
    {
        try { Directory.Delete(tempDir, true); } catch (Exception ex) { Console.Error.WriteLine($"WARNING: Failed to delete temp dir {tempDir}: {ex.Message}"); }
    }
}
