<#PSScriptInfo

.DESCRIPTION Decodes a raw RSOP registry value into its typed PowerShell form

.VERSION 1.2.0

.GUID 44137286-581b-4137-840d-db70a6d5a617

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertFrom-RsopInventoryRegistryValue {

    <#
    .SYNOPSIS
        Decodes a raw RSOP registry value into its typed PowerShell form.

    .DESCRIPTION
        RSOP_RegistryPolicySetting and RSOP_RegistryValue carry a registry value type and the
        value's raw bytes. This function turns that pair into the value a registry editor would
        show: a string for REG_SZ and REG_EXPAND_SZ, a string array for REG_MULTI_SZ, a number for
        REG_DWORD and REG_QWORD, and lower-case hex for REG_BINARY and anything unrecognized. Pure
        function, no side effects, safe to call directly against fixture bytes.

    .PARAMETER ValueType
        The registry value type as an integer (the raw valueType or Type property).

    .PARAMETER Bytes
        The raw bytes as an integer array, the shape a decoded RawJson byte array arrives in. May
        be null or empty.

    .NOTES
        FUNCTION: ConvertFrom-RsopInventoryRegistryValue
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Object
    #>

    param(
        [Parameter(Mandatory = $true)]
        [int]$ValueType,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [int[]]$Bytes
    )

    #region REG_NONE and empty input
    if ($ValueType -eq 0 -or $null -eq $Bytes -or $Bytes.Count -eq 0) {
        return $null
    }
    #endregion

    # Element-wise narrowing, every RSOP byte value is 0-255 so this never overflows
    $byteArray = [byte[]]$Bytes

    #region REG_SZ and REG_EXPAND_SZ
    if ($ValueType -eq 1 -or $ValueType -eq 2) {
        $text = [System.Text.Encoding]::Unicode.GetString($byteArray)
        return $text.TrimEnd([char]0)
    }
    #endregion

    #region REG_DWORD
    if ($ValueType -eq 4 -and $byteArray.Length -ge 4) {
        return [long]([System.BitConverter]::ToUInt32($byteArray, 0))
    }
    #endregion

    #region REG_MULTI_SZ
    if ($ValueType -eq 7) {
        $text = [System.Text.Encoding]::Unicode.GetString($byteArray)
        $parts = $text -split [char]0
        $strings = @()
        foreach ($part in $parts) {
            if ($part.Length -gt 0) { $strings += $part }
        }
        # Plain return, the caller wraps with @() so a zero- or one-element result stays an array there
        return $strings
    }
    #endregion

    #region REG_QWORD
    if ($ValueType -eq 11 -and $byteArray.Length -ge 8) {
        $unsigned = [System.BitConverter]::ToUInt64($byteArray, 0)
        if ([decimal]$unsigned -gt [decimal][long]::MaxValue) {
            return [decimal]$unsigned
        }
        return [long]$unsigned
    }
    #endregion

    #region REG_BINARY and every other value type
    $hex = New-Object System.Text.StringBuilder
    foreach ($b in $byteArray) { [void]$hex.Append($b.ToString('x2')) }
    return $hex.ToString()
    #endregion
}
