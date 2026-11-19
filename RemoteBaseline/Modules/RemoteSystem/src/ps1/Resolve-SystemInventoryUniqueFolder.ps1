<#PSScriptInfo

.DESCRIPTION Creates a new directory at Path, or Path with a numbered suffix appended if Path exists

.VERSION 1.0.0

.GUID 9fc81d21-0648-4f16-a083-fae34545a1e7

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Resolve-SystemInventoryUniqueFolder
function Resolve-SystemInventoryUniqueFolder {

    <#
    .SYNOPSIS
        Creates a new directory at Path, or Path with _2, _3 and so on appended if Path exists.

    .DESCRIPTION
        Creates the directory without overwriting anything already there. When the candidate name
        is already taken, a numbered suffix is appended until an unused name is found, which is
        what keeps two folders from silently overwriting each other, for example two different
        targets reporting the same computer name and build in the same run, or a second call
        landing in the same second. Returns the path actually created.

    .PARAMETER Path
        The candidate path to create.

    .NOTES
        FUNCTION: Resolve-SystemInventoryUniqueFolder
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String]$Path
    )

    $candidate = $Path
    $suffix = 1
    while (Test-Path -LiteralPath $candidate) {
        $suffix++
        $candidate = $Path + '_' + $suffix
    }
    New-Item -Path $candidate -ItemType Directory -ErrorAction Stop -WhatIf:$false -Confirm:$false | Out-Null
    return $candidate
}
#endregion
