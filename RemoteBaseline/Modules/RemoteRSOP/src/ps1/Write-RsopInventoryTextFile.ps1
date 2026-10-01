<#PSScriptInfo

.DESCRIPTION Writes text to a file as UTF-8 without a byte order mark

.VERSION 1.2.0

.GUID cea497c7-0c5f-4735-8253-6c9cfb5d9e7d

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Write-RsopInventoryTextFile {

    <#
    .SYNOPSIS
        Writes text to a file as UTF-8 without a byte order mark.

    .DESCRIPTION
        Used for every text file the host writes into a per-computer folder or the run folder
        (system.json, summary.json, raw.json, run.json), so all of them share one consistent
        encoding regardless of what the content happens to contain.

    .PARAMETER Path
        The file to write.

    .PARAMETER Content
        The text to write. May be an empty string.

    .NOTES
        FUNCTION: Write-RsopInventoryTextFile
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
