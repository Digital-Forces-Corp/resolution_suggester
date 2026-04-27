param(
    [Parameter(Position = 0)]
    [ValidateSet('enabled', 'disabled')]
    [string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HklmPath = 'HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'
$HkcuPath = 'HKCU:\Software\Microsoft\Terminal Server Client'
$HklmName = 'RedirectionWarningDialogVersion'
$HkcuName = 'RdpLaunchConsentAccepted'

function Test-IsProcessElevated {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegistryDwordOrNull([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return [int]$item.$Name
}

function Set-RegistryDwordValue([string]$Path, [string]$Name, [int]$Value) {
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -Path $Path -Force
    }

    $null = New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force
}

function Format-DwordDisplay($Value) {
    if ($null -eq $Value) { return '<not set>' }
    return [string]$Value
}

function Show-WarningStatus {
    $hklmValue = Get-RegistryDwordOrNull -Path $HklmPath -Name $HklmName
    $hkcuValue = Get-RegistryDwordOrNull -Path $HkcuPath -Name $HkcuName

    $state = if ($hklmValue -eq 1 -and $hkcuValue -eq 1) {
        'disabled'
    }
    elseif (($null -eq $hklmValue -or $hklmValue -eq 0) -and ($null -eq $hkcuValue -or $hkcuValue -eq 0)) {
        'enabled'
    }
    else {
        'mixed'
    }

    Write-Host "RDP redirection warning dialogs: $state"
    Write-Host "  HKLM ${HklmPath}\${HklmName} = $(Format-DwordDisplay $hklmValue)"
    Write-Host "  HKCU ${HkcuPath}\${HkcuName} = $(Format-DwordDisplay $hkcuValue)"
}

function Show-Help {
    $scriptName = Split-Path -Leaf $PSCommandPath
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\$scriptName              # show current status"
    Write-Host "  .\$scriptName enabled      # restore RDP redirection warning dialogs"
    Write-Host "  .\$scriptName disabled     # suppress RDP redirection warning dialogs"
    Write-Host ""
    Write-Host "Writes to HKLM require elevation; the script self-elevates when needed."
}

function Set-RdpWarningDialogs([bool]$WarningsEnabled) {
    if ($WarningsEnabled) {
        $redirectionValue = 0
        $consentValue = 0
    }
    else {
        $redirectionValue = 1
        $consentValue = 1
    }

    try {
        Set-RegistryDwordValue -Path $HklmPath -Name $HklmName -Value $redirectionValue
    }
    catch {
        throw "Failed to set HKLM policy value ${HklmName}=$redirectionValue. Run this script in an elevated PowerShell session. $($_.Exception.Message)"
    }

    Set-RegistryDwordValue -Path $HkcuPath -Name $HkcuName -Value $consentValue
}

if (-not $PSBoundParameters.ContainsKey('Action')) {
    Show-WarningStatus
    Show-Help
    return
}

if (-not (Test-IsProcessElevated)) {
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $PSCommandPath + '"'),
        $Action
    )

    try {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -WorkingDirectory (Get-Location).Path -Verb RunAs -Wait -PassThru
    }
    catch {
        throw "Elevation is required because this script writes HKLM policy values. $($_.Exception.Message)"
    }

    if ($process.ExitCode -ne 0) {
        throw "Elevated run failed with exit code $($process.ExitCode)."
    }

    return
}

$enable = ($Action -eq 'enabled')
Set-RdpWarningDialogs -WarningsEnabled $enable

if ($enable) {
    Write-Host "RDP redirection warning dialogs enabled."
}
else {
    Write-Host "RDP redirection warning dialogs disabled."
}
