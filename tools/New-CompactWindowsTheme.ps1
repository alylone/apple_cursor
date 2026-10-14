[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$SourceDirectory = 'C:\Windows\Cursors\macOS-Regular Cursors',
    [string]$BitmapDirectory,
    [string]$OutputDirectory,
    [ValidateSet('Compact', 'Balanced', 'Balanced-Large')]
    [string]$Profile = 'Compact'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot "themes\macOS-$Profile-Windows"
}
if ([string]::IsNullOrWhiteSpace($BitmapDirectory)) {
    $BitmapDirectory = Join-Path $ProjectRoot 'bitmaps\macOS'
}

if ($Profile -eq 'Compact') {
    $themeName = 'macOS-Compact Cursors'
    $cursorDirectoryName = 'macOS-Compact Cursors'
    $animationArtworkSize = 22
    $sizeMappings = @(
        [pscustomobject]@{ Source = 22; Artwork = 22; Target = 32 }
        [pscustomobject]@{ Source = 32; Artwork = 32; Target = 48 }
        [pscustomobject]@{ Source = 43; Artwork = 43; Target = 64 }
        [pscustomobject]@{ Source = 64; Artwork = 64; Target = 96 }
        [pscustomobject]@{ Source = 86; Artwork = 86; Target = 128 }
        [pscustomobject]@{ Source = 171; Artwork = 171; Target = 256 }
    )
}
elseif ($Profile -eq 'Balanced') {
    $themeName = 'macOS-Balanced Cursors'
    $cursorDirectoryName = 'macOS-Balanced Cursors'
    $animationArtworkSize = 22
    $sizeMappings = @(
        [pscustomobject]@{ Source = 22; Artwork = 22; Target = 32 }
        [pscustomobject]@{ Source = 32; Artwork = 32; Target = 48 }
        [pscustomobject]@{ Source = 43; Artwork = 43; Target = 64 }
        [pscustomobject]@{ Source = 64; Artwork = 64; Target = 96 }
        [pscustomobject]@{ Source = 86; Artwork = 86; Target = 128 }
        [pscustomobject]@{ Source = 171; Artwork = 171; Target = 256 }
    )
}
else {
    $themeName = 'macOS-Balanced Large Cursors'
    $cursorDirectoryName = 'macOS-Balanced Large Cursors'
    $animationArtworkSize = 27
    $sizeMappings = @(
        [pscustomobject]@{ Source = 32; Artwork = 27; Target = 32 }
        [pscustomobject]@{ Source = 43; Artwork = 40; Target = 48 }
        [pscustomobject]@{ Source = 64; Artwork = 54; Target = 64 }
        [pscustomobject]@{ Source = 86; Artwork = 81; Target = 96 }
        [pscustomobject]@{ Source = 171; Artwork = 108; Target = 128 }
        [pscustomobject]@{ Source = 171; Artwork = 216; Target = 256 }
    )
}

$designHotspots = @{
    'Alternate.cur' = @(179, 40)
    'Grabbing.cur' = @(139, 86)
    'Handwriting.cur' = @(37, 218)
    'Help.cur' = @(128, 169)
    'Link.cur' = @(92, 53)
    'Pan.cur' = @(134, 81)
    'Person.cur' = @(56, 17)
    'Pin.cur' = @(56, 17)
    'Pointer.cur' = @(80, 38)
    'Text.cur' = @(129, 136)
    'Unavailiable.cur' = @(56, 17)
    'Zoom-in.cur' = @(99, 98)
    'Zoom-out.cur' = @(99, 98)
}

