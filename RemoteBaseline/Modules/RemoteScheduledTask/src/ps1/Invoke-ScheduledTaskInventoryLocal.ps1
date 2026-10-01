<#PSScriptInfo

.DESCRIPTION Runs the worker in-process on the local computer

.VERSION 1.3.0

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
        Takes no parameters and has no logic of its own beyond the call, which is deliberate:
        every local alias in the same Get-ScheduledTaskInventory call shares this one run instead
        of each alias triggering its own.

    .NOTES
        FUNCTION: Invoke-ScheduledTaskInventoryLocal
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param()

    $worker = Get-ScheduledTaskInventoryWorker
    return & $worker
}
