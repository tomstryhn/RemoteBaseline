<#PSScriptInfo

.DESCRIPTION Collapses a message to one trimmed line

.VERSION 1.0.0

.GUID ccfd5cbe-0bda-45e9-83ca-25343022da0c

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function ConvertTo-RemoteBaselineOneLine {

    <#
    .SYNOPSIS
        Collapses a message to one trimmed line.

    .DESCRIPTION
        The output convention (version 1.2) makes every Error and Errors entry one trimmed line
        with internal whitespace collapsed to one space. Every message the module adds (a thrown
        message, a path, a collector's own entry) goes through this one function so that rule
        lives in one place. A null value gives an empty string.

    .PARAMETER Text
        The message.

    .NOTES
        FUNCTION: ConvertTo-RemoteBaselineOneLine
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String
    #>

    param(
        [AllowNull()]
        [AllowEmptyString()]
        $Text
    )

    if ($null -eq $Text) { return '' }
    return (([string]$Text).Trim() -replace '\s+', ' ')
}
