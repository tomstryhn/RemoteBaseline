<#PSScriptInfo

.DESCRIPTION Tests whether a computer name identifies the local computer

.VERSION 1.3.0

.GUID dbe8fcbc-7c58-4b9c-9622-8e7791bf4f20

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function Test-ServiceInventoryLocalName {

    <#
    .SYNOPSIS
        Tests whether a computer name identifies the local computer.

    .DESCRIPTION
        True for '.', 'localhost', '127.0.0.1', '::1', the local NetBIOS name, and the local
        FQDN, all compared case-insensitively. Used by Get-ServiceInventory to split a requested
        target list into names that run in-process and names that go through Invoke-Command.

    .PARAMETER Name
        The computer name to test.

    .NOTES
        FUNCTION: Test-ServiceInventoryLocalName
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Boolean
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $localAliases = @('.', 'localhost', '127.0.0.1', '::1')
    foreach ($alias in $localAliases) {
        if ($Name -ieq $alias) { return $true }
    }
    if ($Name -ieq $env:COMPUTERNAME) { return $true }

    $fqdn = $null
    try {
        $ipProps = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        $fqdn = $ipProps.HostName
        if ($ipProps.DomainName) { $fqdn = $fqdn + '.' + $ipProps.DomainName }
    } catch {
        $fqdn = $null
    }
    if ($fqdn -and ($Name -ieq $fqdn)) { return $true }

    return $false
}
