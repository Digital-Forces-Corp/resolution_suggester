using System.Diagnostics;
using System.Text;

static class ProcessRunner
{
    public record RunResult(int ExitCode, string Stdout, string Stderr);

    public static RunResult Run(string exePath, string args, string? stdinInput = null, int timeoutMs = 10000)
    {
        var psi = new ProcessStartInfo
        {
            FileName = exePath,
            Arguments = args,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        using var process = Process.Start(psi)!;

        if (stdinInput != null)
        {
            process.StandardInput.Write(stdinInput);
            process.StandardInput.Close();
        }
        else
        {
            process.StandardInput.Close();
        }

        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();

        if (!process.WaitForExit(timeoutMs))
        {
            process.Kill();
            throw new TimeoutException($"Process timed out after {timeoutMs}ms. stdout so far: {stdout}");
        }

        return new RunResult(process.ExitCode, stdout, stderr);
    }
}
