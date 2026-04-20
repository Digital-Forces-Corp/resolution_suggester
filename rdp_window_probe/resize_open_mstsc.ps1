# resize_open_mstsc.ps1 — failure log
#
# Goal: locate the open mstsc session window and resize it by $Scale (default x1.25).
# Outcome so far: every approach below was tried against a confirmed-connected
# session window and FAILED — mstsc reports the resize as successful but snaps
# the window back to its prior outer size (822x656 / client 800x600 here).
# Mouse-drag resize was also reported as snapping back by the user.
#
# Things tried that did not change the post-resize size:
#   - SetWindowPos with SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE (+/- SWP_FRAMECHANGED)
#   - MoveWindow keeping the original top-left
#   - ShowWindow(SW_MAXIMIZE)
#   - Calling SetForegroundWindow first
#   - Toggling Smart Sizing via WM_SYSCOMMAND id 0x0091 (the "Sm&art sizing"
#     entry on the system menu). Tried convergent sequence:
#         resize -> if no change, toggle, resize -> if no change, toggle back, resize.
#     All three attempts produced the same PostOuter as PreOuter.
#   - Reading the Smart Sizing menu state via GetMenuState/MF_CHECKED seems unreliable
#
# Window facts confirmed via GetWindowInfo:
#   - Class: TscShellContainerClass
#   - Style includes WS_THICKFRAME, WS_MAXIMIZEBOX, WS_MINIMIZEBOX (i.e. it
#     advertises itself as resizable).
#   - The session is connected (user verified).
#
# Net: the actual reason mstsc refuses programmatic AND mouse resize in this
# state is still unknown. This script is kept as a minimal repro harness.
#
# Environment note: the failures above were observed connecting from a client
# running 10.0.19045.718 to a Windows XP target.
#
# Contrast: against a Windows IoT target, Smart Sizing only allows shrinking the
# session window below the negotiated desktop size — it scales the bitmap down
# but does NOT renegotiate / change the remote desktop resolution. Enlarging
# beyond the original size is not honored either.
#
# NOTE: XP target (DEV2024) was logging Event ID 50 / Source TermDD ("The RDP
# protocol component X.224 detected an error in the protocol stream and has
# disconnected the client") — "An internal error has occurred" on the client.
# Also Event ID 1006 / Source TermService ("The terminal server received large
# number of incomplete connections. The system may be under attack.") — XP
# treating rapid failed probe connections as a flood.
# Attempted fix: security layer:i:0 + authentication level:i:0 in ticket_highest_speed.rdp
# (disables TLS/NLA, falls back to classic RDP security that XP supports).
# Result: did NOT help — error persists.
# Reference: https://petri.com/remote-desktop-connection-an-internal-error-has-occurred/

[CmdletBinding()]
param(
    [double]$Scale = 1.25,
    [string]$WindowClass = 'TscShellContainerClass'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('MstscSmart' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class MstscSmart {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc f, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr GetSystemMenu(IntPtr h, bool revert);
    [DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr menu);
    [DllImport("user32.dll")] public static extern uint GetMenuItemID(IntPtr menu, int pos);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetMenuString(IntPtr menu, uint item, StringBuilder buf, int max, uint flag);
    [DllImport("user32.dll")] public static extern uint GetMenuState(IntPtr menu, uint item, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);

    public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, s.Capacity); return s.ToString(); }
    public static string Txt(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, s.Capacity); return s.ToString(); }
}
"@
}

$ctx = [IntPtr]::new(-4)
$null = [MstscSmart]::SetProcessDpiAwarenessContext($ctx)
$null = [MstscSmart]::SetThreadDpiAwarenessContext($ctx)

$target = [IntPtr]::Zero
$cb = [MstscSmart+EnumWindowsProc] {
    param($h, $l)
    if (-not [MstscSmart]::IsWindowVisible($h)) { return $true }
    if ([MstscSmart]::Cls($h) -ne $WindowClass) { return $true }
    $script:target = $h
    return $false
}
[void][MstscSmart]::EnumWindows($cb, [IntPtr]::Zero)
if ($target -eq [IntPtr]::Zero) { throw "No '$WindowClass' window found." }

