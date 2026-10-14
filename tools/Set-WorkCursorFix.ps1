[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ThemeDirectory,
    [ValidateSet('Balanced', 'Balanced-Large')]
    [string]$Profile = 'Balanced-Large',
    [switch]$IncludeBusy
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ThemeDirectory)) {
    $ThemeDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) "themes\macOS-$Profile-Windows"
}
$ThemeDirectory = [IO.Path]::GetFullPath($ThemeDirectory)
$newWorkSource = Join-Path $ThemeDirectory 'Work.ani'
$newBusySource = Join-Path $ThemeDirectory 'Busy.ani'
$active = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors')
try {
    $currentArrow = [string]$active.GetValue('Arrow')
    $currentWork = [string]$active.GetValue('AppStarting')
    $currentBusy = [string]$active.GetValue('Wait')
    $currentScheme = [string]$active.GetValue('')
    $names = @($active.GetValueNames())
    $values = @()
    foreach ($name in @($names + @('', 'AppStarting', 'Wait', 'SchemeSource') | Select-Object -Unique)) {
        $exists = $names -contains $name
        $values += [pscustomobject]@{
            Name = $name; Exists = $exists
            Kind = if ($exists) { $active.GetValueKind($name).ToString() } else { $null }
            Value = if ($exists) {
                $active.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            } else { $null }
        }
    }
}
finally { $active.Dispose() }
if ((Get-FileHash -LiteralPath $currentArrow).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $ThemeDirectory 'Pointer.cur')).Hash) {
    throw 'The selected build does not match the currently active pointer. Choose its matching profile.'
}
$action = if ($IncludeBusy) { 'Back up and apply the repaired Work and Busy animations' }
    else { 'Back up and apply the repaired Work animation' }
if (-not $PSCmdlet.ShouldProcess($currentScheme, $action)) {
    return
}

# Validate the complete build before touching the active scheme.
& (Join-Path $PSScriptRoot 'Test-BalancedWindowsTheme.ps1') -ThemeDirectory $ThemeDirectory -Profile $Profile
function Get-NativeBitmapHash {
    param([IntPtr]$BitmapHandle)
    $bitmap = [BalancedCursorNative+BitmapInfo]::new()
    if ([BalancedCursorNative]::GetObject($BitmapHandle,
        [Runtime.InteropServices.Marshal]::SizeOf($bitmap), [ref]$bitmap) -eq 0) {
        throw 'Could not inspect the cursor bitmap for cache verification.'
    }
    $pixels = [byte[]]::new($bitmap.WidthBytes * $bitmap.Height)
    if ([BalancedCursorNative]::GetBitmapBits($BitmapHandle, $pixels.Length, $pixels) -ne $pixels.Length) {
        throw 'Could not read the cursor bitmap for cache verification.'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($pixels))).Replace('-', '') }
    finally { $sha.Dispose() }
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$directoryName = if ($IncludeBusy) { 'animation-fix' } else { 'work-fix' }
$applicationDirectory = Join-Path $env:LOCALAPPDATA "apple_cursor\$directoryName\$timestamp"
$backupDirectory = Join-Path $applicationDirectory 'backup'
if (Test-Path -LiteralPath $applicationDirectory) { throw 'The timestamped output already exists.' }
[void](New-Item -ItemType Directory -Path $backupDirectory)
$fixedWork = Join-Path $applicationDirectory 'Work.ani'
$fixedBusy = if ($IncludeBusy) { Join-Path $applicationDirectory 'Busy.ani' } else { $null }
$baseScheme = $currentScheme -replace ' \((?:Work|Animations) Fixed \d{8}-\d{9}\)$', ''
$fixName = if ($IncludeBusy) { 'Animations Fixed' } else { 'Work Fixed' }
$fixedSchemeName = "$baseScheme ($fixName $timestamp)"
$slotNames = @('Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair', 'IBeam', 'NWPen', 'No',
    'SizeNS', 'SizeWE', 'SizeNWSE', 'SizeNESW', 'SizeAll', 'UpArrow', 'Hand', 'Pin', 'Person')
