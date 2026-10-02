<#PSScriptInfo

.DESCRIPTION Returns the collecting computer's own ComputerId, or null on failure

.VERSION 1.3.0

.GUID 24a20a25-e122-4f89-bc2d-5c0d56cd037b

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Get-RsopInventoryHostComputerId {

    <#
    .SYNOPSIS
        Returns the collecting computer's own ComputerId, or null on failure.

    .DESCRIPTION
        Reads Win32_ComputerSystemProduct.UUID on the collecting computer, the same way the
        worker scriptblock reads it for a target: through CIM, the value trimmed and upper-cased.
        Returns null when the class or the property is missing or the read throws, so a bad read
        here never stops run.json from being written. Used once, for run.json's HostComputerId.

    .NOTES
        FUNCTION: Get-RsopInventoryHostComputerId
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
        Write-Verbose "Get-RsopInventoryHostComputerId: $($_.Exception.Message)"
        $computerId = $null
    }

    return $computerId
}
