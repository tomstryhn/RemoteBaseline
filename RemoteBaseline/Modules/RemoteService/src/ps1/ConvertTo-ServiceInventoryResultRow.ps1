<#PSScriptInfo

.DESCRIPTION Builds one RemoteService.Result row

.VERSION 1.3.0

.GUID d27111d0-2676-4af6-b34e-84af76944e08

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function ConvertTo-ServiceInventoryResultRow {

    <#
    .SYNOPSIS
        Builds one RemoteService.Result row.

    .DESCRIPTION
        Every optional property defaults to the "not reached" shape, so a caller only needs to
        override what it actually knows. Error is derived from Errors here, as the first entry,
        rather than being supplied separately, so the two can never disagree about which message
        came first.

    .PARAMETER ComputerName
        The name as requested by the caller.

    .PARAMETER ComputerId
        The computer's identity from the worker object (section 5), or $null when the target was
        never reached.

    .PARAMETER Status
        Success, Partial, or Failed.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER OutputFolder
        The per-computer folder, or $null when the target was never reached.

    .PARAMETER IsElevated
        Elevation as reported by the target, or $null when unknown.

    .PARAMETER ServiceCount
        Number of Win32_Service instances returned, or $null.

    .PARAMETER SddlFailedCount
        Services whose sc sdshow did not return a descriptor, or $null.

    .PARAMETER BinaryCount
        Distinct executables parsed from PathName, or $null.

    .PARAMETER BinaryMissingCount
        Of those, not found on disk or unreadable, or $null.

    .PARAMETER AccountCount
        Distinct non-empty StartName values, or $null.

    .PARAMETER AccountUnresolvedCount
        Of those, without a SID after the lookup, or $null.

    .PARAMETER Errors
        Every error message seen for this computer, target and host side. May be empty.
        ErrorCount is derived from this list's Count, so the two can never disagree.

    .NOTES
        FUNCTION: ConvertTo-ServiceInventoryResultRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteService.Result
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
        $ServiceCount,

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

    # Every entry is collapsed to one line here, so a host-side message that arrives with line breaks (a WinRM connection error is several lines) reaches Error, Errors, run.json and results.csv as one line, the same as a worker message does.
    $errorList = @($Errors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' })

    return [pscustomobject]@{
        PSTypeName              = 'RemoteService.Result'
        ComputerName            = $ComputerName
        ComputerId              = $ComputerId
        Status                  = $Status
        Transport               = $Transport
        OutputFolder            = $OutputFolder
        IsElevated              = $IsElevated
        ServiceCount            = $ServiceCount
        SddlFailedCount         = $SddlFailedCount
        BinaryCount             = $BinaryCount
        BinaryMissingCount      = $BinaryMissingCount
        AccountCount            = $AccountCount
        AccountUnresolvedCount  = $AccountUnresolvedCount
        Error                   = $(if ($errorList.Count -gt 0) { $errorList[0] } else { '' })
        ErrorCount              = $errorList.Count
        Errors                  = [string[]]$errorList
    }
}
