<#PSScriptInfo

.DESCRIPTION Writes the run folder as one zip beside it, with forward-slash entry names

.VERSION 1.0.0

.GUID 5f0b8a1e-7c34-4d2a-9b6e-2a41c8d3e957

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Compress-RemoteBaselineRunFolder {

    <#
    .SYNOPSIS
        Writes the run folder as one zip beside it, with forward-slash entry names.

    .DESCRIPTION
        Writes <RunFolder>.zip with System.IO.Compression.ZipArchive: one entry per file under the
        run folder, entry names relative to the run folder with forward slashes, Optimal
        compression, entries in ordinal order of the relative path (the order of manifest.sha256),
        manifest.sha256 included. The file's last write time is kept on the entry, as the file's
        local time (a zip stores local DOS time, two-second precision), clamped into the range a
        zip can hold.

        Compress-Archive is not used: in Windows PowerShell 5.1 it writes entry names with
        backslashes, which an unzip on Linux or macOS reads as one flat file name. Zip64 is used by
        the archive class as needed, so there is no 2 GB limit. The assembly is loaded with
        Add-Type where the type is not already there (Windows PowerShell 5.1).

        The target must not exist: a zip that is already there is never replaced or removed, and
        the call throws. When writing fails part way, the partial zip this call created is removed
        and the error is thrown, so a failure leaves no partial archive; the caller turns the
        message into a "zip: <message>" line.

    .PARAMETER RunFolder
        The umbrella run folder. The zip is written beside it, as <RunFolder>.zip.

    .NOTES
        FUNCTION: Compress-RemoteBaselineRunFolder
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        None.
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$RunFolder
    )

    Set-StrictMode -Version Latest

    # Windows PowerShell 5.1 has neither type loaded; ZipArchive lives in System.IO.Compression and ZipFile in the FileSystem assembly, so both are named. On PowerShell 7 both are already in the box.
    if (-not ('System.IO.Compression.ZipFile' -as [type]) -or -not ('System.IO.Compression.ZipArchive' -as [type])) {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    $rootPath = (Get-Item -LiteralPath $RunFolder -ErrorAction Stop).FullName.TrimEnd('\', '/')
    $zipPath = $rootPath + '.zip'

    # Refused before anything is opened, outside the cleanup below: a zip that was there is not ours to remove.
    if (Test-Path -LiteralPath $zipPath) {
        throw "the archive $zipPath already exists"
    }

    # The same relative paths and the same ordinal order as the manifest, so the two agree entry for line.
    $pathToFile = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
    foreach ($file in @(Get-ChildItem -LiteralPath $RunFolder -Recurse -File -Force -ErrorAction Stop)) {
        $relative = $file.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
        $pathToFile[$relative] = $file.FullName
    }
    $sortedPaths = [string[]]@($pathToFile.Keys)
    [System.Array]::Sort($sortedPaths, [System.StringComparer]::Ordinal)

    # A zip stores DOS time, 1980 to 2107; a value outside that makes the entry setter throw.
    $earliest = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $latest = [DateTimeOffset]::new(2107, 12, 31, 23, 59, 58, [TimeSpan]::Zero)

    $archive = $null
    $succeeded = $false
    try {
        # Create mode opens with CreateNew, so a zip that appears after the check above makes this throw before $archive is set and is left alone.
        $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)

        foreach ($relative in $sortedPaths) {
            $sourcePath = $pathToFile[$relative]
            $entry = $archive.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
            $sourceStream = $null
            $entryStream = $null
            try {
                # The file's local time, not UTC: the zip format stores local DOS time, so a UTC value would extract shifted by the UTC offset. The DateTime is Kind Local, so the DateTimeOffset carries the local offset and its clock time is the file's.
                $stamp = [DateTimeOffset]::new((Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop).LastWriteTime)
                if ($stamp -lt $earliest) { $stamp = $earliest }
                if ($stamp -gt $latest) { $stamp = $latest }
                $entry.LastWriteTime = $stamp

                $sourceStream = [System.IO.File]::Open($sourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $entryStream = $entry.Open()
                $sourceStream.CopyTo($entryStream)
            } finally {
                if ($null -ne $entryStream) { $entryStream.Dispose() }
                if ($null -ne $sourceStream) { $sourceStream.Dispose() }
            }
        }

        # Disposing writes the central directory, so it sits inside the try: a failure there is a failed archive too.
        $archive.Dispose()
        $archive = $null
        $succeeded = $true
    } finally {
        if ($null -ne $archive) {
            try { $archive.Dispose() } catch { Write-Verbose "Could not close the partial archive: $($_.Exception.Message)" }
            # Only an archive this call opened is removed, and only after its handle is closed.
            if (-not $succeeded) {
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
            }
        }
    }
}