$menu = [MstscSmart]::GetSystemMenu($target, $false)
$count = [MstscSmart]::GetMenuItemCount($menu)
Write-Host "System menu items ($count):"
$smartId = 0
$smartIndex = -1
for ($i = 0; $i -lt $count; $i++) {
    $id = [MstscSmart]::GetMenuItemID($menu, $i)
    $sb = New-Object System.Text.StringBuilder 256
    [void][MstscSmart]::GetMenuString($menu, [uint32]$i, $sb, $sb.Capacity, 0x400)
    $state = [MstscSmart]::GetMenuState($menu, [uint32]$i, 0x400)
    $checked = if ($state -band 0x8) { 'CHECKED' } else { '' }
    $text = $sb.ToString()
    $clean = $text -replace '&', ''
    '  [{0,2}] id=0x{1:X4}  {2,-8}  "{3}"' -f $i, $id, $checked, $text | Write-Host
    if ($clean -match '(?i)smart\s*sizing') { $smartId = $id; $smartIndex = $i }
}

function Test-SmartSizingChecked {
    param($menu, [int]$index)
    $state = [MstscSmart]::GetMenuState($menu, [uint32]$index, 0x400)
    return [bool]($state -band 0x8)
}

if ($smartId -eq 0) {
    Write-Warning "No 'Smart sizing' menu item found."
}

$WM_SYSCOMMAND = 0x0112
$flags = 0x0002 -bor 0x0004 -bor 0x0010

function Get-Outer($h) {
    $r = New-Object MstscSmart+RECT
    [void][MstscSmart]::GetWindowRect($h, [ref]$r)
    return [PSCustomObject]@{ W = $r.Right - $r.Left; H = $r.Bottom - $r.Top }
}

function Try-Resize($h, [int]$w, [int]$h2) {
    $null = [MstscSmart]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, $w, $h2, $flags)
    Start-Sleep -Milliseconds 600
}

$pre = Get-Outer $target
$newW = [int][Math]::Ceiling($pre.W * $Scale)
$newH = [int][Math]::Ceiling($pre.H * $Scale)

Write-Host ("Pre  outer: {0}x{1}; target {2}x{3}" -f $pre.W, $pre.H, $newW, $newH)

# Attempt 1: resize as-is
Try-Resize $target $newW $newH
$post = Get-Outer $target
Write-Host ("After attempt 1: {0}x{1}" -f $post.W, $post.H)

if (($post.W -eq $pre.W -and $post.H -eq $pre.H) -and $smartId -ne 0) {
    Write-Host "No change - toggling Smart Sizing then retrying"
    [void][MstscSmart]::SendMessage($target, $WM_SYSCOMMAND, [IntPtr]$smartId, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    Try-Resize $target $newW $newH
    $post = Get-Outer $target
    Write-Host ("After attempt 2: {0}x{1}" -f $post.W, $post.H)

    if ($post.W -eq $pre.W -and $post.H -eq $pre.H) {
        Write-Host "Still no change - toggling back and retrying"
        [void][MstscSmart]::SendMessage($target, $WM_SYSCOMMAND, [IntPtr]$smartId, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 400
        Try-Resize $target $newW $newH
        $post = Get-Outer $target
        Write-Host ("After attempt 3: {0}x{1}" -f $post.W, $post.H)
    }
}

$client = New-Object MstscSmart+RECT
[void][MstscSmart]::GetClientRect($target, [ref]$client)

[PSCustomObject]@{
    PreOuter   = "$($pre.W)x$($pre.H)"
    Target     = "${newW}x${newH}"
    PostOuter  = "$($post.W)x$($post.H)"
    PostClient = "$($client.Right - $client.Left)x$($client.Bottom - $client.Top)"
} | Format-List
