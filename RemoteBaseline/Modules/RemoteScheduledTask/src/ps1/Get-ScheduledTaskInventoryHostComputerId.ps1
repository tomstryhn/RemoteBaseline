<#PSScriptInfo

.DESCRIPTION Returns the collecting computer's own ComputerId, read the same way the worker reads a target's

.VERSION 1.3.0

.GUID 2acecfeb-f22f-479c-824f-404dcdb7e895

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function Get-ScheduledTaskInventoryHostComputerId {

    <#
    .SYNOPSIS
        Returns the collecting computer's own ComputerId, read the same way the worker reads a
        target's.

    .DESCRIPTION
        Reads Win32_ComputerSystemProduct.UUID through CIM, upper cases it, and gives $null when
        the class or the property is missing or the read throws. Used once per call to fill
        HostComputerId in run.json, so the collecting computer's own identity is recorded by the
        same rule the worker uses for every target.

    .NOTES
        FUNCTION: Get-ScheduledTaskInventoryHostComputerId
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String
    #>

    param()

    $computerId = $null
    try {
        $product = $null
        $product = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop -Verbose:$false
        if ($null -ne $product -and $null -ne $product.PSObject.Properties['UUID'] -and -not [string]::IsNullOrWhiteSpace([string]$product.UUID)) {
            $computerId = ([string]$product.UUID).Trim().ToUpperInvariant()
        }
    } catch {
        $computerId = $null
    }

    return $computerId
}
