<#PSScriptInfo

.DESCRIPTION Writes text to a file as UTF-8 without a byte order mark

.VERSION 1.0.0

.GUID 31484105-8a5d-4479-a880-3e2344abb44e

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Write-RemoteBaselineTextFile {

    <#
    .SYNOPSIS
        Writes text to a file as UTF-8 without a byte order mark.

    .DESCRIPTION
        Used for every text file the module writes (run.json, host.json, manifest.sha256), so all
        of them share one consistent encoding regardless of what the content happens to contain.
        The code is the same as the collectors' text writer.

    .PARAMETER Path
        The file to write.

    .PARAMETER Content
        The text to write. May be an empty string.

    .NOTES
        FUNCTION: Write-RemoteBaselineTextFile
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        None.
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}
