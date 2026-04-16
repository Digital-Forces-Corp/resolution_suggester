param(
    [string]$BaseRdpPath = (Join-Path $PSScriptRoot 'ticket_highest_speed.rdp'),
    [string]$OutputCsvPath = (Join-Path $PSScriptRoot ("rdp-window-probe-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))),
    [string]$TargetAddress = '',
    [switch]$SingleCase,
    [int]$SmartSizing = 0,
    [int]$ScreenModeId = 1,
    [int]$WinposShowCmd = 1,
    [string]$WinposSize = '800x600',
    [string]$SmartSize125 = 'no',
    [int[]]$SmartSizingValues = @(0, 1),
    [int[]]$ScreenModeIds = @(1, 2),
    [int[]]$WinposShowCmdValues = @(1, 3),
    [string[]]$WinposSizes = @('800x600', '1600x1200'),
    [string[]]$SmartSize125Values = @('no', 'yes'),
    [int]$LaunchTimeoutSeconds = 20,
    [int]$SettleMilliseconds = 2500,
    [switch]$ListOnly,
    [switch]$KeepTempFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-SizeSpec([string]$Spec) {
    if ($Spec -notmatch '^(\d+)x(\d+)$') {
        throw "Invalid size spec '$Spec'. Use WxH, e.g. 800x600."
    }

    return [PSCustomObject]@{
        Width = [int]$Matches[1]
        Height = [int]$Matches[2]
        Spec = $Spec
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
    [int]$ScreenModeIdValue,
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
        ScreenModeId = $ScreenModeIdValue
        WinposShowCmd = $WinposShowCmdValue
        WinposWidth = $size.Width
        WinposHeight = $size.Height
        WinposSpec = $size.Spec
        SmartSize125 = $smartSize125Normalized
    }
}

function Get-ProbeCases {
    $cases = [System.Collections.Generic.List[object]]::new()
    $caseNumber = 1

    if ($useSingleCase) {
        $cases.Add((New-ProbeCase -CaseNumber $caseNumber -SmartSizingValue $SmartSizing -ScreenModeIdValue $ScreenModeId -WinposShowCmdValue $WinposShowCmd -WinposSizeValue $WinposSize -SmartSize125Value $SmartSize125))
        return $cases
    }

    foreach ($smartSizing in $SmartSizingValues) {
        foreach ($screenModeId in $ScreenModeIds) {
            foreach ($showCmd in $WinposShowCmdValues) {
                foreach ($sizeSpec in $WinposSizes) {
                    $smartSize125Options = if ($smartSizing -eq 1) { $SmartSize125Values } else { @('no') }
                    foreach ($smartSize125 in $smartSize125Options) {
                        $cases.Add((New-ProbeCase -CaseNumber $caseNumber -SmartSizingValue $smartSizing -ScreenModeIdValue $screenModeId -WinposShowCmdValue $showCmd -WinposSizeValue $sizeSpec -SmartSize125Value $smartSize125))
                        $caseNumber++
                    }
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

function Wait-ForMainWindow([System.Diagnostics.Process]$Process, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) {
            throw "mstsc exited before a main window was found."
        }

        try {
            $Process.Refresh()
        }
        catch {
        }

        $hwnd = [RdpWindowProbe]::FindBestWindowForProcess($Process.Id)
        if ($hwnd -ne [IntPtr]::Zero) {
            return $hwnd
        }

        Start-Sleep -Milliseconds 200
    }

    throw "Timed out waiting $TimeoutSeconds seconds for mstsc main window."
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

$singleCaseParameterNames = @('SmartSizing', 'ScreenModeId', 'WinposShowCmd', 'WinposSize', 'SmartSize125')
$matrixParameterNames = @('SmartSizingValues', 'ScreenModeIds', 'WinposShowCmdValues', 'WinposSizes', 'SmartSize125Values')
$useSingleCase = $SingleCase -or @($singleCaseParameterNames | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0
if ($useSingleCase) {
    $conflictingMatrixParameters = @($matrixParameterNames | Where-Object { $PSBoundParameters.ContainsKey($_) })
    if ($conflictingMatrixParameters.Count -gt 0) {
        throw "Do not combine single-case parameters with matrix parameters: $($conflictingMatrixParameters -join ', ')"
    }
}

$hostWindowsVersion = Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Version
$cases = @(Get-ProbeCases)
if ($ListOnly) {
    $cases | Format-Table SmartSizing, ScreenModeId, WinposShowCmd, WinposSpec, SmartSize125 -AutoSize
    return
}

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

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
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

    [DllImport("user32.dll")]
    private static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    public class WindowInfo
    {
        public WindowInfo()
        {
            WindowClass = "";
            Title = "";
        }

        public long Handle { get; set; }
        public string WindowClass { get; set; }
        public string Title { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Right { get; set; }
        public int Bottom { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int Area { get; set; }
    }

    private class WindowMatch
    {
        public IntPtr Handle { get; set; }
        public int Area { get; set; }
    }

    public class WindowSnapshot
    {
        public WindowSnapshot()
        {
            WindowClass = "";
            Title = "";
            ChildSummary = "";
        }

        public long Handle { get; set; }
        public string WindowClass { get; set; }
        public string Title { get; set; }
        public int OuterLeft { get; set; }
        public int OuterTop { get; set; }
        public int OuterRight { get; set; }
        public int OuterBottom { get; set; }
        public int OuterWidth { get; set; }
        public int OuterHeight { get; set; }
        public int ClientLeft { get; set; }
        public int ClientTop { get; set; }
        public int ClientRight { get; set; }
        public int ClientBottom { get; set; }
        public int ClientWidth { get; set; }
        public int ClientHeight { get; set; }
        public int VisibleChildCount { get; set; }
        public string ChildSummary { get; set; }
        public WindowInfo LargestVisibleChild { get; set; }
    }

    public static IntPtr FindBestWindowForProcess(int processId)
    {
        var matches = new List<WindowMatch>();
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd))
                return true;

            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid != processId)
                return true;

            RECT rect;
            if (!GetWindowRect(hwnd, out rect))
                return true;

            int width = Math.Max(0, rect.Right - rect.Left);
            int height = Math.Max(0, rect.Bottom - rect.Top);
            int area = width * height;
            if (area > 0)
                matches.Add(new WindowMatch { Handle = hwnd, Area = area });
            return true;
        }, IntPtr.Zero);

        if (matches.Count == 0)
            return IntPtr.Zero;

        return matches.OrderByDescending(x => x.Area).First().Handle;
    }

    public static WindowSnapshot CaptureWindow(IntPtr hwnd)
    {
        RECT outerRect;
        if (!GetWindowRect(hwnd, out outerRect))
            throw new InvalidOperationException("GetWindowRect failed.");

        RECT clientRect;
        if (!GetClientRect(hwnd, out clientRect))
            throw new InvalidOperationException("GetClientRect failed.");

        POINT clientTopLeft = new POINT { X = clientRect.Left, Y = clientRect.Top };
        POINT clientBottomRight = new POINT { X = clientRect.Right, Y = clientRect.Bottom };
        ClientToScreen(hwnd, ref clientTopLeft);
        ClientToScreen(hwnd, ref clientBottomRight);

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
                Handle = childHwnd.ToInt64(),
                WindowClass = GetWindowClass(childHwnd),
                Title = GetWindowCaption(childHwnd),
                Left = childRect.Left,
                Top = childRect.Top,
                Right = childRect.Right,
                Bottom = childRect.Bottom,
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
            Handle = hwnd.ToInt64(),
            WindowClass = GetWindowClass(hwnd),
            Title = GetWindowCaption(hwnd),
            OuterLeft = outerRect.Left,
            OuterTop = outerRect.Top,
            OuterRight = outerRect.Right,
            OuterBottom = outerRect.Bottom,
            OuterWidth = Math.Max(0, outerRect.Right - outerRect.Left),
            OuterHeight = Math.Max(0, outerRect.Bottom - outerRect.Top),
            ClientLeft = clientTopLeft.X,
            ClientTop = clientTopLeft.Y,
            ClientRight = clientBottomRight.X,
            ClientBottom = clientBottomRight.Y,
            ClientWidth = Math.Max(0, clientBottomRight.X - clientTopLeft.X),
            ClientHeight = Math.Max(0, clientBottomRight.Y - clientTopLeft.Y),
            VisibleChildCount = visibleChildren.Count,
            LargestVisibleChild = largestVisibleChild,
            ChildSummary = childSummary
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

    private static string GetWindowClass(IntPtr hwnd)
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

Add-Type -TypeDefinition $source -Language CSharp

$baseLines = @(Get-Content -LiteralPath $BaseRdpPath -Encoding Unicode)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("rdp-window-probe-{0}" -f ([guid]::NewGuid().ToString('N')))
$null = New-Item -ItemType Directory -Path $tempRoot
$results = [System.Collections.Generic.List[object]]::new()

try {
    foreach ($case in $cases) {
        $probePath = Join-Path $tempRoot ("case-{0:00}.rdp" -f $case.CaseNumber)
        $probeLines = [System.Collections.Generic.List[string]]::new([string[]]$baseLines)

        Set-RdpSettingLine $probeLines "smart sizing:i:$($case.SmartSizing)"
        Set-RdpSettingLine $probeLines "screen mode id:i:$($case.ScreenModeId)"
        Set-RdpSettingLine $probeLines "winposstr:s:0,$($case.WinposShowCmd),0,0,$($case.WinposWidth),$($case.WinposHeight)"
        Set-RdpSettingLine $probeLines 'redirectsmartcards:i:0'
        Set-RdpSettingLine $probeLines 'redirectwebauthn:i:0'
        Set-RdpSettingLine $probeLines 'redirectclipboard:i:0'
        Set-RdpSettingLine $probeLines 'drivestoredirect:s:'
        if ($TargetAddress -ne '') {
            Set-RdpSettingLine $probeLines "full address:s:$TargetAddress"
        }

        $probeLines | Set-Content -LiteralPath $probePath -Encoding Unicode

        $process = $null
        $snapshot = $null
        $errorText = ''
        Write-Host ("[{0}/{1}] smart sizing={2}, screen mode id={3}, winpos showCmd={4}, winpos={5}, smart_size_125={6}" -f $case.CaseNumber, $cases.Count, $case.SmartSizing, $case.ScreenModeId, $case.WinposShowCmd, $case.WinposSpec, $case.SmartSize125)
        try {
            $process = Start-Process -FilePath 'mstsc.exe' -ArgumentList "`"$probePath`"" -PassThru
            $null = Wait-ForMainWindow -Process $process -TimeoutSeconds $LaunchTimeoutSeconds
            Start-Sleep -Milliseconds $SettleMilliseconds
            if ($case.SmartSizing -eq 1 -and $case.SmartSize125 -eq 'yes') {
                $resizeHwnd = [RdpWindowProbe]::FindBestWindowForProcess($process.Id)
                if ($resizeHwnd -ne [IntPtr]::Zero) {
                    $preResizeSnapshot = [RdpWindowProbe]::CaptureWindow($resizeHwnd)
                    $targetOuterWidth = [int][Math]::Ceiling($preResizeSnapshot.OuterWidth * 1.25)
                    $targetOuterHeight = [int][Math]::Ceiling($preResizeSnapshot.OuterHeight * 1.25)
                    [RdpWindowProbe]::ResizeWindowKeepPosition($resizeHwnd, $targetOuterWidth, $targetOuterHeight)
                    Start-Sleep -Milliseconds ([Math]::Max(500, [int]($SettleMilliseconds / 2)))
                }
            }
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $hwnd = [RdpWindowProbe]::FindBestWindowForProcess($process.Id)
                if ($hwnd -eq [IntPtr]::Zero) {
                    Start-Sleep -Milliseconds 300
                    continue
                }

                try {
                    $snapshot = [RdpWindowProbe]::CaptureWindow($hwnd)
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
        }
        finally {
            Stop-MstscProcess $process
            if (-not $KeepTempFiles) {
                Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            }
        }

        $largestChild = Get-PropertyOrNull $snapshot 'LargestVisibleChild'
        $results.Add([PSCustomObject]@{
            HostWindowsVersion = $hostWindowsVersion
            SmartSizing = $case.SmartSizing
            SmartSize125 = $case.SmartSize125
            ScreenModeId = $case.ScreenModeId
            WinposShowCmd = $case.WinposShowCmd
            WinposWidth = $case.WinposWidth
            WinposHeight = $case.WinposHeight
            WindowTitle = Get-PropertyOrNull $snapshot 'Title'
            OuterWidth = Get-PropertyOrNull $snapshot 'OuterWidth'
            OuterHeight = Get-PropertyOrNull $snapshot 'OuterHeight'
            ClientWidth = Get-PropertyOrNull $snapshot 'ClientWidth'
            ClientHeight = Get-PropertyOrNull $snapshot 'ClientHeight'
            VisibleChildCount = Get-PropertyOrNull $snapshot 'VisibleChildCount'
            LargestChildClass = Get-PropertyOrNull $largestChild 'WindowClass'
            LargestChildWidth = Get-PropertyOrNull $largestChild 'Width'
            LargestChildHeight = Get-PropertyOrNull $largestChild 'Height'
            LargestChildLeft = Get-PropertyOrNull $largestChild 'Left'
            LargestChildTop = Get-PropertyOrNull $largestChild 'Top'
            ChildSummary = Get-PropertyOrNull $snapshot 'ChildSummary'
            ProbeFile = if ($KeepTempFiles) { $probePath } else { '' }
            Error = $errorText
        })
    }

    $outputDir = Split-Path -Parent $OutputCsvPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        $null = New-Item -ItemType Directory -Path $outputDir
    }

    $results | Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation
    $results |
        Select-Object HostWindowsVersion, SmartSizing, SmartSize125, ScreenModeId, WinposShowCmd, WinposWidth, WinposHeight, ClientWidth, ClientHeight, LargestChildWidth, LargestChildHeight, Error |
        Format-Table -AutoSize
    Write-Host "Wrote probe results to $OutputCsvPath"
    if ($KeepTempFiles) {
        Write-Host "Kept temporary .rdp files in $tempRoot"
    }
}
finally {
    if (-not $KeepTempFiles) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
