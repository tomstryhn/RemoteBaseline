<#PSScriptInfo

.DESCRIPTION Cleans a list of computer names

.VERSION 1.1.0

.GUID 0ab1749e-bf93-4641-8dca-da0336024ab7

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Resolve-RemoteBaselineComputerList {

    <#
    .SYNOPSIS
        Cleans a list of computer names.

    .DESCRIPTION
        Removes duplicates case-insensitively, keeps first-seen order, and drops blank entries.
        Runs once, on the names collected from -ComputerName across the pipeline, before
        Get-RemoteBaseline hands the list to the collectors. The code is the same as the
        collectors' list helper, so the umbrella and every collector agree on which names a call
        asked for.

    .PARAMETER ComputerName
        The raw list of names to clean.

    .NOTES
        FUNCTION: Resolve-RemoteBaselineComputerList
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String[]
    #>

    param(
        [string[]]$ComputerName
    )

    $result = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($ComputerName)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $trimmed = $name.Trim()
        if ($seen.Add($trimmed)) { $result += $trimmed }
    }
    return $result
}
