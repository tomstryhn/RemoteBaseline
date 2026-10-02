<#PSScriptInfo

.DESCRIPTION Reads the identity of the collecting computer and run for run.json

.VERSION 1.1.0

.GUID d3ac2ec6-2bff-4d39-ba6d-6698954a0a26

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Get-RemoteBaselineHostIdentity {

    <#
    .SYNOPSIS
        Reads the identity of the collecting computer and run for run.json.

    .DESCRIPTION
        Returns HostComputer, HostComputerId, HostUser, PSVersion and StartUtc. HostComputerId is
        the same read as the collectors' host computer id helper: Win32_ComputerSystemProduct.UUID
        through CIM, upper case, null when the class or the property is missing or the read
        throws. StartUtc is the moment of this call as an ISO 8601 UTC string, which is the start
        of the run because the call is made right after the run folder exists. Never throws.

    .NOTES
        FUNCTION: Get-RemoteBaselineHostIdentity
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
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

    return [pscustomobject]@{
        HostComputer   = $env:COMPUTERNAME
        HostComputerId = $computerId
        HostUser       = "$env:USERDOMAIN\$env:USERNAME"
        PSVersion      = $PSVersionTable.PSVersion.ToString()
        StartUtc       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
}
