<#PSScriptInfo

.DESCRIPTION Turns one worker object into a result row, and writes its per-computer folder

.VERSION 1.0.0

.GUID 8e41c6d3-27b5-4d90-a1f4-6c3b9d05e872

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Complete-EventLogInventoryComputer
function Complete-EventLogInventoryComputer {

    <#
    .SYNOPSIS
        Turns one worker object into a result row, and writes its per-computer folder.

    .DESCRIPTION
        Turns one worker object, or nothing plus the errors that explain why there is none, into
        a result row. When a worker object is present, it also writes the per-computer folder.
        The logs are written sorted by name, ordinal and without regard to case, whatever order
        the worker listed them in. The lists of the worker object (the logs, the accounts, the
        application packages and capabilities, the errors and the name lists) are read straight
        from the object's properties, never through Get-EventLogInventorySafeProperty, so an
        empty list stays an empty list and a one-element list stays a list.
        Called once per computer: a caller with several local aliases for the same computer calls
        this once for the first alias and copies the returned row for every later one, changing
        only ComputerName, so no two rows for one folder can ever disagree on Status, a count or
        Errors. Status is computed from the worker object's own counts and its own Errors list
        alone, before any host-side error (a write failure) is appended, so a problem the host
        has while writing the files never changes a Status the target-side collection already
        earned.

    .PARAMETER RequestedComputerName
        The name as the caller requested it, used for the result row and any error messages.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER RunFolder
        The run folder a new per-computer folder is created under. Its leaf name is also the
        RunId recorded in system.json.

    .PARAMETER WorkerObject
        The object Get-EventLogInventoryWorker's scriptblock returned, or $null when the target
        produced nothing.

    .PARAMETER ExtraErrors
        Errors already known before this call, folded into the row's Errors alongside anything
        found here. May be empty or $null.

    .PARAMETER OutputFormat
        Json, Csv or Both. Decides which file of the logs, accounts and appcontainers pairs is written.
        system.json and summary.json have no csv twin and are always written. Defaults to Json.

    .NOTES
        FUNCTION: Complete-EventLogInventoryComputer
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteEventLog.Result
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String]$RequestedComputerName,

        [Parameter(Mandatory = $true)]
        [String]$Transport,

        [Parameter(Mandatory = $true)]
        [String]$RunFolder,

        [AllowNull()]
        [PSObject]$WorkerObject,

        [AllowNull()]
        [AllowEmptyCollection()]
        [String[]]$ExtraErrors,

        [ValidateSet('Json', 'Csv', 'Both')]
        [String]$OutputFormat = 'Json'
    )

    $writeJson = $OutputFormat -ne 'Csv'
    $writeCsv = $OutputFormat -ne 'Json'

    $errors = @()
    # Every host-side message added to $errors is collapsed to one trimmed line where it is added: the list
    # goes to system.json as it stands, and the message of a failed write or a remote call can carry a line
    # break.
    if ($ExtraErrors) {
        $errors += @($ExtraErrors | ForEach-Object { ([String]$_).Trim() -replace '\s+', ' ' })
    }

    if ($null -eq $WorkerObject) {
        return ConvertTo-EventLogInventoryResultRow -ComputerName $RequestedComputerName -Status 'Failed' -Transport $Transport -Errors $errors
    }

    # Set before the try so the catch-all below always has a value to return, even when a later step here
    # throws: a computer that was reached still carries its ComputerId.
    $computerId = $null

    try {
        #region Read list reads one list property of the worker object
        # A list read through Get-EventLogInventorySafeProperty is enumerated on its way out, so an empty list
        # arrives as nothing and a list of one as the bare item. This reads the property itself and emits the
        # items, and the caller's @() turns them back into a list. A missing or null property emits nothing.
        $readList = {
            param($Object, [String]$Name)

            $listProperty = $Object.PSObject.Properties[$Name]
            if (($null -ne $listProperty) -and ($null -ne $listProperty.Value)) {
                $listProperty.Value
            }
        }
        #endregion

        # A malformed worker object can carry $null or empty-string entries in Errors, dropped here so a
        # summary or a results row never shows a blank line for one.
        $workerErrors = @(& $readList $WorkerObject 'Errors' | Where-Object { -not [String]::IsNullOrEmpty($_) })
        $errors += $workerErrors

        $computerId = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerId' -Default $null
        $logCount = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'LogCount' -Default $null
        $logReadFailedCount = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'LogReadFailedCount' -Default $null
        $sddlFailedCount = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'SddlFailedCount' -Default $null
        $accountCount = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'AccountCount' -Default $null
        $accountUnresolvedCount = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'AccountUnresolvedCount' -Default $null

        # Status is computed from the worker object's own counts and its own Errors list, never from anything
        # the host adds afterward. A $null count (a malformed or partial worker object) is not the same as a
        # verified 0, so Success also requires both counts to be present.
        if (($null -eq $logCount) -or ([Int]$logCount -eq 0)) {
            $status = 'Failed'
        }
        elseif (($null -ne $logReadFailedCount) -and ($null -ne $sddlFailedCount) -and ([Int]$logReadFailedCount -eq 0) -and ([Int]$sddlFailedCount -eq 0) -and ($workerErrors.Count -eq 0)) {
            $status = 'Success'
        }
        else {
            $status = 'Partial'
        }

        $reportedName = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerName' -Default $RequestedComputerName
        if ([String]::IsNullOrWhiteSpace($reportedName)) {
            $reportedName = $RequestedComputerName
        }
        $reportedNameUpper = $reportedName.ToUpperInvariant()

        $buildNumber = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'CurrentBuild' -Default $null
        if ([String]::IsNullOrWhiteSpace($buildNumber)) {
            $buildNumber = 'unknown'
        }

        $folderStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
        # The reported name comes from the target. A name carrying path separators, dots or wildcard
        # characters must not steer the folder outside the run folder or trip the provider, so anything
        # outside letters, digits, underscore and hyphen becomes an underscore. ASCII NetBIOS names are
        # unchanged. A name with other letters gets underscores and stays unique through the suffix rule.
        $safeReportedName = [Regex]::Replace($reportedNameUpper, '[^A-Za-z0-9_-]', '_')
        # The build number is a registry string read on the target, so it gets the same reduction. The stamp
        # is generated here and stays.
        $safeBuildNumber = [Regex]::Replace([String]$buildNumber, '[^A-Za-z0-9_-]', '_')
        $folderName = '{0}_{1}_{2}Z' -f $safeReportedName, $safeBuildNumber, $folderStamp
        $outputFolder = Resolve-EventLogInventoryUniqueFolder -Path (Join-Path $RunFolder $folderName)

        $logs = @(& $readList $WorkerObject 'Logs')
        $accounts = @(& $readList $WorkerObject 'Accounts')
        # A worker object without the list gives an empty list, as any missing list does.
        $appContainers = @(& $readList $WorkerObject 'AppContainers')

        #region Sort logs by name, ordinal and without regard to case
        # Each log travels with its name in a small wrapper, so the comparison reads a property that is known
        # to exist and never calls back into the worker object. A log without a name sorts first.
        $logWrappers = [System.Collections.Generic.List[Object]]::new()
        foreach ($log in $logs) {
            $logName = [String](Get-EventLogInventorySafeProperty -InputObject $log -Name 'LogName' -Default '')
            $wrapper = [PSCustomObject]@{
                Key = $logName
                Log = $log
            }
            $logWrappers.Add($wrapper)
        }
        $logWrappers.Sort([Comparison[Object]] { param($A, $B) [String]::Compare($A.Key, $B.Key, [System.StringComparison]::OrdinalIgnoreCase) })
        $sortedLogs = [System.Collections.Generic.List[Object]]::new()
        foreach ($wrapper in $logWrappers) {
            [Void]$sortedLogs.Add($wrapper.Log)
        }
        #endregion

        # The json file and the csv file hold the same rows: the columns in file order, a missing value null.
        $logRows = @(ConvertTo-EventLogInventoryLogCsvRow -Logs $sortedLogs.ToArray())

        if ($writeJson) {
            try {
                # -InputObject @($logRows), not a pipe, so an empty array still serialises to [] and a
                # one-element array still serialises to a one-element array, rather than collapsing to a bare
                # object.
                $logsJson = ConvertTo-Json -InputObject @($logRows) -Depth 4
                Write-EventLogInventoryTextFile -Path (Join-Path $outputFolder 'logs.json') -Content $logsJson
            }
            catch {
                $errors += ("write logs.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $logCsvColumns = @('LogName', 'LogType', 'IsClassicLog', 'IsEnabled', 'LogMode', 'LogIsolation', 'OwningProviderName', 'LogFilePath', 'LogFilePathExpanded', 'MaximumSizeInBytes', 'SecurityDescriptor', 'FileSize', 'RecordCount', 'OldestRecordNumber', 'IsLogFull', 'CreationUtc', 'LastWriteUtc', 'LastAccessUtc', 'OldestRecordId', 'OldestEventUtc', 'NewestRecordId', 'NewestEventUtc', 'CoveredSeconds', 'PolicyMaxSize', 'PolicyRetention', 'PolicyAutoBackupLogFiles', 'PolicyChannelAccess', 'PolicyFile', 'PolicyEnabled', 'ArchiveCount', 'ArchiveBytes', 'ArchiveOldestWriteUtc', 'ArchiveNewestWriteUtc', 'ReadError')
                Write-EventLogInventoryCsvFile -Row $logRows -Path (Join-Path $outputFolder 'logs.csv') -Column $logCsvColumns
            }
            catch {
                $errors += ("write logs.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeJson) {
            try {
                $accountsJson = ConvertTo-Json -InputObject @($accounts) -Depth 4
                Write-EventLogInventoryTextFile -Path (Join-Path $outputFolder 'accounts.json') -Content $accountsJson
            }
            catch {
                $errors += ("write accounts.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $accountCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'Error')
                $accountCsvRows = @($accounts | Select-Object -Property $accountCsvColumns)
                Write-EventLogInventoryCsvFile -Row $accountCsvRows -Path (Join-Path $outputFolder 'accounts.csv') -Column $accountCsvColumns
            }
            catch {
                $errors += ("write accounts.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeJson) {
            try {
                $appContainersJson = ConvertTo-Json -InputObject @($appContainers) -Depth 4
                Write-EventLogInventoryTextFile -Path (Join-Path $outputFolder 'appcontainers.json') -Content $appContainersJson
            }
            catch {
                $errors += ("write appcontainers.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $appContainerCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'ReferenceCount')
                $appContainerCsvRows = @($appContainers | Select-Object -Property $appContainerCsvColumns)
                Write-EventLogInventoryCsvFile -Row $appContainerCsvRows -Path (Join-Path $outputFolder 'appcontainers.csv') -Column $appContainerCsvColumns
            }
            catch {
                $errors += ("write appcontainers.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        try {
            #region Summary totals over the log rows
            $logCountByType = @{}
            $logsWithRecordsCount = 0
            $totalRecordCount = [Int64]0
            $totalFileSize = [Int64]0
            $archiveBytes = [Int64]0
            $oldestEventUtc = $null
            $newestEventUtc = $null
            foreach ($row in $logRows) {
                if ($null -ne $row.LogType) {
                    $typeName = [String]$row.LogType
                    if ($logCountByType.ContainsKey($typeName)) {
                        $logCountByType[$typeName] = $logCountByType[$typeName] + 1
                    }
                    else {
                        $logCountByType[$typeName] = 1
                    }
                }
                if ($null -ne $row.RecordCount) {
                    $totalRecordCount += [Int64]$row.RecordCount
                    if ([Int64]$row.RecordCount -gt 0) {
                        $logsWithRecordsCount++
                    }
                }
                if ($null -ne $row.FileSize) {
                    $totalFileSize += [Int64]$row.FileSize
                }
                if ($null -ne $row.ArchiveBytes) {
                    $archiveBytes += [Int64]$row.ArchiveBytes
                }
                # The times are fixed-width ISO strings in UTC, so an ordinal comparison orders them in time.
                if (-not [String]::IsNullOrEmpty($row.OldestEventUtc)) {
                    if (($null -eq $oldestEventUtc) -or ([String]::CompareOrdinal([String]$row.OldestEventUtc, $oldestEventUtc) -lt 0)) {
                        $oldestEventUtc = [String]$row.OldestEventUtc
                    }
                }
                if (-not [String]::IsNullOrEmpty($row.NewestEventUtc)) {
                    if (($null -eq $newestEventUtc) -or ([String]::CompareOrdinal([String]$row.NewestEventUtc, $newestEventUtc) -gt 0)) {
                        $newestEventUtc = [String]$row.NewestEventUtc
                    }
                }
            }

            $logCountByTypeSorted = [ordered]@{}
            $typeNames = [System.Collections.Generic.List[String]]::new()
            foreach ($typeKey in $logCountByType.Keys) {
                $typeNames.Add([String]$typeKey)
            }
            $typeNames.Sort([System.StringComparer]::Ordinal)
            foreach ($typeKey in $typeNames) {
                $logCountByTypeSorted[$typeKey] = $logCountByType[$typeKey]
            }
            #endregion

            $summaryObject = [PSCustomObject]@{
                LogCount                = $logCount
                EnabledLogCount         = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'EnabledLogCount' -Default $null
                LogCountByType          = $logCountByTypeSorted
                LogsWithRecordsCount    = $logsWithRecordsCount
                TotalRecordCount        = $totalRecordCount
                TotalFileSize           = $totalFileSize
                OldestEventUtc          = $oldestEventUtc
                NewestEventUtc          = $newestEventUtc
                LogReadFailedCount      = $logReadFailedCount
                LogReadFailedItems      = @(& $readList $WorkerObject 'LogReadFailedItems')
                SddlFailedCount         = $sddlFailedCount
                SddlFailedItems         = @(& $readList $WorkerObject 'SddlFailedItems')
                PolicyKeyPresent        = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'PolicyKeyPresent' -Default $null
                PolicyLogNames          = @(& $readList $WorkerObject 'PolicyLogNames')
                PolicyUnmatchedNames    = @(& $readList $WorkerObject 'PolicyUnmatchedNames')
                ArchiveCount            = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'ArchiveCount' -Default $null
                ArchiveBytes            = $archiveBytes
                LogsDurationMs          = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'LogsDurationMs' -Default $null
                RecordsDurationMs       = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'RecordsDurationMs' -Default $null
                PolicyDurationMs        = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'PolicyDurationMs' -Default $null
                ArchivesDurationMs      = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'ArchivesDurationMs' -Default $null
                AccountsDurationMs      = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'AccountsDurationMs' -Default $null
                AccountCount            = $accountCount
                AccountUnresolvedCount  = $accountUnresolvedCount
                AccountUnresolvedTokens = @($accounts | Where-Object { $_.Status -eq 'NotFound' } | Select-Object -ExpandProperty Token)
                AppContainerCount       = $appContainers.Count
            }
            $summaryJson = $summaryObject | ConvertTo-Json -Depth 6
            Write-EventLogInventoryTextFile -Path (Join-Path $outputFolder 'summary.json') -Content $summaryJson
        }
        catch {
            $errors += ("write summary.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            # Built as an explicit ordered list of names, not by enumerating
            # $WorkerObject.PSObject.Properties, so the key order of system.json is fixed regardless of
            # how a worker object happened to be built (a live worker return or a PSSerializer round trip).
            $systemObject = [ordered]@{}
            $identityPropertyOrder = @('ComputerName', 'DnsHostName', 'Domain', 'OSCaption', 'OSVersion', 'CurrentBuild', 'UBR',
                'DisplayVersion', 'EditionID', 'InstallationType', 'Culture', 'TimeZoneId', 'PSVersion', 'CollectedBy',
                'PartOfDomain', 'IsElevated', 'DomainRole', 'CollectedUtc', 'ComputerId', 'MachineGuid',
                'MachineSid', 'DomainSid', 'ComputerAccountSid', 'DomainNetbiosName')
            foreach ($name in $identityPropertyOrder) {
                $systemObject[$name] = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Collector'] = 'RemoteEventLog'
            $systemObject['CollectorVersion'] = $MyInvocation.MyCommand.Module.Version.ToString()
            $systemObject['RunId'] = Split-Path -Path $RunFolder -Leaf

            $modulePropertyOrder = @('LogCount', 'EnabledLogCount', 'LogReadFailedCount', 'SddlFailedCount', 'ArchiveCount',
                'AccountCount', 'AccountUnresolvedCount', 'AppContainerCount', 'PolicyKeyPresent', 'LogsDurationMs', 'RecordsDurationMs',
                'PolicyDurationMs', 'ArchivesDurationMs', 'AccountsDurationMs')
            foreach ($name in $modulePropertyOrder) {
                # AppContainerCount is the row count of the list read above, the same value as in
                # summary.json, so a worker object without the list gives 0 and not $null.
                if ($name -eq 'AppContainerCount') {
                    $systemObject[$name] = $appContainers.Count
                }
                else {
                    $systemObject[$name] = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
                }
            }

            $systemObject['Errors'] = @($errors)
            $systemObject['Transport'] = $Transport
            $systemObject['RequestedComputerName'] = $RequestedComputerName
            $systemObject['Status'] = $status

            $systemJson = [PSCustomObject]$systemObject | ConvertTo-Json -Depth 6
            Write-EventLogInventoryTextFile -Path (Join-Path $outputFolder 'system.json') -Content $systemJson
        }
        catch {
            $errors += ("write system.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        $isElevatedValue = Get-EventLogInventorySafeProperty -InputObject $WorkerObject -Name 'IsElevated' -Default $null
        if ($null -ne $isElevatedValue) {
            $isElevatedValue = [Bool]$isElevatedValue
        }

        return ConvertTo-EventLogInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status $status -Transport $Transport `
            -OutputFolder $outputFolder -IsElevated $isElevatedValue `
            -LogCount $logCount -LogReadFailedCount $logReadFailedCount -SddlFailedCount $sddlFailedCount `
            -AccountCount $accountCount -AccountUnresolvedCount $accountUnresolvedCount `
            -Errors $errors
    }
    catch {
        $errors += ("unexpected error processing ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        return ConvertTo-EventLogInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status 'Failed' -Transport $Transport -Errors $errors
    }
}
#endregion
