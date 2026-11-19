<#PSScriptInfo

.DESCRIPTION Runs the worker in-process on the local computer

.VERSION 1.0.0

.GUID a4eeb57b-2b21-4431-8d94-f18033750a39

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Invoke-SystemInventoryLocal
function Invoke-SystemInventoryLocal {

    <#
    .SYNOPSIS
        Runs the worker in-process on the local computer.

    .DESCRIPTION
        Kept as its own function, separate from the worker scriptblock, so tests can mock the
        local call without reading the real computer. Its parameters are -SkipSidReference and
        -SkipDismFeatures, both handed to the worker as a real bool, and it has no logic of its
        own beyond the call, which is deliberate: every local alias in the same
        Get-SystemInventory call shares this one run instead of each alias triggering its own.

    .PARAMETER SkipSidReference
        Leaves the SID reference unread: the worker returns MachineSid, DomainSid,
        ComputerAccountSid and DomainNetbiosName as null.

    .PARAMETER SkipDismFeatures
        Leaves the DISM feature list unread: the worker records the DismFeatures read as Skipped
        and returns a null DismState on every feature row.

    .NOTES
        FUNCTION: Invoke-SystemInventoryLocal
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Switch]$SkipSidReference,

        [Switch]$SkipDismFeatures
    )

    $worker = Get-SystemInventoryWorker
    return & $worker -SkipSidReference ([Bool]$SkipSidReference) -SkipDismFeatures ([Bool]$SkipDismFeatures)
}
#endregion