$schemePaths = @($slotNames | ForEach-Object {
    $slot = $_
    $item = @($values | Where-Object Name -eq $slot)[0]
    if ($item.Kind -eq 'ExpandString') {
        [Environment]::ExpandEnvironmentVariables([string]$item.Value)
    }
    else { [string]$item.Value }
})
$schemePaths[2] = $fixedWork
if ($IncludeBusy) { $schemePaths[3] = $fixedBusy }
$fixedSchemePaths = $schemePaths -join ','
$state = [pscustomobject]@{
    CreatedAt = (Get-Date).ToString('o'); Profile = $Profile; PreviousScheme = $currentScheme
    PreviousWorkPath = $currentWork; FixedWorkPath = $fixedWork
    IncludeBusy = [bool]$IncludeBusy; PreviousBusyPath = $currentBusy; FixedBusyPath = $fixedBusy
    FixedSchemeName = $fixedSchemeName; FixedSchemePaths = $fixedSchemePaths; Values = $values
}
$state | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $backupDirectory 'cursor-settings.json') -Encoding UTF8
& reg.exe export 'HKCU\Control Panel\Cursors' (Join-Path $backupDirectory 'cursors.reg') /y | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not export cursor settings.' }
Copy-Item -LiteralPath $currentWork -Destination (Join-Path $backupDirectory 'Work.ani')
Copy-Item -LiteralPath $currentArrow -Destination (Join-Path $backupDirectory 'Pointer.cur')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Restore-WorkCursor.ps1') -Destination $backupDirectory
Copy-Item -LiteralPath $newWorkSource -Destination $fixedWork
if ($IncludeBusy) {
    Copy-Item -LiteralPath $currentBusy -Destination (Join-Path $backupDirectory 'Busy.ani')
    Copy-Item -LiteralPath $newBusySource -Destination $fixedBusy
}
$hashes = @()
$copyPairs = @(
    @($currentWork, (Join-Path $backupDirectory 'Work.ani')),
    @($currentArrow, (Join-Path $backupDirectory 'Pointer.cur')),
    @($newWorkSource, $fixedWork)
)
if ($IncludeBusy) {
    $copyPairs += ,@($currentBusy, (Join-Path $backupDirectory 'Busy.ani'))
    $copyPairs += ,@($newBusySource, $fixedBusy)
}
foreach ($pair in $copyPairs) {
    $sourceHash = (Get-FileHash -LiteralPath $pair[0]).Hash
    $copiedHash = (Get-FileHash -LiteralPath $pair[1]).Hash
    if ($sourceHash -ne $copiedHash) { throw 'Backup or installation copy verification failed.' }
    $hashes += [pscustomobject]@{Path = $pair[1]; Sha256 = $copiedHash}
}
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDirectory 'hashes.json') -Encoding UTF8

