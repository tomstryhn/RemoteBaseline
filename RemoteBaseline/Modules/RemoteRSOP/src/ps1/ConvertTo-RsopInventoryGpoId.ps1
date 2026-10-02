<#PSScriptInfo

.DESCRIPTION Turns a raw GPO id into the GpoId the output files carry

.VERSION 1.3.0

.GUID c310c44e-29e3-4c14-be52-a3a9284d99b4

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertTo-RsopInventoryGpoId {

    <#
    .SYNOPSIS
        Turns a raw GPO id into the GpoId the output files carry.

    .DESCRIPTION
        The one place that knows how a raw GPOID or RSOP_GPO id becomes a GpoId, shared by the
        setting, gpo and link rows: a value of the form cn={guid},... or CN={GUID},... becomes the
        {GUID} upper case, LocalGPO is kept as is (compared case-insensitively), any other value is
        returned unchanged, and an empty or null value becomes null.

    .PARAMETER Value
        The raw id as the instance carries it. May be null or empty.

    .NOTES
        FUNCTION: ConvertTo-RsopInventoryGpoId
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String
    #>

    param(
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    if (-not $Value) { return $null }
    if ($Value -ieq 'LocalGPO') { return 'LocalGPO' }
    if ($Value -match '(?i)^cn=(\{[0-9a-f-]{36}\})') { return $matches[1].ToUpperInvariant() }
    # The comma keeps a raw value that is an array an array: a plain return would unroll a one-element array to its element.
    return , $Value
}
