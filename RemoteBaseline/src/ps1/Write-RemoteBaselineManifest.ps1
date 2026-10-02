<#PSScriptInfo

.DESCRIPTION Writes manifest.sha256, the SHA-256 of every file of the run folder

.VERSION 1.1.0

.GUID dc3a4733-7c1a-45e5-820b-590706911f11

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Write-RemoteBaselineManifest {

    <#
    .SYNOPSIS
        Writes manifest.sha256, the SHA-256 of every file of the run folder.

    .DESCRIPTION
        Writes <RunFolder>\manifest.sha256 with one line per file under the run folder except the
        manifest itself: the SHA-256 as lower-case hex, two spaces, and the path relative to the
        run folder with forward slashes. Lines are sorted ordinal by path, end in LF, and the
        file is UTF-8 without a byte order mark, so sha256sum -c reads it on any system. Hashes
        come from Get-FileHash -Algorithm SHA256, which uses the .NET provider that works on a
        FIPS-enforced Windows PowerShell 5.1 host.

        Every hash is computed before anything is written, and the file is written once. When any
        step fails the half-written file, if any, is removed and the error is thrown, so a failure
        leaves no partial manifest; the caller turns it into a "manifest: <message>" line.

    .PARAMETER RunFolder
        The umbrella run folder.

    .NOTES
        FUNCTION: Write-RemoteBaselineManifest
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

    $manifestPath = Join-Path -Path $RunFolder -ChildPath 'manifest.sha256'
    try {
        $rootPath = (Get-Item -LiteralPath $RunFolder -ErrorAction Stop).FullName.TrimEnd('\', '/')

        $pathToFile = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
        foreach ($file in @(Get-ChildItem -LiteralPath $RunFolder -Recurse -File -Force -ErrorAction Stop)) {
            if ($file.FullName -ieq $manifestPath) { continue }
            $relative = $file.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
            $pathToFile[$relative] = $file.FullName
        }

        $sortedPaths = [string[]]@($pathToFile.Keys)
        [System.Array]::Sort($sortedPaths, [System.StringComparer]::Ordinal)

        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($relative in $sortedPaths) {
            $hash = (Get-FileHash -LiteralPath $pathToFile[$relative] -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            [void]$lines.Add($hash + '  ' + $relative)
        }

        # LF after every line, the last one included, the way sha256sum writes it.
        $content = ($lines.ToArray() -join "`n") + "`n"
        Write-RemoteBaselineTextFile -Path $manifestPath -Content $content
    } catch {
        $failure = $_
        Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
        throw $failure
    }
}
