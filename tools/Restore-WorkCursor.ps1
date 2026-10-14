[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$BackupDirectory = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$state = Get-Content -LiteralPath (Join-Path $BackupDirectory 'cursor-settings.json') -Raw |
    ConvertFrom-Json
if (-not $PSCmdlet.ShouldProcess('Current Windows cursor scheme', 'Restore the backed-up Work cursor')) {
    return
}
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
    foreach ($item in @($state.Values | Where-Object { $_.Name -in @('', 'AppStarting', 'SchemeSource') })) {
        if ($item.Exists) {
            $kind = [Microsoft.Win32.RegistryValueKind]$item.Kind
            $value = if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) {
                [int]$item.Value
            } else { [string]$item.Value }
            $key.SetValue([string]$item.Name, $value, $kind)
        }
        else { $key.DeleteValue([string]$item.Name, $false) }
    }
    # Remove only the unique scheme recorded by this application, if it is still ours.
    if ($schemes.GetValue([string]$state.FixedSchemeName) -eq $state.FixedSchemePaths) {
        $schemes.DeleteValue([string]$state.FixedSchemeName, $false)
    }
    if (-not [WorkCursorRefresh]::SystemParametersInfo(0x57, 0, [IntPtr]::Zero, 2)) {
        throw "Windows cursor refresh failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    foreach ($item in @($state.Values | Where-Object { $_.Name -in @('', 'AppStarting', 'SchemeSource') })) {
        if ($item.Exists -and
            ($key.GetValue([string]$item.Name, $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ne $item.Value -or
             $key.GetValueKind([string]$item.Name).ToString() -ne $item.Kind)) {
            throw "Restore verification failed for $($item.Name)."
        }
        if (-not $item.Exists -and $key.GetValueNames() -contains [string]$item.Name) {
            throw "Restore verification failed for absent value $($item.Name)."
        }
    }
}
finally { $key.Dispose(); $schemes.Dispose() }
Write-Output "Restored previous Windows Work cursor. Backup retained: $BackupDirectory"
