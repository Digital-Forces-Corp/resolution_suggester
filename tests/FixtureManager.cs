using System.Text;

static class FixtureManager
{
    static readonly string FixturesDir = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "fixtures");

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

        string sourceFile = Path.Combine(FixturesDir, fixtureFile);

        if (fileCount == "directory")
        {
            string subdir = Path.Combine(tempDir, "testdir");
            Directory.CreateDirectory(subdir);
            File.Copy(sourceFile, Path.Combine(subdir, "test1.rdp"));
            // Second file always uses test2.rdp (none_present) so we can verify which was modified
            File.Copy(Path.Combine(FixturesDir, "test2.rdp"), Path.Combine(subdir, "test2.rdp"));
            return tempDir;
        }

        File.Copy(sourceFile, Path.Combine(tempDir, "test1.rdp"));

        if (fileCount == "two")
        {
            File.Copy(Path.Combine(FixturesDir, "test2.rdp"), Path.Combine(tempDir, "test2.rdp"));
        }

        return tempDir;
    }

    public static void Cleanup(string tempDir)
    {
        try { Directory.Delete(tempDir, true); } catch { }
    }
}
