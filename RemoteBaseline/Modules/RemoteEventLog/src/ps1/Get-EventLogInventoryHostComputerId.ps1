<#PSScriptInfo

.DESCRIPTION Reads the collecting computer's own ComputerId for run.json

.VERSION 1.0.0

.GUID 1dfc04fe-0d6a-4d9c-89c0-4ffff0302e06

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-EventLogInventoryHostComputerId
function Get-EventLogInventoryHostComputerId {

    <#
    .SYNOPSIS
        Reads the collecting computer's own ComputerId for run.json.

    .DESCRIPTION
        Reads Win32_ComputerSystemProduct.UUID on the collecting computer, the same way the
        worker reads ComputerId for a target: through CIM, upper case, null when the class or the
        property is missing or the read throws. Runs on the host, so unlike the worker it may use
        module helpers.

    .NOTES
        FUNCTION: Get-EventLogInventoryHostComputerId
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
        if ($null -ne $product -and $null -ne $product.PSObject.Properties['UUID'] -and -not [String]::IsNullOrWhiteSpace([String]$product.UUID)) {
            $computerId = ([String]$product.UUID).Trim().ToUpperInvariant()
        }
    }
    catch {
        $computerId = $null
    }

    return $computerId
}
#endregion
