<#PSScriptInfo

.DESCRIPTION Builds the logs.csv rows for one computer

.VERSION 1.0.0

.GUID 0b7d3e91-4c18-4a6f-8e2d-95f1a3c7d604

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region ConvertTo-EventLogInventoryLogCsvRow
function ConvertTo-EventLogInventoryLogCsvRow {

    <#
    .SYNOPSIS
        Builds the logs.csv rows for one computer.

    .DESCRIPTION
        Produces one flat row per log, in the exact column order logs.csv requires. Every column
        is a plain read of the log property of the same name, and a property the log object does
        not carry stays null. The rows keep the order of the Logs list, so a caller that wants
        them sorted sorts the list first.

    .PARAMETER Logs
        The Logs array from the worker object. May be empty.

    .NOTES
        FUNCTION: ConvertTo-EventLogInventoryLogCsvRow
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
        [PSObject[]]$Logs
    )

    $columns = @('LogName', 'LogType', 'IsClassicLog', 'IsEnabled', 'LogMode', 'LogIsolation', 'OwningProviderName', 'LogFilePath', 'LogFilePathExpanded', 'MaximumSizeInBytes', 'SecurityDescriptor', 'FileSize', 'RecordCount', 'OldestRecordNumber', 'IsLogFull', 'CreationUtc', 'LastWriteUtc', 'LastAccessUtc', 'OldestRecordId', 'OldestEventUtc', 'NewestRecordId', 'NewestEventUtc', 'CoveredSeconds', 'PolicyMaxSize', 'PolicyRetention', 'PolicyAutoBackupLogFiles', 'PolicyChannelAccess', 'PolicyFile', 'PolicyEnabled', 'ArchiveCount', 'ArchiveBytes', 'ArchiveOldestWriteUtc', 'ArchiveNewestWriteUtc', 'ReadError')

    # A list and a direct read of each property, because a helper call per cell and an array grown per row
    # cost most of the host time for a computer with over a thousand logs.
    $rows = [System.Collections.Generic.List[Object]]::new()
    foreach ($log in @($Logs)) {
        $logProperties = $null
        if ($null -ne $log) {
            $logProperties = $log.PSObject.Properties
        }
        $row = [ordered]@{}
        foreach ($column in $columns) {
            $value = $null
            if ($null -ne $logProperties) {
                $property = $logProperties[$column]
                if ($null -ne $property) {
                    $value = $property.Value
                }
            }
            $row[$column] = $value
        }
        [Void]$rows.Add([PSCustomObject]$row)
    }

    return $rows.ToArray()
}
#endregion
