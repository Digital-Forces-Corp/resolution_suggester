param(
    [string]$BaseRdpPath = (Join-Path $PSScriptRoot 'ticket_highest_speed.rdp'),
    [string]$OutputCsvPath = (Join-Path $PSScriptRoot ("rdp-window-probe-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))),
    [string]$TargetAddress = '',
    [int[]]$SmartSizingValues = @(0, 1),
    # screen mode id is always 1 (windowed); id=2 is fullscreen and takes over the whole screen, making window measurement meaningless
    [int[]]$WinposShowCmdValues = @(1, 3),
    [string[]]$WinposSizes = @('800x600', '1600x1200'),
    [string[]]$SmartSize125Values = @('no', 'yes'),
    [int]$SettleMilliseconds = 2000,
    [switch]$ListOnly,
    [switch]$KeepTempFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Variable -Name ExtraChrome     -Option Constant -Value 100   # extra px added to winposstr width/height to give MSTSC room to breathe
Set-Variable -Name WaitTimeoutMs   -Option Constant -Value 10000  # ms to wait for the session window to become ready
Set-Variable -Name RetryIntervalMs -Option Constant -Value 200    # polling interval inside Wait-ForProbeWindow
Set-Variable -Name RetryCount      -Option Constant -Value 3      # attempts for the per-case retry loop
Set-Variable -Name ProbeTempDir    -Option Constant -Value (Join-Path $env:TEMP 'rdp_window_probe')

function ConvertTo-SizeSpec([string]$Spec) {
    if ($Spec -notmatch '^(\d+)x(\d+)$') {
        throw "Invalid size spec '$Spec'. Use WxH, e.g. 800x600."
    }

    return [PSCustomObject]@{
        Width = [int]$Matches[1]
        Height = [int]$Matches[2]
    }
}

function ConvertTo-YesNoValue([string]$Value) {
    $normalized = $Value.Trim().ToLowerInvariant()
    if ($normalized -ne 'yes' -and $normalized -ne 'no') {
        throw "Invalid yes/no value '$Value'. Use 'yes' or 'no'."
    }

    return $normalized
}

function Set-RdpSettingLine([System.Collections.Generic.List[string]]$Lines, [string]$Line) {
    $key = $Line.Split(':')[0]
    $pattern = "^$([regex]::Escape($key)):"
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $pattern) {
            $Lines[$i] = $Line
            return
        }
    }

    $Lines.Add($Line)
}

function Get-ProbeCases(
    [int[]]$SmartSizingList,
    [int[]]$WinposShowCmdList,
    [string[]]$WinposSizeList,
    [string[]]$SmartSize125List
) {
    $cases = [System.Collections.Generic.List[object]]::new()
    $caseNumber = 1

    foreach ($smartSizing in $SmartSizingList) {
        foreach ($showCmd in $WinposShowCmdList) {
            foreach ($sizeSpec in $WinposSizeList) {
                $size = ConvertTo-SizeSpec $sizeSpec
                $smartSize125Options = if ($smartSizing -eq 1) { $SmartSize125List } else { @('no') }
                foreach ($smartSize125 in $smartSize125Options) {
                    $smartSize125Normalized = if ($smartSizing -eq 1) { ConvertTo-YesNoValue $smartSize125 } else { 'no' }
                    $cases.Add([PSCustomObject]@{
                        CaseNumber = $caseNumber
                        SmartSizing = $smartSizing
                        WinposShowCmd = $showCmd
                        WinposWidth = $size.Width
                        WinposHeight = $size.Height
                        WinposSpec = $sizeSpec
                        SmartSize125 = $smartSize125Normalized
                    })
                    $caseNumber++
                }
            }
        }
    }

    return $cases
}

function Test-IsProbeWindowReady([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $false
    }
    return $Title.IndexOf('security warning', [System.StringComparison]::OrdinalIgnoreCase) -lt 0
}

function Wait-ForProbeWindow([System.Diagnostics.Process]$Process, [string]$TitleToken, [int]$TimeoutMilliseconds = $WaitTimeoutMs) {
    $seenTitles = [System.Collections.Generic.List[string]]::new()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($true) {
        if ($watch.ElapsedMilliseconds -gt $TimeoutMilliseconds) {
            $seenList = $seenTitles -join ' | '
            $message = "Timed out after ${TimeoutMilliseconds}ms waiting for session window with title token '$TitleToken'. Seen titles: '$seenList'"
            $ex = [System.InvalidOperationException]::new($message)
            $ex.Data['SeenTitles'] = $seenList
            throw $ex
        }

        if (-not $Process.HasExited) {
            $scan = [RdpWindowProbe]::ScanProcessWindows($Process.Id, $TitleToken)
            foreach ($t in $scan.Titles) {
                if ($seenTitles.Count -eq 0 -or $seenTitles[$seenTitles.Count - 1] -ne $t) {
                    $seenTitles.Add($t)
                }
            }
            if ($scan.SessionHandle -ne [IntPtr]::Zero) {
                try {
                    $snapshot = [RdpWindowProbe]::CaptureWindow($scan.SessionHandle)
                    if (Test-IsProbeWindowReady $snapshot.Title) {
                        return [PSCustomObject]@{
                            Handle = $scan.SessionHandle
                            Snapshot = $snapshot
                            SeenTitles = $seenTitles -join ' | '
                        }
                    }
                }
                catch {
                }
            }
        }

        Start-Sleep -Milliseconds $RetryIntervalMs
    }
}

function Stop-MstscProcess([System.Diagnostics.Process]$Process) {
    if ($null -ne $Process) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $BaseRdpPath)) {
    throw "Base RDP file not found: $BaseRdpPath"
}

