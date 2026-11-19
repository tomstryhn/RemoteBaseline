<#PSScriptInfo

.DESCRIPTION Runs the worker in-process on the local computer

.VERSION 1.0.0

.GUID 8b3fc07c-a7a7-4728-8287-45d64e004aca

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Invoke-EventLogInventoryLocal
function Invoke-EventLogInventoryLocal {

    <#
    .SYNOPSIS
        Runs the worker in-process on the local computer.

    .DESCRIPTION
        Kept as its own function, separate from the worker scriptblock, so tests can mock the
        local call without touching the real event log classes. Its only parameter is -SkipSidReference, handed
        to the worker as a real bool, and it has no logic of its own beyond the call, which is
        deliberate: every local alias in the same Get-EventLogInventory call shares this one run
        instead of each alias triggering its own.

    .PARAMETER SkipSidReference
        Leaves the SID reference unread: the worker returns MachineSid, DomainSid,
        ComputerAccountSid and DomainNetbiosName as null.

    .NOTES
        FUNCTION: Invoke-EventLogInventoryLocal
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Switch]$SkipSidReference
    )

    $worker = Get-EventLogInventoryWorker
    return & $worker -SkipSidReference ([Bool]$SkipSidReference)
}
#endregion
