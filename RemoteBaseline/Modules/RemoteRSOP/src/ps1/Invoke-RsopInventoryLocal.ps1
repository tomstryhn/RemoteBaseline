<#PSScriptInfo

.DESCRIPTION Runs the worker in-process on the local computer

.VERSION 1.2.0

.GUID 19210035-8d07-411b-b9a5-d93435fbb721

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Invoke-RsopInventoryLocal {

    <#
    .SYNOPSIS
        Runs the worker in-process on the local computer.

    .DESCRIPTION
        Kept as its own function, separate from the worker scriptblock, so tests can mock the
        local call without touching the real RSOP WMI namespaces. Takes no parameters and has no
        logic of its own beyond the call, which is deliberate: every local alias in the same
        Get-RsopInventory call shares this one run instead of each alias triggering its own.

    .NOTES
        FUNCTION: Invoke-RsopInventoryLocal
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param()

    return & (Get-RsopInventoryWorker)
}