$cases = @(Get-ProbeCases -SmartSizingList $SmartSizingValues -WinposShowCmdList $WinposShowCmdValues -WinposSizeList $WinposSizes -SmartSize125List $SmartSize125Values)

if ($ListOnly) {
    $cases | Format-Table SmartSizing, WinposShowCmd, WinposSpec, SmartSize125 -AutoSize
    return
}

$hostWindowsVersion = [System.Environment]::OSVersion.Version.ToString()

$source = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class RdpWindowProbe
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    public static bool EnablePerMonitorV2DpiAwareness()
    {
        try
        {
            if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2))
                return true;
        }
        catch { }
        try
        {
            IntPtr prev = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
            return prev != IntPtr.Zero;
        }
        catch { }
        return false;
    }

    public class WindowSnapshot
    {
        public WindowSnapshot()
        {
            Title = "";
        }

        public string Title { get; set; }
        public int OuterWidth { get; set; }
        public int OuterHeight { get; set; }
        public int ClientWidth { get; set; }
        public int ClientHeight { get; set; }
    }

    public class ScanResult
    {
        public ScanResult()
        {
            Titles = new List<string>();
            SessionHandle = IntPtr.Zero;
        }

        public IntPtr SessionHandle { get; set; }
        public List<string> Titles { get; set; }
    }

    private static readonly string[] SessionWindowClasses = new[]
    {
        "TscShellContainerClass",
        "IHWindowClass",
        "OPWindowClass"
    };

    public static ScanResult ScanProcessWindows(int processId, string sessionTitleToken)
    {
        var result = new ScanResult();
        int bestArea = 0;
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd))
                return true;

            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if ((int)pid != processId)
                return true;

            string title = GetWindowCaption(hwnd);
            if (!string.IsNullOrWhiteSpace(title))
                result.Titles.Add(title);

            string cls = GetWindowClass(hwnd);
            bool isSessionClass = false;
            for (int i = 0; i < SessionWindowClasses.Length; i++)
            {
                if (string.Equals(cls, SessionWindowClasses[i], StringComparison.OrdinalIgnoreCase))
                {
                    isSessionClass = true;
                    break;
                }
            }
            if (!isSessionClass)
                return true;

            if (!string.IsNullOrEmpty(sessionTitleToken) &&
                title.IndexOf(sessionTitleToken, StringComparison.OrdinalIgnoreCase) < 0)
                return true;

            RECT rect;
            if (!GetWindowRect(hwnd, out rect))
                return true;

            int width = Math.Max(0, rect.Right - rect.Left);
            int height = Math.Max(0, rect.Bottom - rect.Top);
            int area = width * height;
            if (area > bestArea)
            {
                bestArea = area;
                result.SessionHandle = hwnd;
            }
            return true;
        }, IntPtr.Zero);

        return result;
    }

    public static WindowSnapshot CaptureWindow(IntPtr hwnd)
    {
        RECT outerRect;
        if (!GetWindowRect(hwnd, out outerRect))
            throw new InvalidOperationException("GetWindowRect failed.");

        RECT clientRect;
        if (!GetClientRect(hwnd, out clientRect))
            throw new InvalidOperationException("GetClientRect failed.");

        return new WindowSnapshot
        {
            Title = GetWindowCaption(hwnd),
            OuterWidth = Math.Max(0, outerRect.Right - outerRect.Left),
            OuterHeight = Math.Max(0, outerRect.Bottom - outerRect.Top),
            ClientWidth = Math.Max(0, clientRect.Right - clientRect.Left),
            ClientHeight = Math.Max(0, clientRect.Bottom - clientRect.Top)
        };
    }

    public static void ResizeWindowKeepPosition(IntPtr hwnd, int width, int height)
    {
        const uint SWP_NOMOVE = 0x0002;
        const uint SWP_NOZORDER = 0x0004;
        const uint SWP_NOACTIVATE = 0x0010;

        if (!SetWindowPos(hwnd, IntPtr.Zero, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
            throw new InvalidOperationException("SetWindowPos failed.");
    }

    public static string GetWindowClass(IntPtr hwnd)
    {
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    private static string GetWindowCaption(IntPtr hwnd)
    {
        var sb = new StringBuilder(512);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }
}
"@

if (-not ('RdpWindowProbe' -as [type])) {
    Add-Type -TypeDefinition $source -Language CSharp
}

$null = [RdpWindowProbe]::EnablePerMonitorV2DpiAwareness()

$baseLines = [System.Collections.Generic.List[string]]::new([string[]]@(Get-Content -LiteralPath $BaseRdpPath -Encoding Unicode))
Set-RdpSettingLine $baseLines 'redirectsmartcards:i:0'
Set-RdpSettingLine $baseLines 'redirectwebauthn:i:0'
Set-RdpSettingLine $baseLines 'redirectclipboard:i:0'
Set-RdpSettingLine $baseLines 'drivestoredirect:s:'
if ($TargetAddress -ne '') {
    Set-RdpSettingLine $baseLines "full address:s:$TargetAddress"
}

$effectiveTargetIP = $TargetAddress
if ([string]::IsNullOrEmpty($effectiveTargetIP)) {
    $fullAddressLine = $baseLines | Where-Object { $_ -match '^full address:s:' } | Select-Object -First 1
    if ($fullAddressLine) {
        $effectiveTargetIP = $fullAddressLine.Substring('full address:s:'.Length)
    }
}

if (-not (Test-Path -LiteralPath $ProbeTempDir)) {
    $null = New-Item -ItemType Directory -Path $ProbeTempDir
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($case in $cases) {
    $probePath = Join-Path $ProbeTempDir ("case-{0:00}.rdp" -f $case.CaseNumber)
    $probeLines = [System.Collections.Generic.List[string]]::new($baseLines)
    $probeWinposWidth = $case.WinposWidth + $ExtraChrome
    $probeWinposHeight = $case.WinposHeight + $ExtraChrome

    Set-RdpSettingLine $probeLines "smart sizing:i:$($case.SmartSizing)"
    Set-RdpSettingLine $probeLines 'screen mode id:i:1'
    Set-RdpSettingLine $probeLines "winposstr:s:0,$($case.WinposShowCmd),0,0,$probeWinposWidth,$probeWinposHeight"

    $probeLines | Set-Content -LiteralPath $probePath -Encoding Unicode

    $titleToken = [System.IO.Path]::GetFileNameWithoutExtension($probePath)
    Write-Host ("[{0}/{1}] smart sizing={2}, winpos showCmd={3}, winpos={4}, smart_size_125={5}" -f $case.CaseNumber, $cases.Count, $case.SmartSizing, $case.WinposShowCmd, $case.WinposSpec, $case.SmartSize125)

    $snapshot = $null
    $readyWindow = $null
    $errorText = ''
    $seenTitlesText = ''

    for ($caseAttempt = 1; $caseAttempt -le $RetryCount; $caseAttempt++) {
        $process = $null
        $readyWindow = $null
        $snapshot = $null
        $seenTitlesText = ''
        $errorText = ''
        $isLastAttempt = $caseAttempt -ge $RetryCount
        try {
            $process = Start-Process -FilePath 'mstsc.exe' -ArgumentList "`"$probePath`"" -PassThru
            $readyWindow = Wait-ForProbeWindow -Process $process -TitleToken $titleToken

            if ($case.SmartSize125 -eq 'yes') {
                $targetOuterWidth = [int][Math]::Ceiling($readyWindow.Snapshot.OuterWidth * 1.25)
                $targetOuterHeight = [int][Math]::Ceiling($readyWindow.Snapshot.OuterHeight * 1.25)
                [RdpWindowProbe]::ResizeWindowKeepPosition($readyWindow.Handle, $targetOuterWidth, $targetOuterHeight)
                Start-Sleep -Milliseconds ([int]($SettleMilliseconds / 2))
                $snapshot = [RdpWindowProbe]::CaptureWindow($readyWindow.Handle)
            }
            else {
                $snapshot = $readyWindow.Snapshot
            }
        }
        catch {
            $errorText = $_.Exception.Message
            $dataTitles = $_.Exception.Data['SeenTitles']
            if ($null -ne $dataTitles) {
                $seenTitlesText = $dataTitles
            }
        }
        finally {
            Stop-MstscProcess $process
        }

        if ($null -ne $snapshot) { break }

        if ($isLastAttempt) {
            Write-Warning "Case $($case.CaseNumber) failed after $RetryCount attempts: $errorText"
        }
        else {
            Write-Warning "Case $($case.CaseNumber) attempt $caseAttempt/$RetryCount failed: $errorText. Retrying..."
        }
    }

    if (-not $KeepTempFiles) {
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
    }

    $windowTitle = if ($null -ne $readyWindow) { $readyWindow.SeenTitles } else { $seenTitlesText }
    $outerWidth = $null
    $outerHeight = $null
    $clientWidth = $null
    $clientHeight = $null
    if ($snapshot) {
        $outerWidth = $snapshot.OuterWidth
        $outerHeight = $snapshot.OuterHeight
        $clientWidth = $snapshot.ClientWidth
        $clientHeight = $snapshot.ClientHeight
    }

    $results.Add([PSCustomObject]@{
        TargetIP = $effectiveTargetIP
        HostWindowsVersion = $hostWindowsVersion
        SmartSizing = $case.SmartSizing
        'sz*1.25' = $case.SmartSize125
        WinposShowCmd = $case.WinposShowCmd
        WinposWidth = $probeWinposWidth
        WinposHeight = $probeWinposHeight
        OuterWidth = $outerWidth
        OuterHeight = $outerHeight
        ClientWidth = $clientWidth
        ClientHeight = $clientHeight
        WindowTitle = $windowTitle
        Error = $errorText
    })
}

$outputDir = Split-Path -Parent $OutputCsvPath
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    $null = New-Item -ItemType Directory -Path $outputDir
}

$results | Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host "Wrote probe results to $OutputCsvPath"
if ($KeepTempFiles) {
    Write-Host "Kept generated .rdp files in $ProbeTempDir"
}
