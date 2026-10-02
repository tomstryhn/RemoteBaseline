<#PSScriptInfo

.DESCRIPTION Tells whether the session is Windows PowerShell (Desktop edition), which limits a path to 260 characters

.VERSION 1.1.0

.GUID 8d2c6f41-3b97-4e5a-a0d8-6c19e4b7f352

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Test-RemoteBaselineDesktopEdition {

    <#
    .SYNOPSIS
        Tells whether the session is Windows PowerShell (Desktop edition), which limits a path to 260 characters.

    .DESCRIPTION
        True on the Desktop edition (Windows PowerShell 5.1), false on Core (PowerShell 7). A named
        function and not an inline $PSVersionTable read, so a test can mock the answer and prove
        the path budget check on both engines.

    .NOTES
        FUNCTION: Test-RemoteBaselineDesktopEdition
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Boolean
    #>

    param()

    return ($PSVersionTable.PSEdition -ne 'Core')
}
