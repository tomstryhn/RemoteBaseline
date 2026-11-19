<#PSScriptInfo

.DESCRIPTION Returns the table of the seven bundled collectors in run order, optionally filtered by type

.VERSION 1.4.0

.GUID 14157d57-bf1a-4c74-92d4-ec3ac0646e28

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-RemoteBaselineCollectorInfo
function Get-RemoteBaselineCollectorInfo {

    <#
    .SYNOPSIS
        Returns the table of the seven bundled collectors in run order, optionally filtered by type.

    .DESCRIPTION
        One place holds the mapping from a Type value to the collector module and its public
        function: System, RSOP, ScheduledTask, SecEdit, Service, Firewall, EventLog, which is
        also the fixed run order. System comes first, so it is the collector that reads the SID
        reference of the host, and EventLog comes last. Each entry carries Type, Module, Function and
        Subfolder (the module name, which names the folder under the run folder and under every
        host folder). With Type, only the matching entries come back, still in run order, so
        duplicates and case differences in the request collapse. An empty or missing Type returns
        all seven. A value that is not a Type is ignored here. The caller's ValidateSet is what
        rejects it.

    .PARAMETER Type
        The requested types. Case-insensitive. May be empty or $null for all seven.

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
        [String[]]$Type
    )

    $all = @(
        [PSCustomObject]@{ Type = 'System'; Module = 'RemoteSystem'; Function = 'Get-SystemInventory'; Subfolder = 'RemoteSystem' }
        [PSCustomObject]@{ Type = 'RSOP'; Module = 'RemoteRSOP'; Function = 'Get-RsopInventory'; Subfolder = 'RemoteRSOP' }
        [PSCustomObject]@{ Type = 'ScheduledTask'; Module = 'RemoteScheduledTask'; Function = 'Get-ScheduledTaskInventory'; Subfolder = 'RemoteScheduledTask' }
        [PSCustomObject]@{ Type = 'SecEdit'; Module = 'RemoteSecEdit'; Function = 'Get-SecEditExport'; Subfolder = 'RemoteSecEdit' }
        [PSCustomObject]@{ Type = 'Service'; Module = 'RemoteService'; Function = 'Get-ServiceInventory'; Subfolder = 'RemoteService' }
        [PSCustomObject]@{ Type = 'Firewall'; Module = 'RemoteFirewall'; Function = 'Get-FirewallInventory'; Subfolder = 'RemoteFirewall' }
        [PSCustomObject]@{ Type = 'EventLog'; Module = 'RemoteEventLog'; Function = 'Get-EventLogInventory'; Subfolder = 'RemoteEventLog' }
    )

    $requested = @($Type | Where-Object { -not [String]::IsNullOrWhiteSpace($_) })
    if ($requested.Count -eq 0) {
        return $all
    }

    # -contains compares case-insensitively, which is the rule for Type. The table order, not the request
    # order, is the result order.
    return @($all | Where-Object { $requested -contains $_.Type })
}
#endregion
