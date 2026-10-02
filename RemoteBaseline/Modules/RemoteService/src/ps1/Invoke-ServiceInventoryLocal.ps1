<#PSScriptInfo

.DESCRIPTION Runs the worker in-process on the local computer

.VERSION 1.4.0

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
        local call without touching the real sc.exe. Its only parameter is -SkipSidReference, handed
        to the worker as a real bool, and it has no logic of its own beyond the call, which is
        deliberate: every local alias in the same Get-ServiceInventory call shares this one run
        instead of each alias triggering its own.

    .PARAMETER SkipSidReference
        Leaves the SID reference unread: the worker returns MachineSid, DomainSid,
        ComputerAccountSid and DomainNetbiosName as null.

    .NOTES
        FUNCTION: Invoke-ServiceInventoryLocal
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

    $worker = Get-ServiceInventoryWorker
    return & $worker -SkipSidReference ([bool]$SkipSidReference)
}
