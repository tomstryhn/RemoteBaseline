<#PSScriptInfo

.DESCRIPTION Builds the services.csv rows for one computer, with the Binary columns looked up by ExecutablePath

.VERSION 1.3.0

.GUID c65e9da4-b8c9-4dc0-9b4e-eeb188190f6d

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function ConvertTo-ServiceInventoryServiceCsvRow {

    <#
    .SYNOPSIS
        Builds the services.csv rows for one computer, with the Binary columns looked up by
        ExecutablePath.

    .DESCRIPTION
        Produces one flat row per service, in the exact column order services.csv requires. The
        Binary* columns are a lookup, not an interpretation: for each service row, the binary
        object whose Path equals the service's ExecutablePath (case-insensitive) supplies them,
        and they are empty when no binary matches. This is what lets an operator open one file in
        Excel and see each service with its account and its binary's publisher side by side.

    .PARAMETER Services
        The Services array from the worker object. May be empty.

    .PARAMETER Binaries
        The Binaries array from the worker object. May be empty.

    .NOTES
        FUNCTION: ConvertTo-ServiceInventoryServiceCsvRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [psobject[]]$Services,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [psobject[]]$Binaries
    )

    $binaryMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($bin in @($Binaries)) {
        $binPath = Get-ServiceInventorySafeProperty -InputObject $bin -Name 'Path' -Default $null
        if ($binPath) { $binaryMap[$binPath] = $bin }
    }

    # The row's columns in file order. The Binary* columns come from the matched binary, through this map of column to binary property; every other column is a plain read of the service property of the same name.
    $binaryColumnProperty = @{
        BinaryExists          = 'Exists'
        BinaryCompanyName     = 'CompanyName'
        BinaryProductName     = 'ProductName'
        BinaryFileVersion     = 'FileVersion'
        BinarySignatureStatus = 'SignatureStatus'
        BinarySignerSubject   = 'SignerSubject'
    }
    $columns = @('Name', 'DisplayName', 'State', 'StartMode', 'DelayedAutoStart', 'StartName', 'StartNameSid', 'ServiceType', 'PathName', 'ExecutablePath', 'ProcessId', 'DesktopInteract', 'ErrorControl', 'Sddl', 'SddlExitCode', 'BinaryExists', 'BinaryCompanyName', 'BinaryProductName', 'BinaryFileVersion', 'BinarySignatureStatus', 'BinarySignerSubject', 'Description')

    $rows = @()
    foreach ($svc in @($Services)) {
        $execPath = Get-ServiceInventorySafeProperty -InputObject $svc -Name 'ExecutablePath' -Default $null

        $matchedBinary = $null
        if ($execPath -and $binaryMap.ContainsKey($execPath)) { $matchedBinary = $binaryMap[$execPath] }

        $row = [ordered]@{}
        foreach ($column in $columns) {
            if ($binaryColumnProperty.ContainsKey($column)) {
                $row[$column] = $(if ($matchedBinary) { Get-ServiceInventorySafeProperty -InputObject $matchedBinary -Name $binaryColumnProperty[$column] -Default $null } else { '' })
            } else {
                $row[$column] = Get-ServiceInventorySafeProperty -InputObject $svc -Name $column -Default $null
            }
        }
        $rows += [pscustomobject]$row
    }

    return @($rows)
}
