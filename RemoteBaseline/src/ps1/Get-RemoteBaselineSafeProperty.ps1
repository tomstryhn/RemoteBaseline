<#PSScriptInfo

.DESCRIPTION Returns a property value from an object, or a default when the object or the property is missing

.VERSION 1.0.0

.GUID 27d79293-ae15-4623-843f-94743b46526f

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Get-RemoteBaselineSafeProperty {

    <#
    .SYNOPSIS
        Returns a property value from an object, or a default when the object or the property is missing.

    .DESCRIPTION
        Safe under Set-StrictMode -Version Latest: returns Default when InputObject is nothing,
        or does not carry a property named Name, instead of throwing. Used wherever a collector
        row or a system.json object, which vary in shape, is read without a chain of null checks
        around every property access. The code is the same as the collectors' helper.

    .PARAMETER InputObject
        The object to read from. May be $null.

    .PARAMETER Name
        The property name to look for.

    .PARAMETER Default
        The value returned when InputObject is $null or carries no property named Name.

    .NOTES
        FUNCTION: Get-RemoteBaselineSafeProperty
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
