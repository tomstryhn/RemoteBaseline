<#PSScriptInfo

.DESCRIPTION Builds one RemoteEventLog.Result row

.VERSION 1.0.0

.GUID 5f0c8a52-6a2e-4f0b-9c58-3d1b7e6a41c9

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region ConvertTo-EventLogInventoryResultRow
function ConvertTo-EventLogInventoryResultRow {

    <#
    .SYNOPSIS
        Builds one RemoteEventLog.Result row.

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

    .PARAMETER LogCount
        Number of event logs the target listed, or $null.

    .PARAMETER LogReadFailedCount
        Logs whose configuration, information or first and last record could not be read, or
        $null.

    .PARAMETER SddlFailedCount
        Logs whose security descriptor did not parse, or $null.

    .PARAMETER AccountCount
        Distinct security identifiers named in the security descriptors of the logs, or $null.

    .PARAMETER AccountUnresolvedCount
        Of those, without a name after the lookup, or $null.

    .PARAMETER Errors
        Every error message seen for this computer, target and host side. May be empty.
        ErrorCount is derived from this list's Count, so the two can never disagree.

    .NOTES
        FUNCTION: ConvertTo-EventLogInventoryResultRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteEventLog.Result
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
        $LogCount,

        [AllowNull()]
        $LogReadFailedCount,

        [AllowNull()]
        $SddlFailedCount,

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

    return [PSCustomObject]@{
        PSTypeName             = 'RemoteEventLog.Result'
        ComputerName           = $ComputerName
        ComputerId             = $ComputerId
        Status                 = $Status
        Transport              = $Transport
        OutputFolder           = $OutputFolder
        IsElevated             = $IsElevated
        LogCount               = $LogCount
        LogReadFailedCount     = $LogReadFailedCount
        SddlFailedCount        = $SddlFailedCount
        AccountCount           = $AccountCount
        AccountUnresolvedCount = $AccountUnresolvedCount
        Error                  = $(if ($errorList.Count -gt 0) { $errorList[0] } else { '' })
        ErrorCount             = $errorList.Count
        Errors                 = [String[]]$errorList
    }
}
#endregion