$bitmapNames = @{
    'Alternate.cur' = 'right_ptr.png'
    'Cross.cur' = 'cross.png'
    'Dng1.cur' = 'bottom_right_corner.png'
    'Dng2.cur' = 'bottom_left_corner.png'
    'Grabbing.cur' = 'move.png'
    'Handwriting.cur' = 'pencil.png'
    'Help.cur' = 'question_arrow.png'
    'Horz.cur' = 'sb_h_double_arrow.png'
    'Link.cur' = 'hand2.png'
    'Move.cur' = 'all-scroll.png'
    'Pan.cur' = 'hand1.png'
    'Person.cur' = 'person.png'
    'Pin.cur' = 'pin.png'
    'Pointer.cur' = 'left_ptr.png'
    'Text.cur' = 'xterm.png'
    'Unavailiable.cur' = 'crossed_circle.png'
    'Vert.cur' = 'sb_v_double_arrow.png'
    'Zoom-in.cur' = 'zoom-in.png'
    'Zoom-out.cur' = 'zoom-out.png'
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
        $width = if ($Bytes[$entryOffset] -eq 0) { 256 } else { [int]$Bytes[$entryOffset] }
        $height = if ($Bytes[$entryOffset + 1] -eq 0) { 256 } else { [int]$Bytes[$entryOffset + 1] }
        $imageLength = [BitConverter]::ToUInt32($Bytes, $entryOffset + 8)
        $imageOffset = [BitConverter]::ToUInt32($Bytes, $entryOffset + 12)

        if ($imageOffset + $imageLength -gt $Bytes.Length) {
            throw 'Cursor image extends beyond the end of the file.'
        }
        if ($Bytes[$imageOffset] -ne 0x89 -or
            $Bytes[$imageOffset + 1] -ne 0x50 -or
            $Bytes[$imageOffset + 2] -ne 0x4E -or
            $Bytes[$imageOffset + 3] -ne 0x47) {
            throw "Only PNG cursor entries are supported; found a non-PNG ${width}x${height} entry."
        }

        $png = Copy-ByteRange $Bytes $imageOffset $imageLength
        $pngStream = [IO.MemoryStream]::new($png, $false)
        $pngImage = $null
        try {
            $pngImage = [Drawing.Image]::FromStream($pngStream, $true, $true)
            $pngWidth = $pngImage.Width
            $pngHeight = $pngImage.Height
        }
        finally {
            if ($null -ne $pngImage) { $pngImage.Dispose() }
            $pngStream.Dispose()
        }

        $entries += [pscustomobject]@{
            Width = $width
            Height = $height
            HotspotX = [BitConverter]::ToUInt16($Bytes, $entryOffset + 4)
            HotspotY = [BitConverter]::ToUInt16($Bytes, $entryOffset + 6)
            PngWidth = $pngWidth
            PngHeight = $pngHeight
            Png = $png
        }
    }

    return $entries
}

function Convert-PngCanvas {
    param(
        [byte[]]$Png,
        [int]$CanvasWidth,
        [int]$CanvasHeight,
        [int]$DestinationX,
        [int]$DestinationY,
        [int]$DestinationWidth,
        [int]$DestinationHeight,
        [int]$SourceWidth,
        [int]$SourceHeight,
        [switch]$Scale
    )

    $inputStream = [IO.MemoryStream]::new($Png, $false)
    $sourceImage = $null
    $bitmap = $null
    $graphics = $null
    $outputStream = $null
    try {
        $sourceImage = [Drawing.Image]::FromStream($inputStream, $true, $true)
        $bitmap = [Drawing.Bitmap]::new(
            $CanvasWidth,
            $CanvasHeight,
            [Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy

        if ($Scale) {
            if ($SourceWidth -le 0) { $SourceWidth = $sourceImage.Width }
            if ($SourceHeight -le 0) { $SourceHeight = $sourceImage.Height }
            $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $destination = [Drawing.Rectangle]::new(
                $DestinationX,
                $DestinationY,
                $DestinationWidth,
                $DestinationHeight
            )
            $graphics.DrawImage(
                $sourceImage,
                $destination,
                0,
                0,
                $SourceWidth,
                $SourceHeight,
                [Drawing.GraphicsUnit]::Pixel
            )
        }
        else {
            if ($sourceImage.Width -ne $DestinationWidth -or
                $sourceImage.Height -ne $DestinationHeight) {
                throw 'Unscaled cursor image dimensions do not match the requested destination.'
            }
            $graphics.DrawImageUnscaled($sourceImage, $DestinationX, $DestinationY)
        }

        $outputStream = [IO.MemoryStream]::new()
        $bitmap.Save($outputStream, [Drawing.Imaging.ImageFormat]::Png)
        return $outputStream.ToArray()
    }
    finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $sourceImage) { $sourceImage.Dispose() }
        $inputStream.Dispose()
    }
}

