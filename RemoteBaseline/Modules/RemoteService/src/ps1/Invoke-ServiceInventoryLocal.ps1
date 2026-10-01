<#PSScriptInfo

.DESCRIPTION Runs the worker in-process on the local computer

.VERSION 1.3.0

.GUID 2f37672d-801c-4793-a3d7-74b18f57ff20

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function Invoke-ServiceInventoryLocal {

    <#
    .SYNOPSIS
        Runs the worker in-process on the local computer.

    .DESCRIPTION
        Kept as its own function, separate from the worker scriptblock, so tests can mock the
        local call without touching the real sc.exe. Takes no parameters and has no
        logic of its own beyond the call, which is deliberate: every local alias in the same
        Get-ServiceInventory call shares this one run instead of each alias triggering its own.

    .NOTES
        FUNCTION: Invoke-ServiceInventoryLocal
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param()

    $worker = Get-ServiceInventoryWorker
    return & $worker
}
