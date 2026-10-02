<#PSScriptInfo

.DESCRIPTION Runs the worker in-process on the local computer

.VERSION 1.4.1

.GUID c0ed8c10-fe58-4237-9bc8-3d309605431e

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function Invoke-ScheduledTaskInventoryLocal {

    <#
    .SYNOPSIS
        Runs the worker in-process on the local computer.

    .DESCRIPTION
        Kept as its own function, separate from the worker scriptblock, so tests can mock the
        local call without touching the real ScheduledTasks module or the real Task Scheduler.
        Takes one switch, -SkipSidReference, passed to the worker by name as a real bool, and has
        no logic of its own beyond the call, which is deliberate: every local alias in the same
        Get-ScheduledTaskInventory call shares this one run instead of each alias triggering its
        own.

    .PARAMETER SkipSidReference
        Passed to the worker as a bool. With the switch the worker leaves MachineSid, DomainSid,
        ComputerAccountSid and DomainNetbiosName null and does not read them.

    .NOTES
        FUNCTION: Invoke-ScheduledTaskInventoryLocal
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [switch]$SkipSidReference
    )

    $worker = Get-ScheduledTaskInventoryWorker
    return & $worker -SkipSidReference ([bool]$SkipSidReference)
}
