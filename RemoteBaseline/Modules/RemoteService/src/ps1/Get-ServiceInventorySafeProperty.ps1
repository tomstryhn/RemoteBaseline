<#PSScriptInfo

.DESCRIPTION Returns a property value from an object, or a default when the object or the property is missing

.VERSION 1.3.0

.GUID 1aa6c174-2c2a-4742-8848-df206cb6b7df

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function Get-ServiceInventorySafeProperty {

    <#
    .SYNOPSIS
        Returns a property value from an object, or a default when the object or the property is missing.

    .DESCRIPTION
        Safe under Set-StrictMode -Version Latest: returns Default when InputObject is nothing,
        or does not carry a property named Name, instead of throwing. Used everywhere a worker
        object, a CIM instance or an error record, all of which vary in shape depending on how
        they were built, needs to be read without a chain of null checks around every property
        access.

    .PARAMETER InputObject
        The object to read from. May be $null.

    .PARAMETER Name
        The property name to look for.

    .PARAMETER Default
        The value returned when InputObject is $null or carries no property named Name.

    .NOTES
        FUNCTION: Get-ServiceInventorySafeProperty
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Object
    #>

    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}
