static class FixtureManager
{
    public const string FileCountOne = "one";
    public const string FileCountTwo = "two";
    public const string FileCountDirectory = "directory";
    public const string FileCountNonexistent = "nonexistent";
    public const string FileCountZero = "zero";

    static readonly string FixturesDir = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "fixtures"));

    public static string SetupTempDir(string rdpSettings, string fileCount)
    {
        string tempDir = Path.Combine(Path.GetTempPath(), "res_suggest_test_" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(tempDir);

        string fixtureFile = rdpSettings switch
        {
            "all_present" => "test1.rdp",
            "none_present" => "test2.rdp",
            "partial" => "test1_partial.rdp",
            _ => throw new ArgumentException($"Unknown RdpSettings: {rdpSettings}")
        };

        if (fileCount == FileCountNonexistent || fileCount == FileCountZero)
            return tempDir;

        string sourceFile = Path.Combine(FixturesDir, fixtureFile);

        if (fileCount == FileCountDirectory)
        {
            string subdir = Path.Combine(tempDir, "testdir");
            Directory.CreateDirectory(subdir);
            File.Copy(sourceFile, Path.Combine(subdir, "test1.rdp"));
            // Second file always uses test2.rdp (none_present) so we can verify which was modified
            File.Copy(Path.Combine(FixturesDir, "test2.rdp"), Path.Combine(subdir, "test2.rdp"));
            return tempDir;
        }

        if (fileCount == FileCountOne)
        {
            File.Copy(sourceFile, Path.Combine(tempDir, "test1.rdp"));
            return tempDir;
        }

        if (fileCount == FileCountTwo)
        {
            File.Copy(sourceFile, Path.Combine(tempDir, "test1.rdp"));
            File.Copy(Path.Combine(FixturesDir, "test2.rdp"), Path.Combine(tempDir, "test2.rdp"));
            return tempDir;
        }

        throw new ArgumentException($"Unknown fileCount: {fileCount}");
    }

    public static void Cleanup(string tempDir)
    {
        try { Directory.Delete(tempDir, true); } catch (Exception ex) { Console.Error.WriteLine($"WARNING: Failed to delete temp dir {tempDir}: {ex.Message}"); }
    }
}
