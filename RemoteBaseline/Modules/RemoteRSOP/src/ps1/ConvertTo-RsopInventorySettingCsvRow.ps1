<#PSScriptInfo

.DESCRIPTION Turns one setting object into its csv-shaped equivalent

.VERSION 1.3.0

.GUID 071c416e-4b8b-4915-924f-dec198f24931

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertTo-RsopInventorySettingCsvRow {

    <#
    .SYNOPSIS
        Turns one setting object into its csv-shaped equivalent.

    .DESCRIPTION
        settings.json keeps every typed value (an array stays an array, a bool stays a bool).
        settings.csv needs one cell per column, so an array Value is joined with a pipe and
        everything else is passed through unchanged: ConvertTo-Csv renders $null as an empty
        cell and a boolean as True or False on its own.

    .PARAMETER SettingRow
        One object returned by ConvertTo-RsopInventorySettingRow.

    .NOTES
        FUNCTION: ConvertTo-RsopInventorySettingCsvRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SettingRow
    )

    $value = $SettingRow.Value
    if ($value -is [array]) {
        $valueText = ($value -join '|')
    } else {
        $valueText = $value
    }

    return [pscustomobject]@{
        Namespace  = $SettingRow.Namespace
        Class      = $SettingRow.Class
        GpoId      = $SettingRow.GpoId
        GpoName    = $SettingRow.GpoName
        Precedence = $SettingRow.Precedence
        SomId      = $SettingRow.SomId
        Key        = $SettingRow.Key
        Name       = $SettingRow.Name
        ValueType  = $SettingRow.ValueType
        Value      = $valueText
        Deleted    = $SettingRow.Deleted
        Status     = $SettingRow.Status
        ErrorCode  = $SettingRow.ErrorCode
        InstanceId = $SettingRow.InstanceId
        Detail     = $SettingRow.Detail
    }
}
