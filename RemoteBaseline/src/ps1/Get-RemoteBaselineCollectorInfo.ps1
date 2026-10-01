<#PSScriptInfo

.DESCRIPTION Returns the table of the five bundled collectors in run order, optionally filtered by type

.VERSION 1.0.0

.GUID 14157d57-bf1a-4c74-92d4-ec3ac0646e28

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Get-RemoteBaselineCollectorInfo {

    <#
    .SYNOPSIS
        Returns the table of the five bundled collectors in run order, optionally filtered by type.

    .DESCRIPTION
        One place holds the mapping from a Type value to the collector module and its public
        function: Firewall, RSOP, ScheduledTask, SecEdit, Service, which is also the fixed run
        order (alphabetical by type name). Each entry carries Type, Module, Function and
        Subfolder (the module name, which names the folder under the run folder and under every
        host folder). With Type, only the matching entries come back, still in run order, so
        duplicates and case differences in the request collapse. An empty or missing Type returns
        all five. A value that is not a Type is ignored here; the caller's ValidateSet is what
        rejects it.

    .PARAMETER Type
        The requested types. Case-insensitive. May be empty or $null for all five.

    .NOTES
        FUNCTION: Get-RemoteBaselineCollectorInfo
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Type
    )

    $all = @(
        [pscustomobject]@{ Type = 'Firewall'; Module = 'RemoteFirewall'; Function = 'Get-FirewallInventory'; Subfolder = 'RemoteFirewall' }
        [pscustomobject]@{ Type = 'RSOP'; Module = 'RemoteRSOP'; Function = 'Get-RsopInventory'; Subfolder = 'RemoteRSOP' }
        [pscustomobject]@{ Type = 'ScheduledTask'; Module = 'RemoteScheduledTask'; Function = 'Get-ScheduledTaskInventory'; Subfolder = 'RemoteScheduledTask' }
        [pscustomobject]@{ Type = 'SecEdit'; Module = 'RemoteSecEdit'; Function = 'Get-SecEditExport'; Subfolder = 'RemoteSecEdit' }
        [pscustomobject]@{ Type = 'Service'; Module = 'RemoteService'; Function = 'Get-ServiceInventory'; Subfolder = 'RemoteService' }
    )

    $requested = @($Type | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requested.Count -eq 0) { return $all }

    # -contains compares case-insensitively, which is the rule for Type; the table order, not the request order, is the result order.
    return @($all | Where-Object { $requested -contains $_.Type })
}
