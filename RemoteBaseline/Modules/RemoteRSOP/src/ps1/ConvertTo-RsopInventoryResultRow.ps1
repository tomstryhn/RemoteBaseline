<#PSScriptInfo

.DESCRIPTION Builds one RemoteRSOP.Result row

.VERSION 1.3.0

.GUID 9e3bc644-c4ae-4cf1-9928-a7c60e00ad7b

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertTo-RsopInventoryResultRow {

    <#
    .SYNOPSIS
        Builds one RemoteRSOP.Result row.

    .DESCRIPTION
        Every optional property defaults to the "not reached" shape, so a caller only needs to
        override what it actually knows. Error is derived from Errors here, as the first entry,
        rather than being supplied separately, so the two can never disagree about which message
        came first.

    .PARAMETER ComputerName
        The name as requested by the caller.

    .PARAMETER ComputerId
        The computer's own identity (Win32_ComputerSystemProduct.UUID, upper case), or $null when
        the target was never reached.

    .PARAMETER Status
        Success, Partial, or Failed.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER OutputFolder
        The per-computer folder, or $null when the target was never reached.

    .PARAMETER IsElevated
        Elevation as reported by the target, or $null when unknown.

    .PARAMETER ComputerClassCount
        Classes exported from root\RSOP\Computer, or $null when the target was never reached.

    .PARAMETER ComputerInstanceCount
        Instances exported from root\RSOP\Computer, or $null.

    .PARAMETER UserNamespaceCount
        S_1_ child namespaces found under root\RSOP\User, or $null.

    .PARAMETER UserInstanceCount
        Instances exported from all user namespaces, or $null.

    .PARAMETER SettingCount
        Rows in settings.csv, or $null.

    .PARAMETER GpoCount
        RSOP_GPO instances in the computer namespace, or $null.

    .PARAMETER ExtensionErrorCount
        RSOP_ExtensionStatus instances, all namespaces, whose error is not 0, or $null.

    .PARAMETER ClassErrorCount
        Classes whose enumeration threw, all namespaces, or $null.

    .PARAMETER AccountCount
        Number of distinct accounts referenced across the collected classes, or $null.

    .PARAMETER AccountUnresolvedCount
        Number of those accounts that did not resolve, or $null.

    .PARAMETER Errors
        Every error message seen for this computer, target and host side. May be empty.
        ErrorCount, the count of Errors, is derived here, the same way Error is.

    .NOTES
        FUNCTION: ConvertTo-RsopInventoryResultRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteRSOP.Result
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
        $ComputerClassCount,

        [AllowNull()]
        $ComputerInstanceCount,

        [AllowNull()]
        $UserNamespaceCount,

        [AllowNull()]
        $UserInstanceCount,

        [AllowNull()]
        $SettingCount,

        [AllowNull()]
        $GpoCount,

        [AllowNull()]
        $ExtensionErrorCount,

        [AllowNull()]
        $ClassErrorCount,

        [AllowNull()]
        $AccountCount,

        [AllowNull()]
        $AccountUnresolvedCount,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Errors
    )

    # Every entry is collapsed to one line here, so a multi-line host-side message (a remote connection error, for example) can never put a line break into Error, Errors or a csv cell.
    $errorList = @(@($Errors) | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' })

    return [pscustomobject]@{
        PSTypeName             = 'RemoteRSOP.Result'
        ComputerName           = $ComputerName
        ComputerId             = $ComputerId
        Status                 = $Status
        Transport              = $Transport
        OutputFolder           = $OutputFolder
        IsElevated             = $IsElevated
        ComputerClassCount     = $ComputerClassCount
        ComputerInstanceCount  = $ComputerInstanceCount
        UserNamespaceCount     = $UserNamespaceCount
        UserInstanceCount      = $UserInstanceCount
        SettingCount           = $SettingCount
        GpoCount               = $GpoCount
        ExtensionErrorCount    = $ExtensionErrorCount
        ClassErrorCount        = $ClassErrorCount
        AccountCount           = $AccountCount
        AccountUnresolvedCount = $AccountUnresolvedCount
        Error                  = $(if ($errorList.Count -gt 0) { $errorList[0] } else { '' })
        ErrorCount             = $errorList.Count
        Errors                 = [string[]]$errorList
    }
}
