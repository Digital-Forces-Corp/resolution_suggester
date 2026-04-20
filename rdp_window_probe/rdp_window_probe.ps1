param(
    [string]$BaseRdpPath = (Join-Path $PSScriptRoot 'ticket_highest_speed.rdp'),
    [string]$OutputCsvPath = (Join-Path $PSScriptRoot ("rdp-window-probe-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))),
    [string]$TargetAddress = '',
    [switch]$SingleCase,
    [int]$SmartSizing = 0,
    [int]$WinposShowCmd = 1,
    [string]$WinposSize = '800x600',
    [string]$SmartSize125 = 'no',
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

Set-Variable -Name ExtraChrome -Option Constant -Value 100

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

function New-ProbeCase(
    [int]$CaseNumber,
    [int]$SmartSizingValue,
    [int]$WinposShowCmdValue,
    [string]$WinposSizeValue,
    [string]$SmartSize125Value
) {
    $size = ConvertTo-SizeSpec $WinposSizeValue
    $smartSize125Normalized = if ($SmartSizingValue -eq 1) {
        ConvertTo-YesNoValue $SmartSize125Value
    }
    else {
        'no'
    }

    return [PSCustomObject]@{
        CaseNumber = $CaseNumber
        SmartSizing = $SmartSizingValue
        WinposShowCmd = $WinposShowCmdValue
        WinposWidth = $size.Width
        WinposHeight = $size.Height
        WinposSpec = $WinposSizeValue
        SmartSize125 = $smartSize125Normalized
    }
}

function Get-ProbeCases {
    $cases = [System.Collections.Generic.List[object]]::new()
    $caseNumber = 1

    if ($useSingleCase) {
        $cases.Add((New-ProbeCase -CaseNumber $caseNumber -SmartSizingValue $SmartSizing -WinposShowCmdValue $WinposShowCmd -WinposSizeValue $WinposSize -SmartSize125Value $SmartSize125))
        return $cases
    }

    foreach ($smartSizing in $SmartSizingValues) {
        foreach ($showCmd in $WinposShowCmdValues) {
            foreach ($sizeSpec in $WinposSizes) {
                $smartSize125Options = if ($smartSizing -eq 1) { $SmartSize125Values } else { @('no') }
                foreach ($smartSize125 in $smartSize125Options) {
                    $cases.Add((New-ProbeCase -CaseNumber $caseNumber -SmartSizingValue $smartSizing -WinposShowCmdValue $showCmd -WinposSizeValue $sizeSpec -SmartSize125Value $smartSize125))
                    $caseNumber++
                }
            }
        }
    }

    return $cases
}

function Get-PropertyOrNull([object]$Object, [string]$Property) {
    if ($null -ne $Object) { return $Object.$Property }
    return $null
}

function Select-ProbeOutput([object[]]$Results, [switch]$ForConsole) {
    $properties = @(
        'TargetIP',
        'HostWindowsVersion',
        'SmartSizing',
        'sz*1.25',
        'WinposShowCmd',
        'WinposWidth',
        'WinposHeight',
        'OuterWidth',
        'OuterHeight',
        'ClientWidth',
        'ClientHeight',
        'Error'
    )

    if (-not $ForConsole) {
        $properties += 'WindowTitle'
    }

    return $Results | Select-Object $properties
}

function Test-IsSecurityWarningTitle([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $false
    }

    return $Title.IndexOf('security warning', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Test-IsProbeWindowReady([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) {
        return $false
    }

    if (Test-IsSecurityWarningTitle $Title) {
        return $false
    }

    # The bare "Remote Desktop Connection" title belongs to the transient boot-stub
    # window that gets destroyed once the real session window opens. Wait for the
    # session window, whose title is prefixed with the .rdp filename and address
    # (e.g. "case-07 - 192.168.44.101 - Remote Desktop Connection").
    $trimmed = $Title.Trim()
    if ([string]::Equals($trimmed, 'Remote Desktop Connection', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    return $trimmed.IndexOf('Remote Desktop Connection', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Wait-ForProbeWindow([System.Diagnostics.Process]$Process, [string]$TitleToken, [int]$TimeoutMilliseconds = 10000) {
    $seenTitles = [System.Collections.Generic.List[string]]::new()
    $lastWindowTitle = ''
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($true) {
        if ($watch.ElapsedMilliseconds -gt $TimeoutMilliseconds) {
            $seenList = $seenTitles -join ' | '
            $message = "Timed out after ${TimeoutMilliseconds}ms waiting for session window with title token '$TitleToken'. Seen titles: '$seenList'"
            $ex = [System.InvalidOperationException]::new($message)
            $ex.Data['SeenTitles'] = $seenList
            throw $ex
        }

        $hwnd = [RdpWindowProbe]::FindBestWindowByTitleToken($TitleToken, 0)
        if ($hwnd -ne [IntPtr]::Zero) {
            try {
                $snapshot = [RdpWindowProbe]::CaptureWindow($hwnd)
                $lastWindowTitle = $snapshot.Title
                if ($lastWindowTitle -and ($seenTitles.Count -eq 0 -or $seenTitles[$seenTitles.Count - 1] -ne $lastWindowTitle)) {
                    $seenTitles.Add($lastWindowTitle)
                }
                if (Test-IsProbeWindowReady $snapshot.Title) {
                    return [PSCustomObject]@{
                        Handle = $hwnd
                        Snapshot = $snapshot
                        SeenTitles = $seenTitles -join ' | '
                    }
                }
            }
            catch {
            }
        }

        Start-Sleep -Milliseconds 200
    }
}

function Stop-MstscProcess([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process) {
        return
    }

    try {
        if ($Process.HasExited) {
            return
        }
    }
    catch {
        return
    }

    try {
        $null = $Process.CloseMainWindow()
        if ($Process.WaitForExit(5000)) {
            return
        }
    }
    catch {
    }

    try {
        Stop-Process -Id $Process.Id -Force -ErrorAction Stop
    }
    catch {
    }
}

if (-not (Test-Path -LiteralPath $BaseRdpPath)) {
    throw "Base RDP file not found: $BaseRdpPath"
}

$singleCaseParameterNames = @('SmartSizing', 'WinposShowCmd', 'WinposSize', 'SmartSize125')
$matrixParameterNames = @('SmartSizingValues', 'WinposShowCmdValues', 'WinposSizes', 'SmartSize125Values')
$useSingleCase = $SingleCase -or @($singleCaseParameterNames | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0
if ($useSingleCase) {
    $conflictingMatrixParameters = @($matrixParameterNames | Where-Object { $PSBoundParameters.ContainsKey($_) })
    if ($conflictingMatrixParameters.Count -gt 0) {
        throw "Do not combine single-case parameters with matrix parameters: $($conflictingMatrixParameters -join ', ')"
    }
}

$cases = @(Get-ProbeCases)
if ($ListOnly) {
    $cases | Format-Table SmartSizing, WinposShowCmd, WinposSpec, SmartSize125 -AutoSize
    return
}

$hostWindowsVersion = Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Version

$source = @"
using System;
using System.Collections.Generic;
using System.Linq;
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
    private static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

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

    public class WindowInfo
    {
        public WindowInfo()
        {
            WindowClass = "";
        }

        public string WindowClass { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int Area { get; set; }
    }

    public class WindowSnapshot
    {
        public WindowSnapshot()
        {
            Title = "";
            ChildSummary = "";
            WindowClass = "";
        }

        public string Title { get; set; }
        public string WindowClass { get; set; }
        public int OuterWidth { get; set; }
        public int OuterHeight { get; set; }
        public int ClientWidth { get; set; }
        public int ClientHeight { get; set; }
        public int VisibleChildCount { get; set; }
        public string ChildSummary { get; set; }
        public WindowInfo LargestVisibleChild { get; set; }
    }

    private static readonly string[] SessionWindowClasses = new[]
    {
        "TscShellContainerClass",
        "IHWindowClass",
        "OPWindowClass"
    };

    public static IntPtr FindBestWindowForProcess(int processId)
    {
        return FindBestWindowByTitleToken(null, processId);
    }

    public static IntPtr FindBestWindowByTitleToken(string titleToken, int processId)
    {
        IntPtr bestHandle = IntPtr.Zero;
        int bestArea = 0;
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd))
                return true;

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

            if (!string.IsNullOrEmpty(titleToken))
            {
                string title = GetWindowCaption(hwnd);
                if (title.IndexOf(titleToken, StringComparison.OrdinalIgnoreCase) < 0)
                    return true;
            }
            else if (processId > 0)
            {
                uint pid;
                GetWindowThreadProcessId(hwnd, out pid);
                if ((int)pid != processId)
                    return true;
            }

            RECT rect;
            if (!GetWindowRect(hwnd, out rect))
                return true;

            int width = Math.Max(0, rect.Right - rect.Left);
            int height = Math.Max(0, rect.Bottom - rect.Top);
            int area = width * height;
            if (area > bestArea)
            {
                bestArea = area;
                bestHandle = hwnd;
            }
            return true;
        }, IntPtr.Zero);

        return bestHandle;
    }

    public static WindowSnapshot CaptureWindow(IntPtr hwnd)
    {
        RECT outerRect;
        if (!GetWindowRect(hwnd, out outerRect))
            throw new InvalidOperationException("GetWindowRect failed.");

        RECT clientRect;
        if (!GetClientRect(hwnd, out clientRect))
            throw new InvalidOperationException("GetClientRect failed.");

        var visibleChildren = new List<WindowInfo>();
        EnumChildWindows(hwnd, (childHwnd, _) =>
        {
            if (!IsWindowVisible(childHwnd))
                return true;

            RECT childRect;
            if (!GetWindowRect(childHwnd, out childRect))
                return true;

            int width = Math.Max(0, childRect.Right - childRect.Left);
            int height = Math.Max(0, childRect.Bottom - childRect.Top);
            int area = width * height;
            if (area == 0)
                return true;

            visibleChildren.Add(new WindowInfo
            {
                WindowClass = GetWindowClass(childHwnd),
                Left = childRect.Left,
                Top = childRect.Top,
                Width = width,
                Height = height,
                Area = area
            });
            return true;
        }, IntPtr.Zero);

        var sortedChildren = visibleChildren.OrderByDescending(c => c.Area).ToList();

        WindowInfo largestVisibleChild = sortedChildren.FirstOrDefault();

        string childSummary = string.Join(" | ", sortedChildren
            .Take(8)
            .Select(c => string.Format("{0}:{1}x{2}@{3},{4}", c.WindowClass, c.Width, c.Height, c.Left, c.Top)));

        return new WindowSnapshot
        {
            Title = GetWindowCaption(hwnd),
            WindowClass = GetWindowClass(hwnd),
            OuterWidth = Math.Max(0, outerRect.Right - outerRect.Left),
            OuterHeight = Math.Max(0, outerRect.Bottom - outerRect.Top),
            ClientWidth = Math.Max(0, clientRect.Right - clientRect.Left),
            ClientHeight = Math.Max(0, clientRect.Bottom - clientRect.Top),
            VisibleChildCount = visibleChildren.Count,
            LargestVisibleChild = largestVisibleChild,
            ChildSummary = childSummary
        };
    }

    public static void GetOuterSize(IntPtr hwnd, out int width, out int height)
    {
        RECT rect;
        if (!GetWindowRect(hwnd, out rect))
            throw new InvalidOperationException("GetWindowRect failed.");
        width = Math.Max(0, rect.Right - rect.Left);
        height = Math.Max(0, rect.Bottom - rect.Top);
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

if (-not ('RdpDpiAwareness' -as [type])) {
    Add-Type -Namespace '' -Name 'RdpDpiAwareness' -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool SetProcessDpiAwarenessContext(System.IntPtr ctx);
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern System.IntPtr SetThreadDpiAwarenessContext(System.IntPtr ctx);
"@
}

try {
    $perMonitorV2 = [IntPtr]::new(-4)
    $null = [RdpDpiAwareness]::SetProcessDpiAwarenessContext($perMonitorV2)
    $null = [RdpDpiAwareness]::SetThreadDpiAwarenessContext($perMonitorV2)
}
catch {
}

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
$probeRoot = $PSScriptRoot
$results = [System.Collections.Generic.List[object]]::new()

try {
    foreach ($case in $cases) {
        $probePath = Join-Path $probeRoot ("case-{0:00}.rdp" -f $case.CaseNumber)
        $probeLines = [System.Collections.Generic.List[string]]::new($baseLines)
        $probeWinposWidth = $case.WinposWidth + $ExtraChrome
        $probeWinposHeight = $case.WinposHeight + $ExtraChrome

        Set-RdpSettingLine $probeLines "smart sizing:i:$($case.SmartSizing)"
        Set-RdpSettingLine $probeLines 'screen mode id:i:1'  # always windowed; id=2 is fullscreen and makes window measurement meaningless
        Set-RdpSettingLine $probeLines "winposstr:s:0,$($case.WinposShowCmd),0,0,$probeWinposWidth,$probeWinposHeight"

        $probeLines | Set-Content -LiteralPath $probePath -Encoding Unicode

        $process = $null
        $readyWindow = $null
        $snapshot = $null
        $seenTitlesText = ''
        $errorText = ''
        $titleToken = [System.IO.Path]::GetFileNameWithoutExtension($probePath)
        Write-Host ("[{0}/{1}] smart sizing={2}, winpos showCmd={3}, winpos={4}, smart_size_125={5}" -f $case.CaseNumber, $cases.Count, $case.SmartSizing, $case.WinposShowCmd, $case.WinposSpec, $case.SmartSize125)
        try {
            $process = Start-Process -FilePath 'mstsc.exe' -ArgumentList "`"$probePath`"" -PassThru
            $readyWindow = Wait-ForProbeWindow -Process $process -TitleToken $titleToken
            if ($case.SmartSize125 -eq 'yes') {
                $resizeHwnd = [IntPtr]::Zero
                $preWidth = 0
                $preHeight = 0
                for ($resizeAttempt = 1; $resizeAttempt -le 10; $resizeAttempt++) {
                    $resizeHwnd = [RdpWindowProbe]::FindBestWindowByTitleToken($titleToken, 0)
                    if ($resizeHwnd -ne [IntPtr]::Zero) {
                        try {
                            [RdpWindowProbe]::GetOuterSize($resizeHwnd, [ref]$preWidth, [ref]$preHeight)
                            break
                        }
                        catch {
                            $resizeHwnd = [IntPtr]::Zero
                        }
                    }
                    Start-Sleep -Milliseconds 300
                }

                if ($resizeHwnd -eq [IntPtr]::Zero) {
                    throw "Unable to locate a stable mstsc window to resize for smart_size_125."
                }

                $targetOuterWidth = [int][Math]::Ceiling($preWidth * 1.25)
                $targetOuterHeight = [int][Math]::Ceiling($preHeight * 1.25)
                [RdpWindowProbe]::ResizeWindowKeepPosition($resizeHwnd, $targetOuterWidth, $targetOuterHeight)
                Start-Sleep -Milliseconds ([Math]::Max(500, [int]($SettleMilliseconds / 2)))
            }
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $hwnd = [RdpWindowProbe]::FindBestWindowByTitleToken($titleToken, 0)
                if ($hwnd -eq [IntPtr]::Zero) {
                    Start-Sleep -Milliseconds 300
                    continue
                }

                try {
                    $snapshot = [RdpWindowProbe]::CaptureWindow($hwnd)
                    if (-not (Test-IsProbeWindowReady $snapshot.Title)) {
                        $snapshot = $null
                        Start-Sleep -Milliseconds 300
                        continue
                    }
                    break
                }
                catch {
                    if ($attempt -ge 3) {
                        throw
                    }
                    Start-Sleep -Milliseconds 300
                }
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
            if (-not $KeepTempFiles) {
                Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            }
        }

        $results.Add([PSCustomObject]@{
            TargetIP = $effectiveTargetIP
            HostWindowsVersion = $hostWindowsVersion
            SmartSizing = $case.SmartSizing
            'sz*1.25' = $case.SmartSize125
            WinposShowCmd = $case.WinposShowCmd
            WinposWidth = $probeWinposWidth
            WinposHeight = $probeWinposHeight
            OuterWidth = Get-PropertyOrNull $snapshot 'OuterWidth'
            OuterHeight = Get-PropertyOrNull $snapshot 'OuterHeight'
            ClientWidth = Get-PropertyOrNull $snapshot 'ClientWidth'
            ClientHeight = Get-PropertyOrNull $snapshot 'ClientHeight'
            Error = $errorText
            WindowTitle = if ($null -ne $snapshot) {
                $readyWindow.SeenTitles
            }
            elseif ($null -ne $readyWindow) {
                $readyWindow.SeenTitles
            }
            else {
                $seenTitlesText
            }
        })
    }

    $outputDir = Split-Path -Parent $OutputCsvPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        $null = New-Item -ItemType Directory -Path $outputDir
    }

    Select-ProbeOutput -Results $results | Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation
    Select-ProbeOutput -Results $results -ForConsole |
        Format-Table -AutoSize
    Write-Host "Wrote probe results to $OutputCsvPath"
    if ($KeepTempFiles) {
        Write-Host "Kept generated .rdp files in $probeRoot"
    }
}
finally {
}