function Expand-PngCanvasExact {
    param(
        [byte[]]$Png,
        [int]$CanvasWidth,
        [int]$CanvasHeight
    )

    $inputStream = [IO.MemoryStream]::new($Png, $false)
    $outputStream = $null
    try {
        $decoder = [Windows.Media.Imaging.PngBitmapDecoder]::new(
            $inputStream,
            [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )
        $source = [Windows.Media.Imaging.FormatConvertedBitmap]::new(
            $decoder.Frames[0],
            [Windows.Media.PixelFormats]::Bgra32,
            $null,
            0
        )
        if ($source.PixelWidth -gt $CanvasWidth -or $source.PixelHeight -gt $CanvasHeight) {
            throw 'Source PNG is larger than the exact-padding canvas.'
        }

        $sourceStride = $source.PixelWidth * 4
        $sourcePixels = [byte[]]::new($sourceStride * $source.PixelHeight)
        $source.CopyPixels($sourcePixels, $sourceStride, 0)

        $targetStride = $CanvasWidth * 4
        $targetPixels = [byte[]]::new($targetStride * $CanvasHeight)
        for ($row = 0; $row -lt $source.PixelHeight; $row++) {
            [Array]::Copy(
                $sourcePixels,
                $row * $sourceStride,
                $targetPixels,
                $row * $targetStride,
                $sourceStride
            )
        }

        $target = [Windows.Media.Imaging.BitmapSource]::Create(
            $CanvasWidth,
            $CanvasHeight,
            96,
            96,
            [Windows.Media.PixelFormats]::Bgra32,
            $null,
            $targetPixels,
            $targetStride
        )
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($target))
        $outputStream = [IO.MemoryStream]::new()
        $encoder.Save($outputStream)
        return $outputStream.ToArray()
    }
    finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        $inputStream.Dispose()
    }
}

function Merge-PngLayers {
    param(
        [byte[]]$BackgroundPng,
        [byte[]]$ForegroundPng
    )

    $backgroundStream = [IO.MemoryStream]::new($BackgroundPng, $false)
    $foregroundStream = [IO.MemoryStream]::new($ForegroundPng, $false)
    $backgroundImage = $null
    $foregroundImage = $null
    $bitmap = $null
    $graphics = $null
    $outputStream = $null
    try {
        $backgroundImage = [Drawing.Image]::FromStream($backgroundStream, $true, $true)
        $foregroundImage = [Drawing.Image]::FromStream($foregroundStream, $true, $true)
        if ($backgroundImage.Width -ne $foregroundImage.Width -or
            $backgroundImage.Height -ne $foregroundImage.Height) {
            throw 'PNG layers must have matching dimensions.'
        }

        $bitmap = [Drawing.Bitmap]::new(
            $backgroundImage.Width,
            $backgroundImage.Height,
            [Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.DrawImageUnscaled($backgroundImage, 0, 0)
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.DrawImageUnscaled($foregroundImage, 0, 0)

        $outputStream = [IO.MemoryStream]::new()
        $bitmap.Save($outputStream, [Drawing.Imaging.ImageFormat]::Png)
        return $outputStream.ToArray()
    }
    finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $foregroundImage) { $foregroundImage.Dispose() }
        if ($null -ne $backgroundImage) { $backgroundImage.Dispose() }
        $foregroundStream.Dispose()
        $backgroundStream.Dispose()
    }
}

function New-CursorBytes {
    param([object[]]$Entries)

    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]2)
        $writer.Write([uint16]$Entries.Count)

        $imageOffset = 6 + (16 * $Entries.Count)
        foreach ($entry in $Entries) {
            $widthByte = if ($entry.Width -eq 256) { 0 } else { $entry.Width }
            $heightByte = if ($entry.Height -eq 256) { 0 } else { $entry.Height }
            $writer.Write([byte]$widthByte)
            $writer.Write([byte]$heightByte)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]$entry.HotspotX)
            $writer.Write([uint16]$entry.HotspotY)
            $writer.Write([uint32]$entry.Png.Length)
            $writer.Write([uint32]$imageOffset)
            $imageOffset += $entry.Png.Length
        }

        foreach ($entry in $Entries) {
            $writer.Write([byte[]]$entry.Png)
        }

        $writer.Flush()
        return $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Convert-StaticCursor {
    param(
        [string]$SourcePath,
        [string]$OutputPath,
        [int]$DesignHotspotX,
        [int]$DesignHotspotY
    )

    $sourceEntries = @(Read-CursorEntries ([IO.File]::ReadAllBytes($SourcePath)))
    $outputEntries = @()

    foreach ($mapping in $sizeMappings) {
        $matchingEntries = @($sourceEntries | Where-Object {
            $_.Width -eq $mapping.Source -and $_.Height -eq $mapping.Source
        })
        if ($matchingEntries.Count -ne 1) {
            throw "Expected one $($mapping.Source)x$($mapping.Source) entry in $SourcePath."
        }

        $sourceEntry = $matchingEntries[0]
        if ($Profile -eq 'Compact') {
            if ($sourceEntry.PngWidth -gt $mapping.Target -or
                $sourceEntry.PngHeight -gt $mapping.Target) {
                throw "Embedded PNG is larger than the target canvas in $SourcePath."
            }
            if ($sourceEntry.PngWidth -eq $mapping.Target -and
                $sourceEntry.PngHeight -eq $mapping.Target) {
                $outputPng = $sourceEntry.Png
            }
            else {
                $pngArguments = @{
                    Png = $sourceEntry.Png
                    CanvasWidth = $mapping.Target
                    CanvasHeight = $mapping.Target
                }
                $outputPng = Expand-PngCanvasExact @pngArguments
            }
            $hotspotX = $sourceEntry.HotspotX
            $hotspotY = $sourceEntry.HotspotY
        }
        else {
            $pngArguments = @{
                Png = $sourceEntry.Png
                CanvasWidth = $mapping.Target
                CanvasHeight = $mapping.Target
                DestinationX = 0
                DestinationY = 0
                DestinationWidth = $mapping.Artwork
                DestinationHeight = $mapping.Artwork
                SourceWidth = $mapping.Source
                SourceHeight = $mapping.Source
                Scale = $true
            }
            $outputPng = Convert-PngCanvas @pngArguments
            $hotspotX = [Math]::Floor($DesignHotspotX * $mapping.Artwork / 256)
            $hotspotY = [Math]::Floor($DesignHotspotY * $mapping.Artwork / 256)
        }
        $outputEntries += [pscustomobject]@{
            Width = $mapping.Target
            Height = $mapping.Target
            HotspotX = $hotspotX
            HotspotY = $hotspotY
            Png = $outputPng
        }
    }

    [IO.File]::WriteAllBytes($OutputPath, (New-CursorBytes $outputEntries))
}

