<#PSScriptInfo

.DESCRIPTION Cleans a list of computer names

.VERSION 1.2.0

.GUID 64377a0a-777a-4ccb-a044-7338bb4fcff3

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Resolve-RsopInventoryComputerList {

    <#
    .SYNOPSIS
        Cleans a list of computer names.

    .DESCRIPTION
        Removes duplicates case-insensitively, keeps first-seen order, and drops blank entries.
        Runs once, on the names collected from -ComputerName across the pipeline, before
        Get-RsopInventory splits them into local and remote targets.

    .PARAMETER ComputerName
        The raw list of names to clean.

    .NOTES
        FUNCTION: Resolve-RsopInventoryComputerList
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
