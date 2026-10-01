<#PSScriptInfo

.DESCRIPTION Returns a property value from an object, or a default when the object or the property is missing

.VERSION 1.2.0

.GUID 2301383c-26f1-41f1-95ce-26351c0aeb68

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Get-RsopInventorySafeProperty {

    <#
    .SYNOPSIS
        Returns a property value from an object, or a default when the object or the property is missing.

    .DESCRIPTION
        Safe under Set-StrictMode -Version Latest: returns Default when InputObject is nothing,
        or does not carry a property named Name, instead of throwing. Used everywhere a parsed
        RawJson object, a worker object or an error record, all of which vary in shape depending
        on what the target reported, needs to be read without a chain of null checks around every
        property access.

    .PARAMETER InputObject
        The object to read from. May be $null.

    .PARAMETER Name
        The property name to look for.

    .PARAMETER Default
        The value returned when InputObject is $null or carries no property named Name.

    .NOTES
        FUNCTION: Get-RsopInventorySafeProperty
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