function Convert-BitmapCursor {
    param(
        [string]$SourcePngPath,
        [string]$OutputPath,
        [int]$DesignHotspotX,
        [int]$DesignHotspotY
    )

    $sourcePng = [IO.File]::ReadAllBytes($SourcePngPath)
    $outputEntries = @()
    foreach ($mapping in $sizeMappings) {
        $pngArguments = @{
            Png = $sourcePng
            CanvasWidth = $mapping.Target
            CanvasHeight = $mapping.Target
            DestinationX = 0
            DestinationY = 0
            DestinationWidth = $mapping.Artwork
            DestinationHeight = $mapping.Artwork
            SourceWidth = 256
            SourceHeight = 256
            Scale = $true
        }
        $outputEntries += [pscustomobject]@{
            Width = $mapping.Target
            Height = $mapping.Target
            HotspotX = [Math]::Floor($DesignHotspotX * $mapping.Artwork / 256)
            HotspotY = [Math]::Floor($DesignHotspotY * $mapping.Artwork / 256)
            Png = Convert-PngCanvas @pngArguments
        }
    }

    [IO.File]::WriteAllBytes($OutputPath, (New-CursorBytes $outputEntries))
}

function New-RiffChunk {
    param(
        [string]$Id,
        [byte[]]$Data
    )

    if ($Id.Length -ne 4) { throw "RIFF chunk IDs must be four characters: $Id" }
    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes($Id))
        $writer.Write([uint32]$Data.Length)
        $writer.Write($Data)
        if (($Data.Length % 2) -ne 0) { $writer.Write([byte]0) }
        $writer.Flush()
        return $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Convert-AnimationFrame {
    param(
        [byte[]]$CursorBytes,
        [int]$ArtworkHotspotX,
        [int]$ArtworkHotspotY,
        [int]$ArtworkSize
    )

    $entries = @(Read-CursorEntries $CursorBytes)
    if ($entries.Count -ne 1 -or $entries[0].Width -ne 65 -or $entries[0].Height -ne 65) {
        throw 'Expected a single 65x65 PNG frame in the Regular animation.'
    }

    $canvasSize = 32
    $pngArguments = @{
        Png = $entries[0].Png
        CanvasWidth = $canvasSize
        CanvasHeight = $canvasSize
        DestinationX = 0
        DestinationY = 0
        DestinationWidth = $ArtworkSize
        DestinationHeight = $ArtworkSize
        SourceWidth = 65
        SourceHeight = 65
        Scale = $true
    }
    $outputPng = Convert-PngCanvas @pngArguments
    $outputEntry = [pscustomobject]@{
        Width = $canvasSize
        Height = $canvasSize
        HotspotX = $ArtworkHotspotX
        HotspotY = $ArtworkHotspotY
        Png = $outputPng
    }
    return New-CursorBytes @($outputEntry)
}

