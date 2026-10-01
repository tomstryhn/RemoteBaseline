<#PSScriptInfo

.DESCRIPTION Builds one RemoteScheduledTask.Result row

.VERSION 1.3.0

.GUID 2c70669b-4e66-438e-9ec6-b7131e68cc64

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function ConvertTo-ScheduledTaskInventoryResultRow {

    <#
    .SYNOPSIS
        Builds one RemoteScheduledTask.Result row.

    .DESCRIPTION
        Every optional property defaults to the "not reached" shape, so a caller only needs to
        override what it actually knows. Error is derived from Errors here, as the first entry,
        rather than being supplied separately, so the two can never disagree about which message
        came first.

    .PARAMETER ComputerName
        The name as requested by the caller.

    .PARAMETER ComputerId
        The computer's own identity from the worker object, or $null when the target was never
        reached.

    .PARAMETER Status
        Success, Partial, or Failed.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER OutputFolder
        The per-computer folder, or $null when the target was never reached.

    .PARAMETER IsElevated
        Elevation as reported by the target, or $null when unknown.

    .PARAMETER TaskCount
        Tasks Get-ScheduledTask returned, hidden ones included, or $null.

    .PARAMETER XmlFailedCount
        Tasks whose definition export failed or did not parse, or $null.

    .PARAMETER SddlFailedCount
        Tasks whose descriptor the COM interface did not return, or $null.

    .PARAMETER BinaryCount
        Distinct executables resolved from Exec actions, or $null.

    .PARAMETER BinaryMissingCount
        Of those, not found on disk or unreadable, or $null.

    .PARAMETER AccountCount
        Distinct principal tokens, or $null.

    .PARAMETER AccountUnresolvedCount
        Of those, NotFound after the lookup, or $null.

    .PARAMETER Errors
        Every error message seen for this computer, target and host side. May be empty.

    .NOTES
        FUNCTION: ConvertTo-ScheduledTaskInventoryResultRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteScheduledTask.Result
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [AllowNull()]
        $ComputerId,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Transport,

        [AllowNull()]
        [string]$OutputFolder,

        [AllowNull()]
        $IsElevated,

        [AllowNull()]
        $TaskCount,

        [AllowNull()]
        $XmlFailedCount,

        [AllowNull()]
        $SddlFailedCount,

        [AllowNull()]
        $BinaryCount,

        [AllowNull()]
        $BinaryMissingCount,

        [AllowNull()]
        $AccountCount,

        [AllowNull()]
        $AccountUnresolvedCount,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Errors
    )

    # Host-side messages such as a remote connection error run over several lines. One line per message keeps results.csv and the Error column readable, and Error is the first of these collapsed entries, so Error and Errors agree.
    $errorList = @($Errors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' })

    return [pscustomobject]@{
        PSTypeName             = 'RemoteScheduledTask.Result'
        ComputerName           = $ComputerName
        ComputerId             = $ComputerId
        Status                 = $Status
        Transport              = $Transport
        OutputFolder           = $OutputFolder
        IsElevated             = $IsElevated
        TaskCount              = $TaskCount
        XmlFailedCount         = $XmlFailedCount
        SddlFailedCount        = $SddlFailedCount
        BinaryCount            = $BinaryCount
        BinaryMissingCount     = $BinaryMissingCount
        AccountCount           = $AccountCount
        AccountUnresolvedCount = $AccountUnresolvedCount
        Error                  = $(if ($errorList.Count -gt 0) { $errorList[0] } else { '' })
        ErrorCount             = $errorList.Count
        Errors                 = [string[]]$errorList
    }
}
