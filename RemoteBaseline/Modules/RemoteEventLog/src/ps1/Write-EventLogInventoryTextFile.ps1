<#PSScriptInfo

.DESCRIPTION Writes text to a file as UTF-8 without a byte order mark

.VERSION 1.0.0

.GUID 6322ab41-33e3-43ee-a567-d21d00d33bfc

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Write-EventLogInventoryTextFile
function Write-EventLogInventoryTextFile {

    <#
    .SYNOPSIS
        Writes text to a file as UTF-8 without a byte order mark.

    .DESCRIPTION
        Used for every text file the host writes into a per-computer folder or the run folder
        (system.json, summary.json, run.json, logs.json, accounts.json, appcontainers.json), so
        all of them share one consistent encoding regardless of what the content happens to contain.

    .PARAMETER Path
        The file to write.

    .PARAMETER Content
        The text to write. May be an empty string.

    .NOTES
        FUNCTION: Write-EventLogInventoryTextFile
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        None.
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [String]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}
#endregion
