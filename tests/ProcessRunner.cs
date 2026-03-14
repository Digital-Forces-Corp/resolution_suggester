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

        using var process = Process.Start(psi) ?? throw new InvalidOperationException($"Failed to start process: {exePath}");

        if (stdinInput != null)
        {
            process.StandardInput.Write(stdinInput);
            process.StandardInput.Close();
        }
        else
        {
            process.StandardInput.Close();
        }

        // Read both streams asynchronously to avoid pipe-buffer deadlock
        var stderrTask = Task.Run(() => process.StandardError.ReadToEnd());
        var stdoutTask = Task.Run(() => process.StandardOutput.ReadToEnd());

        if (!process.WaitForExit(timeoutMs))
        {
            process.Kill();
            process.WaitForExit();
            throw new TimeoutException($"Process timed out after {timeoutMs}ms");
        }
        process.WaitForExit(); // flush async buffers

        string stdout = stdoutTask.Result;
        string stderr = stderrTask.Result;

        return new RunResult(process.ExitCode, stdout, stderr);
    }
}
