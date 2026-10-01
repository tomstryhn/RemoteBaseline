<#PSScriptInfo

.DESCRIPTION Turns one worker object into a result row, and writes its per-computer folder

.VERSION 1.3.0

.GUID 362850eb-3c37-4ded-9c5e-eb0f8b97921a

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function Complete-ScheduledTaskInventoryComputer {

    <#
    .SYNOPSIS
        Turns one worker object into a result row, and writes its per-computer folder.

    .DESCRIPTION
        Turns one worker object, or nothing plus the errors that explain why there is none, into
        a result row. When a worker object is present, it also writes the per-computer folder:
        tasks.json, tasks.csv, accounts.json, accounts.csv, binaries.json, binaries.csv,
        summary.json and system.json. Called once per computer: a caller with several local
        aliases for the same computer calls this once for the first alias and copies the returned
        row for every later one, changing only ComputerName, so no two rows for one folder can
        ever disagree on Status, a count or Errors. Status is computed from the worker object's
        own counts and its own Errors list alone, before any host-side error (a summary or json
        write failure) is appended, so a problem the host has while writing the remaining files
        never changes a Status the target-side collection already earned. A count the worker
        object does not carry is not the same as a verified zero, so it is never turned into one:
        Success cannot be reached when the worker's own XmlFailedCount is $null.

    .PARAMETER RequestedComputerName
        The name as the caller requested it, used for the result row and any error messages.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER RunFolder
        The run folder a new per-computer folder is created under.

    .PARAMETER WorkerObject
        The object Get-ScheduledTaskInventoryWorker's scriptblock returned, or $null when the
        target produced nothing.

    .PARAMETER ExtraErrors
        Errors already known before this call, folded into the row's Errors alongside anything
        found here. May be empty or $null.

    .NOTES
        FUNCTION: Complete-ScheduledTaskInventoryComputer
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteScheduledTask.Result
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedComputerName,

        [Parameter(Mandatory = $true)]
        [string]$Transport,

        [Parameter(Mandatory = $true)]
        [string]$RunFolder,

        [AllowNull()]
        [psobject]$WorkerObject,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ExtraErrors
    )

    $taskCsvColumns = @('TaskPath', 'TaskName', 'FolderPath', 'State', 'Enabled', 'Hidden', 'Author', 'Date', 'Source', 'TaskVersion', 'PrincipalId', 'PrincipalToken', 'PrincipalSid', 'PrincipalName', 'LogonType', 'RunLevel', 'LastRunTime', 'LastTaskResultHex', 'NextRunTime', 'NumberOfMissedRuns', 'ActionCount', 'ExecActionCount', 'ComHandlerActionCount', 'Command', 'Arguments', 'WorkingDirectory', 'ExecutablePath', 'ClassId', 'TriggerCount', 'TriggerTypes', 'ExecutionTimeLimit', 'MultipleInstancesPolicy', 'StartWhenAvailable', 'RunOnlyIfIdle', 'RunOnlyIfNetworkAvailable', 'Sddl', 'RegistrationSecurityDescriptor', 'BinaryExists', 'BinaryCompanyName', 'BinaryProductName', 'BinaryFileVersion', 'BinarySignatureStatus', 'BinarySignerSubject', 'Description')
    $accountCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'Error')
    $binaryCsvColumns = @('Path', 'Exists', 'Length', 'LastWriteTimeUtc', 'FileVersion', 'ProductVersion', 'CompanyName', 'ProductName', 'FileDescription', 'OriginalFilename', 'InternalName', 'Sha256', 'SignatureStatus', 'SignatureStatusMessage', 'SignerSubject', 'SignerThumbprint', 'Error')

    $errors = @()
    # Every host-side message added to $errors is collapsed to one trimmed line where it is added: the list goes to system.json as it stands, and the message of a failed write or a remote call can carry a line break.
    if ($ExtraErrors) { $errors += @($ExtraErrors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' }) }

    if ($null -eq $WorkerObject) {
        return ConvertTo-ScheduledTaskInventoryResultRow -ComputerName $RequestedComputerName -Status 'Failed' -Transport $Transport -Errors $errors
    }

    # Set before the try so the catch-all below always has a value to return, even when a later step here throws: a computer that was reached still carries its ComputerId.
    $computerId = $null

    try {
        # A malformed worker object can carry $null or empty-string entries in Errors, dropped here so a summary or a results row never shows a blank line for one.
        $workerErrors = @(Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'Errors' -Default @() | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $errors += $workerErrors

        $computerId = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerId' -Default $null
        $taskCount = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'TaskCount' -Default $null
        $workerXmlFailedCount = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'XmlFailedCount' -Default $null
        $sddlFailedCount = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'SddlFailedCount' -Default $null
        $binaryCount = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'BinaryCount' -Default $null
        $binaryMissingCount = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'BinaryMissingCount' -Default $null
        $accountCount = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'AccountCount' -Default $null
        $accountUnresolvedCount = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'AccountUnresolvedCount' -Default $null

        $tasks = @(Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'Tasks' -Default @())
        $accounts = @(Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'Accounts' -Default @())
        $binaries = @(Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'Binaries' -Default @())

        $reportedName = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerName' -Default $RequestedComputerName
        if ([string]::IsNullOrWhiteSpace($reportedName)) { $reportedName = $RequestedComputerName }
        $reportedNameUpper = $reportedName.ToUpperInvariant()

        $buildNumber = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'CurrentBuild' -Default $null
        if ([string]::IsNullOrWhiteSpace($buildNumber)) { $buildNumber = 'unknown' }

        $folderStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
        # The reported name comes from the target. A name carrying path separators, dots or wildcard characters must not steer the folder outside the run folder or trip the provider, so anything outside letters, digits, underscore and hyphen becomes an underscore. ASCII NetBIOS names are unchanged; a name with other letters gets underscores and stays unique through the suffix rule.
        $safeReportedName = [regex]::Replace($reportedNameUpper, '[^A-Za-z0-9_-]', '_')
        # The build number comes from the target as well (a registry string), so it gets the same reduction. The stamp is generated on this host and stays as it is.
        $safeBuildNumber = [regex]::Replace([string]$buildNumber, '[^A-Za-z0-9_-]', '_')
        $folderName = '{0}_{1}_{2}Z' -f $safeReportedName, $safeBuildNumber, $folderStamp
        $outputFolder = Resolve-ScheduledTaskInventoryUniqueFolder -Path (Join-Path $RunFolder $folderName)

        # Status is computed from the worker object's own counts and its own Errors list alone, never from anything the host has trouble with while writing the per-computer files. A $null count (a malformed or partial worker object) is not the same as a verified 0, so Success also requires every count to be present.
        if (($null -eq $taskCount) -or ([int]$taskCount -eq 0)) {
            $status = 'Failed'
        } elseif (($null -ne $workerXmlFailedCount) -and ($null -ne $sddlFailedCount) -and ($null -ne $binaryMissingCount) -and ([int]$workerXmlFailedCount -eq 0) -and ([int]$sddlFailedCount -eq 0) -and ([int]$binaryMissingCount -eq 0) -and ($workerErrors.Count -eq 0)) {
            $status = 'Success'
        } else {
            $status = 'Partial'
        }

        try {
            # -InputObject @($tasks), not a pipe, so an empty array still serialises to [] and a one-element array still serialises to a one-element array, rather than collapsing to a bare object.
            $tasksJson = ConvertTo-Json -InputObject @($tasks) -Depth 5
            Write-ScheduledTaskInventoryTextFile -Path (Join-Path $outputFolder 'tasks.json') -Content $tasksJson
        } catch {
            $errors += ("write tasks.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $taskCsvRows = @(ConvertTo-ScheduledTaskInventoryTaskCsvRow -Tasks $tasks -Binaries $binaries)
            Write-ScheduledTaskInventoryCsvFile -Row $taskCsvRows -Path (Join-Path $outputFolder 'tasks.csv') -Column $taskCsvColumns
        } catch {
            $errors += ("write tasks.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $accountsJson = ConvertTo-Json -InputObject @($accounts) -Depth 4
            Write-ScheduledTaskInventoryTextFile -Path (Join-Path $outputFolder 'accounts.json') -Content $accountsJson
        } catch {
            $errors += ("write accounts.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $accountCsvRows = @($accounts | Select-Object -Property $accountCsvColumns)
            Write-ScheduledTaskInventoryCsvFile -Row $accountCsvRows -Path (Join-Path $outputFolder 'accounts.csv') -Column $accountCsvColumns
        } catch {
            $errors += ("write accounts.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $binariesJson = ConvertTo-Json -InputObject @($binaries) -Depth 4
            Write-ScheduledTaskInventoryTextFile -Path (Join-Path $outputFolder 'binaries.json') -Content $binariesJson
        } catch {
            $errors += ("write binaries.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $binaryCsvRows = @($binaries | Select-Object -Property $binaryCsvColumns)
            Write-ScheduledTaskInventoryCsvFile -Row $binaryCsvRows -Path (Join-Path $outputFolder 'binaries.csv') -Column $binaryCsvColumns
        } catch {
            $errors += ("write binaries.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $xmlFailedPaths = @($tasks | Where-Object {
                (Get-ScheduledTaskInventorySafeProperty -InputObject $_ -Name 'XmlError' -Default '') -or
                (Get-ScheduledTaskInventorySafeProperty -InputObject $_ -Name 'XmlParseError' -Default '')
            } | Select-Object -ExpandProperty TaskPath)
            $sddlFailedItems = @($tasks | Where-Object { Get-ScheduledTaskInventorySafeProperty -InputObject $_ -Name 'SddlError' -Default '' } | Select-Object -ExpandProperty TaskPath)
            $accountUnresolvedTokens = @($accounts | Where-Object { $_.Status -eq 'NotFound' } | Select-Object -ExpandProperty Token)
            $binaryMissingPaths = @($binaries | Where-Object { -not $_.Exists -or $_.Error } | Select-Object -ExpandProperty Path)

            $summaryObject = [pscustomobject]@{
                TaskCount               = $taskCount
                HiddenCount             = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'HiddenCount' -Default $null
                XmlFailedCount          = $workerXmlFailedCount
                XmlFailedItems          = $xmlFailedPaths
                SddlFailedCount         = $sddlFailedCount
                SddlFailedItems         = $sddlFailedItems
                TasksDurationMs         = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'TasksDurationMs' -Default $null
                SddlDurationMs          = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'SddlDurationMs' -Default $null
                AccountsDurationMs      = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'AccountsDurationMs' -Default $null
                BinariesDurationMs      = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'BinariesDurationMs' -Default $null
                AccountCount            = $accountCount
                AccountUnresolvedCount  = $accountUnresolvedCount
                AccountUnresolvedTokens = $accountUnresolvedTokens
                BinaryCount             = $binaryCount
                BinaryMissingCount      = $binaryMissingCount
                BinaryMissingPaths      = $binaryMissingPaths
            }
            $summaryJson = $summaryObject | ConvertTo-Json -Depth 6
            Write-ScheduledTaskInventoryTextFile -Path (Join-Path $outputFolder 'summary.json') -Content $summaryJson
        } catch {
            $errors += ("write summary.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            # Built as an explicit ordered list of names, not by enumerating $WorkerObject.PSObject.Properties, so the key order in system.json always matches the output convention regardless of how a worker object happened to be built (a live worker return or a PSSerializer round trip).
            $systemObject = [ordered]@{}
            $identityPropertyOrder = @('ComputerName', 'DnsHostName', 'Domain', 'OSCaption', 'OSVersion', 'CurrentBuild', 'UBR',
                'DisplayVersion', 'EditionID', 'InstallationType', 'Culture', 'TimeZoneId', 'PSVersion', 'CollectedBy',
                'PartOfDomain', 'IsElevated', 'DomainRole', 'CollectedUtc', 'ComputerId', 'MachineGuid')
            foreach ($name in $identityPropertyOrder) {
                $systemObject[$name] = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Collector'] = 'RemoteScheduledTask'
            $systemObject['CollectorVersion'] = $MyInvocation.MyCommand.Module.Version.ToString()
            $systemObject['RunId'] = Split-Path -Path $RunFolder -Leaf

            $modulePropertyOrder = @('TaskCount', 'XmlFailedCount', 'SddlFailedCount', 'BinaryCount', 'BinaryMissingCount',
                'AccountCount', 'AccountUnresolvedCount', 'HiddenCount', 'TasksDurationMs', 'SddlDurationMs', 'AccountsDurationMs', 'BinariesDurationMs')
            foreach ($name in $modulePropertyOrder) {
                $systemObject[$name] = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Errors'] = @($errors)
            $systemObject['Transport'] = $Transport
            $systemObject['RequestedComputerName'] = $RequestedComputerName
            $systemObject['Status'] = $status

            $systemJson = [pscustomobject]$systemObject | ConvertTo-Json -Depth 6
            Write-ScheduledTaskInventoryTextFile -Path (Join-Path $outputFolder 'system.json') -Content $systemJson
        } catch {
            $errors += ("write system.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        $isElevatedValue = Get-ScheduledTaskInventorySafeProperty -InputObject $WorkerObject -Name 'IsElevated' -Default $null
        if ($null -ne $isElevatedValue) { $isElevatedValue = [bool]$isElevatedValue }

        return ConvertTo-ScheduledTaskInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status $status -Transport $Transport `
            -OutputFolder $outputFolder -IsElevated $isElevatedValue `
            -TaskCount $taskCount -XmlFailedCount $workerXmlFailedCount -SddlFailedCount $sddlFailedCount `
            -BinaryCount $binaryCount -BinaryMissingCount $binaryMissingCount `
            -AccountCount $accountCount -AccountUnresolvedCount $accountUnresolvedCount `
            -Errors $errors
    } catch {
        $errors += ("unexpected error processing ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        return ConvertTo-ScheduledTaskInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status 'Failed' -Transport $Transport -Errors $errors
    }
}