function Convert-BitmapAnimationFrame {
    param(
        [byte[]]$Png,
        [int]$ArtworkHotspotX,
        [int]$ArtworkHotspotY,
        [int]$ArtworkSize
    )

    $pngArguments = @{
        Png = $Png
        CanvasWidth = 32
        CanvasHeight = 32
        DestinationX = 0
        DestinationY = 0
        DestinationWidth = $ArtworkSize
        DestinationHeight = $ArtworkSize
        SourceWidth = 256
        SourceHeight = 256
        Scale = $true
    }
    $outputEntry = [pscustomobject]@{
        Width = 32
        Height = 32
        HotspotX = $ArtworkHotspotX
        HotspotY = $ArtworkHotspotY
        Png = Convert-PngCanvas @pngArguments
    }
    return New-CursorBytes @($outputEntry)
}

function Convert-LayeredWorkAnimationFrame {
    param(
        [object]$Renderer,
        [object[]]$PointerEntries,
        [int]$FrameIndex,
        [int]$FrameCount,
        [int]$ArtworkSize
    )

    $baseSize = [Math]::Min(11, [Math]::Round(0.46 * $ArtworkSize))
    $baseX = [Math]::Min(
        32 - $baseSize,
        [Math]::Round(180 * $ArtworkSize / 256) + 1
    )
    $baseY = [Math]::Round(85 * $ArtworkSize / 256)
    $outputEntries = @()
    foreach ($pointerEntry in $PointerEntries) {
        $scale = $pointerEntry.Width / 32.0
        $wheelX = [int][Math]::Round($baseX * $scale, [MidpointRounding]::AwayFromZero)
        $wheelY = [int][Math]::Round($baseY * $scale, [MidpointRounding]::AwayFromZero)
        $wheelSize = [int][Math]::Round($baseSize * $scale, [MidpointRounding]::AwayFromZero)
        $outputEntries += [pscustomobject]@{
            Width = $pointerEntry.Width
            Height = $pointerEntry.Height
            HotspotX = $pointerEntry.HotspotX
            HotspotY = $pointerEntry.HotspotY
            Png = $Renderer.Render($pointerEntry.Png, $wheelX, $wheelY, $wheelSize,
                (360.0 * $FrameIndex / $FrameCount))
        }
    }
    return New-CursorBytes $outputEntries
}

function Convert-Animation {
    param(
        [string]$SourcePath,
        [string]$OutputPath,
        [int]$ArtworkHotspotX,
        [int]$ArtworkHotspotY,
        [int]$ArtworkSize,
        [string[]]$FramePngFiles
    )

    $bytes = [IO.File]::ReadAllBytes($SourcePath)
    if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or
        [Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne 'ACON') {
        throw "Invalid ANI file: $SourcePath"
    }

    $topLevelChunks = @()
    $position = 12
    while ($position + 8 -le $bytes.Length) {
        $chunkId = [Text.Encoding]::ASCII.GetString($bytes, $position, 4)
        $chunkLength = [BitConverter]::ToUInt32($bytes, $position + 4)
        $dataOffset = $position + 8
        $chunkData = Copy-ByteRange $bytes $dataOffset $chunkLength

        if ($chunkId -eq 'anih') {
            if ($chunkData.Length -lt 20) { throw 'ANI header is too short.' }
            [BitConverter]::GetBytes([uint32]32).CopyTo($chunkData, 12)
            [BitConverter]::GetBytes([uint32]32).CopyTo($chunkData, 16)
            $topLevelChunks += ,(New-RiffChunk 'anih' $chunkData)
        }
        elseif ($chunkId -eq 'LIST' -and
                [Text.Encoding]::ASCII.GetString($chunkData, 0, 4) -eq 'fram') {
            $frameChunks = @()
            $framePosition = 4
            $frameIndex = 0
            while ($framePosition + 8 -le $chunkData.Length) {
                $frameId = [Text.Encoding]::ASCII.GetString($chunkData, $framePosition, 4)
                $frameLength = [BitConverter]::ToUInt32($chunkData, $framePosition + 4)
                $frameDataOffset = $framePosition + 8
                $frameData = Copy-ByteRange $chunkData $frameDataOffset $frameLength
                if ($frameId -eq 'icon') {
                    if ($null -ne $FramePngFiles -and $FramePngFiles.Count -gt 0) {
                        if ($frameIndex -ge $FramePngFiles.Count) {
                            throw 'Not enough PNG frames were provided for the ANI template.'
                        }
                        $frameArguments = @{
                            Png = [IO.File]::ReadAllBytes($FramePngFiles[$frameIndex])
                            ArtworkHotspotX = $ArtworkHotspotX
                            ArtworkHotspotY = $ArtworkHotspotY
                            ArtworkSize = $ArtworkSize
                        }
                        $frameData = Convert-BitmapAnimationFrame @frameArguments
                    }
                    else {
                        $frameArguments = @{
                            CursorBytes = $frameData
                            ArtworkHotspotX = $ArtworkHotspotX
                            ArtworkHotspotY = $ArtworkHotspotY
                            ArtworkSize = $ArtworkSize
                        }
                        $frameData = Convert-AnimationFrame @frameArguments
                    }
                    $frameIndex++
                }
                $frameChunks += ,(New-RiffChunk $frameId $frameData)
                $framePosition = $frameDataOffset + $frameLength + ($frameLength % 2)
            }
            if ($null -ne $FramePngFiles -and
                $FramePngFiles.Count -gt 0 -and
                $frameIndex -ne $FramePngFiles.Count) {
                throw "ANI template used $frameIndex of $($FramePngFiles.Count) provided frames."
            }

            $listStream = [IO.MemoryStream]::new()
            try {
                $listStream.Write([Text.Encoding]::ASCII.GetBytes('fram'), 0, 4)
                foreach ($frameChunk in $frameChunks) {
                    $listStream.Write($frameChunk, 0, $frameChunk.Length)
                }
                $topLevelChunks += ,(New-RiffChunk 'LIST' $listStream.ToArray())
            }
            finally {
                $listStream.Dispose()
            }
        }
        else {
            $topLevelChunks += ,(New-RiffChunk $chunkId $chunkData)
        }

        $position = $dataOffset + $chunkLength + ($chunkLength % 2)
    }

    $aconStream = [IO.MemoryStream]::new()
    try {
        $aconStream.Write([Text.Encoding]::ASCII.GetBytes('ACON'), 0, 4)
        foreach ($chunk in $topLevelChunks) {
            $aconStream.Write($chunk, 0, $chunk.Length)
        }
        $aconData = $aconStream.ToArray()
    }
    finally {
        $aconStream.Dispose()
    }

    $outputStream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($outputStream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([uint32]$aconData.Length)
        $writer.Write($aconData)
        $writer.Flush()
        [IO.File]::WriteAllBytes($OutputPath, $outputStream.ToArray())
    }
    finally {
        $writer.Dispose()
        $outputStream.Dispose()
    }
}

