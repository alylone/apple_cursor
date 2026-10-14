[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$ThemeDirectory,
    [ValidateSet('Balanced', 'Balanced-Large')]
    [string]$Profile = 'Balanced'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

if ($Profile -eq 'Balanced') {
    $expectedSchemeName = 'macOS-Balanced Cursors'
    $expectedHotspotX = 6
    $expectedHotspotY = 3
    $expectedOpaquePixels = 50
    $expectedMinimumWheelColorPixels = 50
    $expectedWheelBounds = @(16, 25, 7, 16)
}
else {
    $expectedSchemeName = 'macOS-Balanced Large Cursors'
    $expectedHotspotX = 8
    $expectedHotspotY = 4
    $expectedOpaquePixels = 85
    $expectedMinimumWheelColorPixels = 60
    $expectedWheelBounds = @(20, 30, 9, 19)
}

if ([string]::IsNullOrWhiteSpace($ThemeDirectory)) {
    $ThemeDirectory = Join-Path $ProjectRoot "themes\macOS-$Profile-Windows"
}
$ThemeDirectory = [IO.Path]::GetFullPath($ThemeDirectory)

if (-not (Test-Path -LiteralPath $ThemeDirectory -PathType Container)) {
    throw "Balanced theme directory not found: $ThemeDirectory"
}

if (-not ('BalancedCursorNative' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class BalancedCursorNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct IconInfo {
        public bool IsIcon;
        public uint HotspotX, HotspotY;
        public IntPtr Mask, Color;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct BitmapInfo {
        public int Type, Width, Height, WidthBytes;
        public ushort Planes, BitsPixel;
        public IntPtr Bits;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadImage(
        IntPtr instance,
        string name,
        uint type,
        int width,
        int height,
        uint flags
    );

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyCursor(IntPtr cursor);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetIconInfo(IntPtr cursor, out IconInfo info);
    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern int GetObject(IntPtr bitmap, int size, out BitmapInfo info);
    [DllImport("gdi32.dll", SetLastError = true)]
    public static extern int GetBitmapBits(IntPtr bitmap, int count, byte[] pixels);
    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr bitmap);
}
'@
}

function Copy-ByteRange {
    param(
        [byte[]]$Bytes,
        [int]$Offset,
        [int]$Length
    )

    $result = [byte[]]::new($Length)
    [Array]::Copy($Bytes, $Offset, $result, 0, $Length)
    return $result
}

function Read-CursorEntries {
    param([byte[]]$Bytes)

    if ($Bytes.Length -lt 22 -or
        [BitConverter]::ToUInt16($Bytes, 0) -ne 0 -or
        [BitConverter]::ToUInt16($Bytes, 2) -ne 2) {
        throw 'Invalid Windows cursor data.'
    }

    $entryCount = [BitConverter]::ToUInt16($Bytes, 4)
    $entries = @()
    for ($index = 0; $index -lt $entryCount; $index++) {
        $entryOffset = 6 + (16 * $index)
        $width = if ($Bytes[$entryOffset] -eq 0) {
            256
        }
        else {
            [int]$Bytes[$entryOffset]
        }
        $height = if ($Bytes[$entryOffset + 1] -eq 0) {
            256
        }
        else {
            [int]$Bytes[$entryOffset + 1]
        }
        $imageLength = [BitConverter]::ToUInt32($Bytes, $entryOffset + 8)
        $imageOffset = [BitConverter]::ToUInt32($Bytes, $entryOffset + 12)

        if ($imageOffset + $imageLength -gt $Bytes.Length) {
            throw 'Cursor image extends beyond the end of the file.'
        }
        $png = Copy-ByteRange $Bytes $imageOffset $imageLength
        if ($png.Length -lt 24 -or
            $png[0] -ne 0x89 -or
            $png[1] -ne 0x50 -or
            $png[2] -ne 0x4E -or
            $png[3] -ne 0x47) {
            throw "Cursor ${width}x${height} entry does not contain a PNG."
        }

        $entries += [pscustomobject]@{
            Width = $width
            Height = $height
            HotspotX = [BitConverter]::ToUInt16($Bytes, $entryOffset + 4)
            HotspotY = [BitConverter]::ToUInt16($Bytes, $entryOffset + 6)
            Png = $png
        }
    }

    return $entries
}

function Read-AniFile {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 56 -or
        [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or
        [Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne 'ACON') {
        throw "Invalid ANI file: $Path"
    }

    $header = $null
    $rates = @()
    $frames = @()
    $position = 12
    while ($position + 8 -le $bytes.Length) {
        $chunkId = [Text.Encoding]::ASCII.GetString($bytes, $position, 4)
        $chunkLength = [BitConverter]::ToUInt32($bytes, $position + 4)
        $dataOffset = $position + 8
        if ($dataOffset + $chunkLength -gt $bytes.Length) {
            throw "ANI chunk extends beyond the file: $Path"
        }

        if ($chunkId -eq 'anih') {
            $header = Copy-ByteRange $bytes $dataOffset $chunkLength
        }
        elseif ($chunkId -eq 'rate') {
            if (($chunkLength % 4) -ne 0) {
                throw "Invalid ANI rate chunk: $Path"
            }
            for ($index = 0; $index -lt $chunkLength; $index += 4) {
                $rates += [BitConverter]::ToUInt32($bytes, $dataOffset + $index)
            }
        }
        elseif ($chunkId -eq 'LIST' -and
                $chunkLength -ge 4 -and
                [Text.Encoding]::ASCII.GetString($bytes, $dataOffset, 4) -eq 'fram') {
            $framePosition = $dataOffset + 4
            $frameEnd = $dataOffset + $chunkLength
            while ($framePosition + 8 -le $frameEnd) {
                $frameId = [Text.Encoding]::ASCII.GetString($bytes, $framePosition, 4)
                $frameLength = [BitConverter]::ToUInt32($bytes, $framePosition + 4)
                $frameDataOffset = $framePosition + 8
                if ($frameDataOffset + $frameLength -gt $frameEnd) {
                    throw "ANI frame extends beyond its LIST chunk: $Path"
                }
                if ($frameId -eq 'icon') {
                    $frames += ,(Copy-ByteRange $bytes $frameDataOffset $frameLength)
                }
                $framePosition = $frameDataOffset + $frameLength + ($frameLength % 2)
            }
        }

        $position = $dataOffset + $chunkLength + ($chunkLength % 2)
    }

    if ($null -eq $header -or $header.Length -lt 36) {
        throw "ANI header is missing or invalid: $Path"
    }

    return [pscustomobject]@{
        HeaderFrames = [BitConverter]::ToUInt32($header, 4)
        HeaderSteps = [BitConverter]::ToUInt32($header, 8)
        Width = [BitConverter]::ToUInt32($header, 12)
        Height = [BitConverter]::ToUInt32($header, 16)
        DefaultRate = [BitConverter]::ToUInt32($header, 28)
        Rates = $rates
        Frames = $frames
    }
}

function New-BitmapFromPng {
    param([byte[]]$Png)

    $stream = [IO.MemoryStream]::new($Png, $false)
    $source = $null
    try {
        $source = [Drawing.Bitmap]::new($stream)
        return [Drawing.Bitmap]::new($source)
    }
    finally {
        if ($null -ne $source) { $source.Dispose() }
        $stream.Dispose()
    }
}

function Get-Sha256 {
    param([byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Assert-EqualSequence {
    param(
        [object[]]$Actual,
        [object[]]$Expected,
        [string]$Description
    )

    if ($Actual.Count -ne $Expected.Count) {
        throw "$Description count mismatch: expected $($Expected.Count), found $($Actual.Count)."
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) {
            throw "$Description mismatch at index ${index}: expected $($Expected[$index]), found $($Actual[$index])."
        }
    }
}

$expectedCursorNames = @(
    'Alternate.cur',
    'Busy.ani',
    'Cross.cur',
    'Dng1.cur',
    'Dng2.cur',
    'Grabbing.cur',
    'Handwriting.cur',
    'Help.cur',
    'Horz.cur',
    'Link.cur',
    'Move.cur',
    'Pan.cur',
    'Person.cur',
    'Pin.cur',
    'Pointer.cur',
    'Text.cur',
    'Unavailiable.cur',
    'Vert.cur',
    'Work.ani',
    'Zoom-in.cur',
    'Zoom-out.cur'
)
$actualCursorNames = @(Get-ChildItem -LiteralPath $ThemeDirectory -File |
    Where-Object { $_.Extension -in @('.cur', '.ani') } |
    Sort-Object Name |
    ForEach-Object Name)
Assert-EqualSequence $actualCursorNames $expectedCursorNames 'Cursor asset list'

$installerPath = Join-Path $ThemeDirectory 'install.inf'
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Installer not found: $installerPath"
}
$installer = Get-Content -LiteralPath $installerPath -Raw
if (-not $installer.Contains("SCHEME_NAME=`"$expectedSchemeName`"") -or
    -not $installer.Contains("CUR_DIR=`"Cursors\$expectedSchemeName`"")) {
    throw "Installer does not define the expected independent $Profile scheme."
}

$expectedCanvasSizes = @(32, 48, 64, 96, 128, 256)
$staticFiles = @(Get-ChildItem -LiteralPath $ThemeDirectory -Filter '*.cur' -File)
if ($staticFiles.Count -ne 19) {
    throw "Expected 19 static cursor files, found $($staticFiles.Count)."
}

$pointerEntry = $null
$pointerEntriesBySize = @{}
foreach ($file in $staticFiles) {
    $entries = @(Read-CursorEntries ([IO.File]::ReadAllBytes($file.FullName)))
    Assert-EqualSequence @($entries | ForEach-Object Width) $expectedCanvasSizes "$($file.Name) widths"
    Assert-EqualSequence @($entries | ForEach-Object Height) $expectedCanvasSizes "$($file.Name) heights"
    foreach ($entry in $entries) {
        $bitmap = New-BitmapFromPng $entry.Png
        try {
            if ($bitmap.Width -ne $entry.Width -or $bitmap.Height -ne $entry.Height) {
                throw "$($file.Name) contains a PNG that does not match its CUR dimensions."
            }
            if ($entry.HotspotX -ge $entry.Width -or $entry.HotspotY -ge $entry.Height) {
                throw "$($file.Name) contains an out-of-bounds hotspot."
            }
        }
        finally {
            $bitmap.Dispose()
        }
    }
    if ($file.Name -eq 'Pointer.cur') {
        $pointerEntry = @($entries | Where-Object Width -eq 32)[0]
        foreach ($entry in $entries) { $pointerEntriesBySize[$entry.Width] = $entry }
    }
}

if ($null -eq $pointerEntry -or
    $pointerEntry.HotspotX -ne $expectedHotspotX -or
    $pointerEntry.HotspotY -ne $expectedHotspotY) {
    throw "The 32px Pointer.cur entry must use hotspot ($expectedHotspotX,$expectedHotspotY)."
}

$pointerBitmap = New-BitmapFromPng $pointerEntry.Png
$pointerOpaqueCoordinates = @()
for ($y = 0; $y -lt 32; $y++) {
    for ($x = 0; $x -lt 32; $x++) {
        if ($pointerBitmap.GetPixel($x, $y).A -eq 255) {
            $pointerOpaqueCoordinates += ,@($x, $y)
        }
    }
}
if ($pointerOpaqueCoordinates.Count -ne $expectedOpaquePixels) {
    $pointerBitmap.Dispose()
    throw "Expected $expectedOpaquePixels opaque Pointer pixels, found $($pointerOpaqueCoordinates.Count)."
}

$work = Read-AniFile (Join-Path $ThemeDirectory 'Work.ani')
$busy = Read-AniFile (Join-Path $ThemeDirectory 'Busy.ani')
$pointerBitmap.Dispose()
if ($work.HeaderFrames -ne 60 -or $work.HeaderSteps -ne 60 -or
    $work.Width -ne 0 -or $work.Height -ne 0 -or $work.Frames.Count -ne 60 -or
    $work.DefaultRate -ne 1) {
    throw 'Work ANI header must describe 60 multi-resolution frames at 1 jiffy.'
}
if ($busy.HeaderFrames -ne 40 -or $busy.HeaderSteps -ne 40 -or
    $busy.Width -ne 32 -or $busy.Height -ne 32 -or $busy.Frames.Count -ne 40 -or
    $busy.DefaultRate -ne 1) {
    throw 'Busy ANI header must describe 40 32px frames at 2 jiffies.'
}
if ($work.Rates.Count -ne 60 -or @($work.Rates | Where-Object { $_ -ne 1 }).Count -ne 0) {
    throw 'Work.ani must use 1 jiffy for all 60 frames.'
}
if ($busy.Rates.Count -ne 40 -or @($busy.Rates | Where-Object { $_ -ne 2 }).Count -ne 0) {
    throw 'Busy.ani must use 2 jiffies for all 40 frames.'
}

$workHashes = @{32 = @(); 48 = @(); 64 = @()}
$firstAlphaMasks = @{}
$minimumColorPixels = [int]::MaxValue
$globalMinX = 31
$globalMaxX = 0
$globalMinY = 31
$globalMaxY = 0
foreach ($frameBytes in $work.Frames) {
    $entries = @(Read-CursorEntries $frameBytes)
    Assert-EqualSequence @($entries.Width) @(32, 48, 64) 'Work frame canvas sizes'
    foreach ($entry in $entries) {
        $size = $entry.Width
        $reference = $pointerEntriesBySize[$size]
        if ($entry.Height -ne $size -or $entry.HotspotX -ne $reference.HotspotX -or
            $entry.HotspotY -ne $reference.HotspotY) {
            throw 'Work frame hotspot differs from its matching Pointer.cur entry.'
        }
        $workHashes[$size] += Get-Sha256 $entry.Png
        $scale = $size / 32.0
        $wheelX = [int][Math]::Round($expectedWheelBounds[0] * $scale, [MidpointRounding]::AwayFromZero)
        $wheelY = [int][Math]::Round($expectedWheelBounds[2] * $scale, [MidpointRounding]::AwayFromZero)
        $wheelSize = [int][Math]::Round(($expectedWheelBounds[1] - $expectedWheelBounds[0] + 1) * $scale,
            [MidpointRounding]::AwayFromZero)
        $bitmap = New-BitmapFromPng $entry.Png
        $pointerBitmap = New-BitmapFromPng $reference.Png
        try {
            if ($bitmap.Width -ne $size -or $bitmap.Height -ne $size) {
                throw 'Work PNG dimensions differ from its directory entry.'
            }
            $alphaMask = [byte[]]::new($size * $size)
            $colorX = @(); $colorY = @()
            for ($y = 0; $y -lt $size; $y++) {
                for ($x = 0; $x -lt $size; $x++) {
                    $color = $bitmap.GetPixel($x, $y)
                    $pointerColor = $pointerBitmap.GetPixel($x, $y)
                    $insideWheelBox = $x -ge $wheelX -and $x -lt ($wheelX + $wheelSize) -and
                        $y -ge $wheelY -and $y -lt ($wheelY + $wheelSize)
                    if ((-not $insideWheelBox -or $pointerColor.A -eq 255) -and
                        $color.ToArgb() -ne $pointerColor.ToArgb()) {
                        throw "Work changed a pointer pixel at ${size}px ($x,$y)."
                    }
                    $alphaMask[$y * $size + $x] = $color.A
                    $maximum = [Math]::Max($color.R, [Math]::Max($color.G, $color.B))
                    $minimum = [Math]::Min($color.R, [Math]::Min($color.G, $color.B))
                    if ($color.A -gt 32 -and ($maximum - $minimum) -gt 45) {
                        if (-not $insideWheelBox) { throw 'The wheel extends outside its fixed bounds.' }
                        $colorX += $x; $colorY += $y
                    }
                }
            }
            $maskHash = Get-Sha256 $alphaMask
            if ($firstAlphaMasks.ContainsKey($size)) {
                if ($firstAlphaMasks[$size] -ne $maskHash) { throw "Work alpha mask changes at ${size}px." }
            }
            else { $firstAlphaMasks[$size] = $maskHash }
            if ($colorX.Count -lt ($expectedMinimumWheelColorPixels * $scale * $scale)) {
                throw "Work color wheel is incomplete at ${size}px: $($colorX.Count) colored pixels."
            }
            if ($size -eq 32) {
                $globalMinX = [Math]::Min($globalMinX, ($colorX | Measure-Object -Minimum).Minimum)
                $globalMaxX = [Math]::Max($globalMaxX, ($colorX | Measure-Object -Maximum).Maximum)
                $globalMinY = [Math]::Min($globalMinY, ($colorY | Measure-Object -Minimum).Minimum)
                $globalMaxY = [Math]::Max($globalMaxY, ($colorY | Measure-Object -Maximum).Maximum)
                $minimumColorPixels = [Math]::Min($minimumColorPixels, $colorX.Count)
            }
        }
        finally {
            $bitmap.Dispose(); $pointerBitmap.Dispose()
        }
    }
}

foreach ($size in @(32, 48, 64)) {
    if (@($workHashes[$size] | Sort-Object -Unique).Count -ne 60) {
        throw "Work must contain 60 unique frames at ${size}px."
    }
}

foreach ($frameBytes in $busy.Frames) {
    $entries = @(Read-CursorEntries $frameBytes)
    if ($entries.Count -ne 1 -or
        $entries[0].Width -ne 32 -or
        $entries[0].Height -ne 32) {
        throw 'Busy.ani contains an invalid frame.'
    }
}

foreach ($assetName in $expectedCursorNames) {
    $assetPath = Join-Path $ThemeDirectory $assetName
    $handle = [BalancedCursorNative]::LoadImage(
        [IntPtr]::Zero,
        $assetPath,
        2,
        0,
        0,
        0x10
    )
    if ($handle -eq [IntPtr]::Zero) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Windows failed to load $assetName (error $errorCode)."
    }
    [void][BalancedCursorNative]::DestroyCursor($handle)
}

function Read-NativeCursor {
    param([string]$Path, [int]$Size)
    $handle = [BalancedCursorNative]::LoadImage([IntPtr]::Zero, $Path, 2, $Size, $Size, 0x10)
    if ($handle -eq [IntPtr]::Zero) {
        throw "Native cursor load failed at ${Size}px: $Path"
    }
    $info = [BalancedCursorNative+IconInfo]::new()
    try {
        if (-not [BalancedCursorNative]::GetIconInfo($handle, [ref]$info)) {
            throw 'GetIconInfo failed.'
        }
        $bitmap = [BalancedCursorNative+BitmapInfo]::new()
        if ([BalancedCursorNative]::GetObject($info.Color,
            [Runtime.InteropServices.Marshal]::SizeOf($bitmap), [ref]$bitmap) -eq 0 -or
            $bitmap.BitsPixel -ne 32) { throw 'Could not inspect the native 32-bit cursor bitmap.' }
        $pixels = [byte[]]::new($bitmap.WidthBytes * $bitmap.Height)
        if ([BalancedCursorNative]::GetBitmapBits($info.Color, $pixels.Length, $pixels) -ne $pixels.Length) {
            throw 'Could not read the native cursor pixels.'
        }
        return [pscustomobject]@{
            Width = $bitmap.Width; Height = $bitmap.Height; Stride = $bitmap.WidthBytes
            HotspotX = $info.HotspotX; HotspotY = $info.HotspotY; Pixels = $pixels
        }
    }
    finally {
        if ($info.Color -ne [IntPtr]::Zero) { [void][BalancedCursorNative]::DeleteObject($info.Color) }
        if ($info.Mask -ne [IntPtr]::Zero) { [void][BalancedCursorNative]::DeleteObject($info.Mask) }
        [void][BalancedCursorNative]::DestroyCursor($handle)
    }
}

$nativeSizes = @()
foreach ($size in @(32, 40, 48, 64)) {
    $pointer = Read-NativeCursor (Join-Path $ThemeDirectory 'Pointer.cur') $size
    $animation = Read-NativeCursor (Join-Path $ThemeDirectory 'Work.ani') $size
    if ($pointer.Width -ne $size -or $pointer.Height -ne $size -or
        $animation.Width -ne $size -or $animation.Height -ne $size -or
        $pointer.HotspotX -ne $animation.HotspotX -or $pointer.HotspotY -ne $animation.HotspotY) {
        throw "Native Work and Pointer sizes or hotspots disagree at ${size}px."
    }
    $pointerRegionWidth = [int][Math]::Floor($expectedWheelBounds[0] * $size / 32.0) - 1
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt ($pointerRegionWidth * 4); $x++) {
            if ($pointer.Pixels[$y * $pointer.Stride + $x] -ne
                $animation.Pixels[$y * $animation.Stride + $x]) {
                throw "Native Work altered the pointer region at ${size}px."
            }
        }
    }
    $nativeSizes += "$size ($($animation.HotspotX),$($animation.HotspotY))"
}

$workHash = (Get-FileHash (Join-Path $ThemeDirectory 'Work.ani') -Algorithm SHA256).Hash
[pscustomobject]@{
    ThemeDirectory = $ThemeDirectory
    StaticCursors = $staticFiles.Count
    NativeLoads = "$($expectedCursorNames.Count)/$($expectedCursorNames.Count)"
    WorkFrames = $work.Frames.Count
    UniqueWorkFramesPerSize = '60/60 at 32,48,64'
    WorkCanvasSizes = '32,48,64'
    FixedAlphaMasks = $firstAlphaMasks.Count
    NativeSizeHotspots = $nativeSizes -join '; '
    Profile = $Profile
    PointerHotspot = "$expectedHotspotX,$expectedHotspotY"
    PointerOpaquePixels = $pointerOpaqueCoordinates.Count
    WorkWheelBounds = "$globalMinX,$globalMinY to $globalMaxX,$globalMaxY"
    MinimumWheelColorPixels = $minimumColorPixels
    WorkJiffies = 1
    WorkRevolutionSeconds = 1
    BusyJiffies = 2
    WorkSha256 = $workHash
} | Format-List

Write-Output "$Profile Windows theme validation passed."
