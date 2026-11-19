<#PSScriptInfo

.DESCRIPTION Builds one RemoteSystem.Result row

.VERSION 1.0.0

.GUID 0f6c3a52-7b1e-4d98-a3c4-5e2d81b97a10

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region ConvertTo-SystemInventoryResultRow
function ConvertTo-SystemInventoryResultRow {

    <#
    .SYNOPSIS
        Builds one RemoteSystem.Result row.

    .DESCRIPTION
        Every optional property defaults to the "not reached" shape, so a caller only needs to
        override what it actually knows. Error is derived from Errors here, as the first entry,
        rather than being supplied separately, so the two can never disagree about which message
        came first.

    .PARAMETER ComputerName
        The name as requested by the caller.

    .PARAMETER ComputerId
        The computer's identity from the worker object, or $null when the target was
        never reached.

    .PARAMETER Status
        Success, Partial, or Failed.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER OutputFolder
        The per-computer folder, or $null when the target was never reached.

    .PARAMETER IsElevated
        Elevation as reported by the target, or $null when unknown.

    .PARAMETER ReadCount
        Number of reads that were answered, with or without data, or $null.

    .PARAMETER ReadFailedCount
        Number of reads that failed, or $null.

    .PARAMETER HotfixCount
        Number of installed updates listed, or $null.

    .PARAMETER AccountCount
        Distinct non-empty InstalledBy values, or $null.

    .PARAMETER AccountUnresolvedCount
        Of those, without a SID after the lookup, or $null.

    .PARAMETER Errors
        Every error message seen for this computer, target and host side. May be empty.
        ErrorCount is derived from this list's Count, so the two can never disagree.

    .NOTES
        FUNCTION: ConvertTo-SystemInventoryResultRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteSystem.Result
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String]$ComputerName,

        [AllowNull()]
        $ComputerId,

        [Parameter(Mandatory = $true)]
        [String]$Status,

        [Parameter(Mandatory = $true)]
        [String]$Transport,

        [AllowNull()]
        [String]$OutputFolder,

        [AllowNull()]
        $IsElevated,

        [AllowNull()]
        $ReadCount,

        [AllowNull()]
        $ReadFailedCount,

        [AllowNull()]
        $HotfixCount,

        [AllowNull()]
        $AccountCount,

        [AllowNull()]
        $AccountUnresolvedCount,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [String[]]$Errors
    )

    # Every entry is collapsed to one line here, so a host-side message that arrives with line breaks (a WinRM
    # connection error is several lines) reaches Error, Errors, run.json and results.csv as one line, the same
    # as a worker message does.
    $errorList = @($Errors | ForEach-Object { ([String]$_).Trim() -replace '\s+', ' ' })
    $firstError = ''
    if ($errorList.Count -gt 0) {
        $firstError = $errorList[0]
    }

    return [PSCustomObject]@{
        PSTypeName             = 'RemoteSystem.Result'
        ComputerName           = $ComputerName
        ComputerId             = $ComputerId
        Status                 = $Status
        Transport              = $Transport
        OutputFolder           = $OutputFolder
        IsElevated             = $IsElevated
        ReadCount              = $ReadCount
        ReadFailedCount        = $ReadFailedCount
        HotfixCount            = $HotfixCount
        AccountCount           = $AccountCount
        AccountUnresolvedCount = $AccountUnresolvedCount
        Error                  = $firstError
        ErrorCount             = $errorList.Count
        Errors                 = [String[]]$errorList
    }
}
#endregion
