<#PSScriptInfo

.DESCRIPTION Cleans a list of computer names

.VERSION 1.0.0

.GUID bb6ab143-4c08-4aa5-a128-c75baa6842ee

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Resolve-SystemInventoryComputerList
function Resolve-SystemInventoryComputerList {

    <#
    .SYNOPSIS
        Cleans a list of computer names.

    .DESCRIPTION
        Removes duplicates case-insensitively, keeps first-seen order, and drops blank entries.
        Runs once, on the names collected from -ComputerName across the pipeline, before
        Get-SystemInventory splits them into local and remote targets.

    .PARAMETER ComputerName
        The raw list of names to clean.

    .NOTES
        FUNCTION: Resolve-SystemInventoryComputerList
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String[]
    #>

    param(
        [String[]]$ComputerName
    )

    $result = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($ComputerName)) {
        if ([String]::IsNullOrWhiteSpace($name)) {
            continue
        }
        $trimmed = $name.Trim()
        if ($seen.Add($trimmed)) {
            $result += $trimmed
        }
    }
    return $result
}
#endregion