function New-BitmapAnimation {
    param(
        [string[]]$FramePngFiles,
        [string]$OutputPath,
        [int]$ArtworkHotspotX,
        [int]$ArtworkHotspotY,
        [int]$ArtworkSize,
        [string]$PointerCursorPath,
        [ValidateRange(1, 60)]
        [int]$FrameJiffies = 2
    )

    $isWork = -not [string]::IsNullOrWhiteSpace($PointerCursorPath)
    if (-not $isWork -and $FramePngFiles.Count -ne 40) {
        throw "Expected 40 animation PNGs, found $($FramePngFiles.Count)."
    }
    if ($isWork -and $FramePngFiles.Count -lt 1) {
        throw 'The Work animation requires a canonical wheel PNG.'
    }
    $frameCount = if ($isWork) { 60 } else { $FramePngFiles.Count }
    $canvasSize = if ($isWork) { 0 } else { 32 }
    # Keep Busy.ani byte-for-byte compatible; its rate chunk already sets 2 jiffies.
    $headerRate = if ($isWork) { $FrameJiffies } else { 1 }
    if ($isWork) {
        if (-not ('WorkAnimationRenderer' -as [type])) {
            $drawingReferences = @(
                [Drawing.Bitmap].Assembly.Location,
                [Drawing.Color].Assembly.Location
                # Newer PowerShell runtimes split GDI+ into additional assemblies.
                [AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -like 'System.Private.Windows.*' } |
                    ForEach-Object Location
            ) | Select-Object -Unique
            Add-Type -Path (Join-Path $PSScriptRoot 'WorkAnimationRenderer.cs') `
                -ReferencedAssemblies $drawingReferences
        }
        $renderer = [WorkAnimationRenderer]::new([IO.File]::ReadAllBytes($FramePngFiles[0]))
        $pointerEntries = @(Read-CursorEntries ([IO.File]::ReadAllBytes($PointerCursorPath)) |
            Where-Object Width -in @(32, 48, 64))
        if ($pointerEntries.Count -ne 3) {
            throw 'Work requires the 32px, 48px and 64px Pointer.cur entries.'
        }
    }

    $frameListStream = [IO.MemoryStream]::new()
    try {
        $frameListStream.Write([Text.Encoding]::ASCII.GetBytes('fram'), 0, 4)
        for ($frameIndex = 0; $frameIndex -lt $frameCount; $frameIndex++) {
            if (-not $isWork) {
                $frameArguments = @{
                    Png = [IO.File]::ReadAllBytes($FramePngFiles[$frameIndex])
                    ArtworkHotspotX = $ArtworkHotspotX
                    ArtworkHotspotY = $ArtworkHotspotY
                    ArtworkSize = $ArtworkSize
                }
                $cursorFrame = Convert-BitmapAnimationFrame @frameArguments
            }
            else {
                $frameArguments = @{
                    Renderer = $renderer
                    PointerEntries = $pointerEntries
                    FrameIndex = $frameIndex
                    FrameCount = $frameCount
                    ArtworkSize = $ArtworkSize
                }
                $cursorFrame = Convert-LayeredWorkAnimationFrame @frameArguments
            }
            $iconChunk = New-RiffChunk 'icon' $cursorFrame
            $frameListStream.Write($iconChunk, 0, $iconChunk.Length)
        }
        $frameListChunk = New-RiffChunk 'LIST' $frameListStream.ToArray()
    }
    finally {
        $frameListStream.Dispose()
    }

    $headerStream = [IO.MemoryStream]::new()
    $headerWriter = [IO.BinaryWriter]::new($headerStream)
    try {
        foreach ($value in @(36, $frameCount, $frameCount, $canvasSize, $canvasSize, 32, 1, $headerRate, 1)) {
            $headerWriter.Write([uint32]$value)
        }
        $headerWriter.Flush()
        $headerChunk = New-RiffChunk 'anih' $headerStream.ToArray()
    }
    finally {
        $headerWriter.Dispose()
        $headerStream.Dispose()
    }

    $rateStream = [IO.MemoryStream]::new()
    $rateWriter = [IO.BinaryWriter]::new($rateStream)
    try {
        for ($index = 0; $index -lt $frameCount; $index++) {
            $rateWriter.Write([uint32]$FrameJiffies)
        }
        $rateWriter.Flush()
        $rateChunk = New-RiffChunk 'rate' $rateStream.ToArray()
    }
    finally {
        $rateWriter.Dispose()
        $rateStream.Dispose()
    }

    $aconStream = [IO.MemoryStream]::new()
    try {
        $aconStream.Write([Text.Encoding]::ASCII.GetBytes('ACON'), 0, 4)
        foreach ($chunk in @($headerChunk, $frameListChunk, $rateChunk)) {
            $aconStream.Write($chunk, 0, $chunk.Length)
        }
        $aconData = $aconStream.ToArray()
    }
    finally {
        $aconStream.Dispose()
    }

    $outputStream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($outputStream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([uint32]$aconData.Length)
        $writer.Write($aconData)
        $writer.Flush()
        [IO.File]::WriteAllBytes($OutputPath, $outputStream.ToArray())
    }
    finally {
        $writer.Dispose()
        $outputStream.Dispose()
    }
}

[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$staticFileCount = 19

if ($Profile -eq 'Compact') {
    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        throw "Regular cursor source directory not found: $SourceDirectory"
    }
    $staticFiles = @(Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.cur' -File)
    if ($staticFiles.Count -ne $staticFileCount) {
        throw "Expected $staticFileCount static Regular cursors, found $($staticFiles.Count)."
    }
    foreach ($sourceFile in $staticFiles) {
        $designHotspot = if ($designHotspots.ContainsKey($sourceFile.Name)) {
            $designHotspots[$sourceFile.Name]
        }
        else {
            @(128, 128)
        }
        $staticArguments = @{
            SourcePath = $sourceFile.FullName
            OutputPath = Join-Path $OutputDirectory $sourceFile.Name
            DesignHotspotX = $designHotspot[0]
            DesignHotspotY = $designHotspot[1]
        }
        Convert-StaticCursor @staticArguments
    }

    # The Regular upstream config emits both animations as 65px-only resources.
    $busyArguments = @{
        SourcePath = Join-Path $SourceDirectory 'Busy.ani'
        OutputPath = Join-Path $OutputDirectory 'Busy.ani'
        ArtworkHotspotX = [Math]::Floor(128 * $animationArtworkSize / 256)
        ArtworkHotspotY = [Math]::Floor(128 * $animationArtworkSize / 256)
        ArtworkSize = $animationArtworkSize
    }
    Convert-Animation @busyArguments
    $workArguments = @{
        SourcePath = Join-Path $SourceDirectory 'Work.ani'
        OutputPath = Join-Path $OutputDirectory 'Work.ani'
        ArtworkHotspotX = [Math]::Floor(56 * $animationArtworkSize / 256)
        ArtworkHotspotY = [Math]::Floor(17 * $animationArtworkSize / 256)
        ArtworkSize = $animationArtworkSize
    }
    Convert-Animation @workArguments
}
else {
    if (-not (Test-Path -LiteralPath $BitmapDirectory -PathType Container)) {
        throw "Rendered bitmap directory not found: $BitmapDirectory. Run 'npx cbmp render.json' first."
    }
    foreach ($cursorName in $bitmapNames.Keys) {
        $sourcePngPath = Join-Path $BitmapDirectory $bitmapNames[$cursorName]
        if (-not (Test-Path -LiteralPath $sourcePngPath -PathType Leaf)) {
            throw "Required rendered bitmap not found: $sourcePngPath"
        }
        $designHotspot = if ($designHotspots.ContainsKey($cursorName)) {
            $designHotspots[$cursorName]
        }
        else {
            @(128, 128)
        }
        $staticArguments = @{
            SourcePngPath = $sourcePngPath
            OutputPath = Join-Path $OutputDirectory $cursorName
            DesignHotspotX = $designHotspot[0]
            DesignHotspotY = $designHotspot[1]
        }
        Convert-BitmapCursor @staticArguments
    }

    $busyFrames = @(Get-ChildItem -LiteralPath $BitmapDirectory -Filter 'wait-*.png' -File |
        Sort-Object Name | ForEach-Object FullName)
    $busyArguments = @{
        FramePngFiles = $busyFrames
        OutputPath = Join-Path $OutputDirectory 'Busy.ani'
        ArtworkHotspotX = [Math]::Floor(128 * $animationArtworkSize / 256)
        ArtworkHotspotY = [Math]::Floor(128 * $animationArtworkSize / 256)
        ArtworkSize = $animationArtworkSize
    }
    New-BitmapAnimation @busyArguments
    $workArguments = @{
        FramePngFiles = $busyFrames
        OutputPath = Join-Path $OutputDirectory 'Work.ani'
        ArtworkHotspotX = [Math]::Floor(80 * $animationArtworkSize / 256)
        ArtworkHotspotY = [Math]::Floor(38 * $animationArtworkSize / 256)
        ArtworkSize = $animationArtworkSize
        PointerCursorPath = Join-Path $OutputDirectory 'Pointer.cur'
        FrameJiffies = 1
    }
    New-BitmapAnimation @workArguments
}

$installInf = @'
; __PROFILE__ Apple Cursor theme for standard Windows cursor slots.

[Version]
Signature="$CHICAGO$"

[DefaultInstall]
CopyFiles=Scheme.Cur
AddReg=Scheme.Reg

[DestinationDirs]
Scheme.Cur=10,"%CUR_DIR%"

[Scheme.Reg]
HKCU,"Control Panel\Cursors\Schemes","%SCHEME_NAME%",,"%10%\%CUR_DIR%\Pointer.cur,%10%\%CUR_DIR%\Help.cur,%10%\%CUR_DIR%\Work.ani,%10%\%CUR_DIR%\Busy.ani,%10%\%CUR_DIR%\Cross.cur,%10%\%CUR_DIR%\Text.cur,%10%\%CUR_DIR%\Handwriting.cur,%10%\%CUR_DIR%\Unavailiable.cur,%10%\%CUR_DIR%\Vert.cur,%10%\%CUR_DIR%\Horz.cur,%10%\%CUR_DIR%\Dng1.cur,%10%\%CUR_DIR%\Dng2.cur,%10%\%CUR_DIR%\Move.cur,%10%\%CUR_DIR%\Alternate.cur,%10%\%CUR_DIR%\Link.cur,%10%\%CUR_DIR%\Pin.cur,%10%\%CUR_DIR%\Person.cur"

[Scheme.Cur]
Alternate.cur
Busy.ani
Cross.cur
Dng1.cur
Dng2.cur
Grabbing.cur
Handwriting.cur
Help.cur
Horz.cur
Link.cur
Move.cur
Pan.cur
Person.cur
Pin.cur
Pointer.cur
Text.cur
Unavailiable.cur
Vert.cur
Work.ani
Zoom-in.cur
Zoom-out.cur

[Strings]
CUR_DIR="Cursors\__CURSOR_DIRECTORY__"
SCHEME_NAME="__THEME_NAME__"
'@
$installInf = $installInf.Replace('__PROFILE__', $Profile)
$installInf = $installInf.Replace('__CURSOR_DIRECTORY__', $cursorDirectoryName)
$installInf = $installInf.Replace('__THEME_NAME__', $themeName)
Set-Content -LiteralPath (Join-Path $OutputDirectory 'install.inf') -Value $installInf -Encoding Ascii -NoNewline

Write-Output "Generated $Profile Windows theme: $OutputDirectory"
$totalAnimationFrames = if ($Profile -eq 'Compact') { 80 } else { 100 }
Write-Output "Static cursors: $staticFileCount; animation frames: $totalAnimationFrames"
