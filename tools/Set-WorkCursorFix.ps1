[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ThemeDirectory,
    [ValidateSet('Balanced', 'Balanced-Large')]
    [string]$Profile = 'Balanced-Large'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ThemeDirectory)) {
    $ThemeDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) "themes\macOS-$Profile-Windows"
}
$ThemeDirectory = [IO.Path]::GetFullPath($ThemeDirectory)
$newWorkSource = Join-Path $ThemeDirectory 'Work.ani'
$active = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors')
try {
    $currentArrow = [string]$active.GetValue('Arrow')
    $currentWork = [string]$active.GetValue('AppStarting')
    $currentScheme = [string]$active.GetValue('')
    $names = @($active.GetValueNames())
    $values = @()
    foreach ($name in @($names + @('', 'AppStarting', 'SchemeSource') | Select-Object -Unique)) {
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
if (-not $PSCmdlet.ShouldProcess($currentScheme, 'Back up and apply the repaired Work animation')) {
    return
}

# Validate the complete build before touching the active scheme.
& (Join-Path $PSScriptRoot 'Test-BalancedWindowsTheme.ps1') -ThemeDirectory $ThemeDirectory -Profile $Profile
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$applicationDirectory = Join-Path $env:LOCALAPPDATA "apple_cursor\work-fix\$timestamp"
$backupDirectory = Join-Path $applicationDirectory 'backup'
if (Test-Path -LiteralPath $applicationDirectory) { throw 'The timestamped output already exists.' }
[void](New-Item -ItemType Directory -Path $backupDirectory)
$fixedWork = Join-Path $applicationDirectory 'Work.ani'
$baseScheme = $currentScheme -replace ' \(Work Fixed \d{8}-\d{9}\)$', ''
$fixedSchemeName = "$baseScheme (Work Fixed $timestamp)"
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
$fixedSchemePaths = $schemePaths -join ','
$state = [pscustomobject]@{
    CreatedAt = (Get-Date).ToString('o'); Profile = $Profile; PreviousScheme = $currentScheme
    PreviousWorkPath = $currentWork; FixedWorkPath = $fixedWork
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
$hashes = @()
foreach ($pair in @(
    @($currentWork, (Join-Path $backupDirectory 'Work.ani')),
    @($currentArrow, (Join-Path $backupDirectory 'Pointer.cur')),
    @($newWorkSource, $fixedWork)
)) {
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
    $key.SetValue('SchemeSource', 2, [Microsoft.Win32.RegistryValueKind]::DWord)
    if (-not [WorkCursorRefresh]::SystemParametersInfo(0x57, 0, [IntPtr]::Zero, 2)) {
        throw "Windows cursor refresh failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    if ($key.GetValue('AppStarting') -ne $fixedWork -or $key.GetValue('') -ne $fixedSchemeName -or
        $schemes.GetValue($fixedSchemeName) -ne $fixedSchemePaths) {
        throw 'The active or saved cursor scheme does not match the repaired build.'
    }
    foreach ($item in @($values | Where-Object { $_.Exists -and $_.Name -notin @('', 'AppStarting', 'SchemeSource') })) {
        $now = $key.GetValue([string]$item.Name, $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($now -ne $item.Value -or $key.GetValueKind([string]$item.Name).ToString() -ne $item.Kind) {
            throw "An unrelated cursor setting changed: $($item.Name)."
        }
    }
    # Inspect the real system slots after refreshing, rather than only the files on disk.
    $systemSlots = @()
    foreach ($role in @(32512, 32650)) {
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
    [pscustomobject]@{
        Scheme = $fixedSchemeName; WorkPath = $fixedWork; BackupDirectory = $backupDirectory
        RestoreScript = Join-Path $backupDirectory 'Restore-WorkCursor.ps1'; SystemSlots = $systemSlots
        Sha256 = (Get-FileHash -LiteralPath $fixedWork).Hash
    } | ConvertTo-Json -Depth 5 |
        Tee-Object -FilePath (Join-Path $applicationDirectory 'application-result.json')
}
catch {
    $applyError = $_
    & (Join-Path $backupDirectory 'Restore-WorkCursor.ps1') -BackupDirectory $backupDirectory -Confirm:$false
    throw $applyError
}
finally { $key.Dispose(); $schemes.Dispose() }