if (-not ('WorkCursorRefresh' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WorkCursorRefresh {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SystemParametersInfo(uint action, uint param, IntPtr value, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr LoadCursor(IntPtr instance, IntPtr name);
}
'@
}
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors', $true)
$schemes = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors\Schemes', $true)
try {
    if ($schemes.GetValueNames() -contains $fixedSchemeName) { throw 'The independent scheme already exists.' }
    $schemes.SetValue($fixedSchemeName, $fixedSchemePaths, [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('', $fixedSchemeName, [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('AppStarting', $fixedWork, [Microsoft.Win32.RegistryValueKind]::String)
    if ($IncludeBusy) { $key.SetValue('Wait', $fixedBusy, [Microsoft.Win32.RegistryValueKind]::String) }
    $key.SetValue('SchemeSource', 2, [Microsoft.Win32.RegistryValueKind]::DWord)
    if (-not [WorkCursorRefresh]::SystemParametersInfo(0x57, 0, [IntPtr]::Zero, 2)) {
        throw "Windows cursor refresh failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    if ($key.GetValue('AppStarting') -ne $fixedWork -or $key.GetValue('') -ne $fixedSchemeName -or
        $schemes.GetValue($fixedSchemeName) -ne $fixedSchemePaths) {
        throw 'The active or saved cursor scheme does not match the repaired build.'
    }
    if ($IncludeBusy -and $key.GetValue('Wait') -ne $fixedBusy) {
        throw 'The active Busy cursor does not match the repaired build.'
    }
    $modifiedNames = @('', 'AppStarting', 'SchemeSource')
    if ($IncludeBusy) { $modifiedNames += 'Wait' }
    foreach ($item in @($values | Where-Object { $_.Exists -and $_.Name -notin $modifiedNames })) {
        $now = $key.GetValue([string]$item.Name, $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($now -ne $item.Value -or $key.GetValueKind([string]$item.Name).ToString() -ne $item.Kind) {
            throw "An unrelated cursor setting changed: $($item.Name)."
        }
    }
    # Inspect the real system slots after refreshing, rather than only the files on disk.
    $systemSlots = @()
    $roles = @(32512, 32650)
    if ($IncludeBusy) { $roles += 32514 }
    foreach ($role in $roles) {
        $handle = [WorkCursorRefresh]::LoadCursor([IntPtr]::Zero, [IntPtr]$role)
        $info = [BalancedCursorNative+IconInfo]::new()
        try {
            if ($handle -eq [IntPtr]::Zero -or -not [BalancedCursorNative]::GetIconInfo($handle, [ref]$info)) {
                throw 'Could not inspect the refreshed system cursor.'
            }
            $bitmap = [BalancedCursorNative+BitmapInfo]::new()
            if ([BalancedCursorNative]::GetObject($info.Color,
                [Runtime.InteropServices.Marshal]::SizeOf($bitmap), [ref]$bitmap) -eq 0) {
                throw 'Could not inspect the refreshed system cursor dimensions.'
            }
            $systemSlots += [pscustomobject]@{
                Role = $role; Width = $bitmap.Width; Height = $bitmap.Height
                HotspotX = $info.HotspotX; HotspotY = $info.HotspotY
                PixelSha256 = Get-NativeBitmapHash $info.Color
            }
        }
        finally {
            if ($info.Color -ne [IntPtr]::Zero) { [void][BalancedCursorNative]::DeleteObject($info.Color) }
            if ($info.Mask -ne [IntPtr]::Zero) { [void][BalancedCursorNative]::DeleteObject($info.Mask) }
        }
    }
    if ($systemSlots[0].Width -ne $systemSlots[1].Width -or
        $systemSlots[0].Height -ne $systemSlots[1].Height -or
        $systemSlots[0].HotspotX -ne $systemSlots[1].HotspotX -or
        $systemSlots[0].HotspotY -ne $systemSlots[1].HotspotY) {
        throw 'The refreshed system Arrow and Work slots disagree in dimensions or hotspot.'
    }
    if ($IncludeBusy) {
        if ($systemSlots[2].Width -ne $systemSlots[0].Width -or
            $systemSlots[2].Height -ne $systemSlots[0].Height) {
            throw 'The refreshed system Busy cursor has an unexpected canvas size.'
        }
        $expectedHandle = [BalancedCursorNative]::LoadImage([IntPtr]::Zero, $fixedBusy, 2,
            $systemSlots[2].Width, $systemSlots[2].Height, 0x10)
        $expectedInfo = [BalancedCursorNative+IconInfo]::new()
        try {
            if ($expectedHandle -eq [IntPtr]::Zero -or
                -not [BalancedCursorNative]::GetIconInfo($expectedHandle, [ref]$expectedInfo) -or
                $expectedInfo.HotspotX -ne $systemSlots[2].HotspotX -or
                $expectedInfo.HotspotY -ne $systemSlots[2].HotspotY -or
                (Get-NativeBitmapHash $expectedInfo.Color) -ne $systemSlots[2].PixelSha256) {
                throw 'The refreshed Busy cursor pixels or hotspot differ from the repaired build.'
            }
        }
        finally {
            if ($expectedInfo.Color -ne [IntPtr]::Zero) { [void][BalancedCursorNative]::DeleteObject($expectedInfo.Color) }
            if ($expectedInfo.Mask -ne [IntPtr]::Zero) { [void][BalancedCursorNative]::DeleteObject($expectedInfo.Mask) }
            if ($expectedHandle -ne [IntPtr]::Zero) { [void][BalancedCursorNative]::DestroyCursor($expectedHandle) }
        }
    }
    [pscustomobject]@{
        Scheme = $fixedSchemeName; WorkPath = $fixedWork; BackupDirectory = $backupDirectory
        IncludeBusy = [bool]$IncludeBusy; BusyPath = $fixedBusy
        RestoreScript = Join-Path $backupDirectory 'Restore-WorkCursor.ps1'; SystemSlots = $systemSlots
        Sha256 = (Get-FileHash -LiteralPath $fixedWork).Hash
        BusySha256 = if ($IncludeBusy) { (Get-FileHash -LiteralPath $fixedBusy).Hash } else { $null }
    } | ConvertTo-Json -Depth 5 |
        Tee-Object -FilePath (Join-Path $applicationDirectory 'application-result.json')
}
catch {
    $applyError = $_
    & (Join-Path $backupDirectory 'Restore-WorkCursor.ps1') -BackupDirectory $backupDirectory -Confirm:$false
    throw $applyError
}
finally { $key.Dispose(); $schemes.Dispose() }
