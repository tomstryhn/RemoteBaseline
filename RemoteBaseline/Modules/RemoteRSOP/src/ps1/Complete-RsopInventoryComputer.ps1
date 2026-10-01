<#PSScriptInfo

.DESCRIPTION Turns one worker object into a result row, and writes its per-computer folder

.VERSION 1.2.0

.GUID 49815716-fc2e-405c-a6d8-14811bfd653b

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Complete-RsopInventoryComputer {

    <#
    .SYNOPSIS
        Turns one worker object into a result row, and writes its per-computer folder.

    .DESCRIPTION
        Turns one worker object, or nothing plus the errors that explain why there is none, into
        a result row. When a worker object is present, RawJson is parsed once with
        ConvertFrom-Json and every nested list read back from it is wrapped with @(), because a
        single-element array can arrive as a bare object on either engine. The parsed namespaces
        are then walked once to build the settings table, the gpo, link and extension rows, the
        session list and the per-class instance counts. Called once per computer: a caller with
        several local aliases for the same computer calls this once for the first alias and
        copies the returned row for every later one, changing only ComputerName, so no two rows
        for one folder can ever disagree on Status, a count or Errors.

        Status is Failed when no worker object came back or the worker's ComputerClassCount is
        null or 0 (the target's computer namespace was never read, for example an access-denied
        caller), Success when the worker's ClassErrorCount is 0 and its Errors list is empty, and
        Partial otherwise. ExtensionErrorCount never gates Status: it describes the target's own
        Group Policy health, not whether the collector reached the target.

    .PARAMETER RequestedComputerName
        The name as the caller requested it, used for the result row and any error messages.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER RunFolder
        The run folder a new per-computer folder is created under.

    .PARAMETER WorkerObject
        The object Get-RsopInventoryWorker's scriptblock returned, or $null when the target
        produced nothing.

    .PARAMETER ExtraErrors
        Errors already known before this call, folded into the row's Errors alongside anything
        found here. May be empty or $null.

    .NOTES
        FUNCTION: Complete-RsopInventoryComputer
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteRSOP.Result
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

    $errors = @()
    # Every host-side message added to $errors is collapsed to one trimmed line where it is added: the list goes to system.json as it stands, and the message of a failed write or a remote call can carry a line break.
    if ($ExtraErrors) { $errors += @($ExtraErrors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' }) }

    if ($null -eq $WorkerObject) {
        return ConvertTo-RsopInventoryResultRow -ComputerName $RequestedComputerName -Status 'Failed' -Transport $Transport -Errors $errors
    }

    # Set before the try so the catch-all below always has a value to return, even when the very first read inside the try throws.
    $computerIdValue = $null

    try {
        #region worker errors and the module's own counts, all read straight off the worker object
        # A malformed worker object can carry $null or empty-string entries in Errors, dropped here so a summary or a results row never shows a blank line for one.
        $workerErrors = @(Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'Errors' -Default @() | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $errors += $workerErrors

        $computerIdValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerId' -Default $null

        $computerClassCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerClassCount' -Default $null
        $computerInstanceCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerInstanceCount' -Default $null
        $userNamespaceCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'UserNamespaceCount' -Default $null
        $userInstanceCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'UserInstanceCount' -Default $null
        $gpoCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'GpoCount' -Default $null
        $extensionErrorCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'ExtensionErrorCount' -Default $null
        $classErrorCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'ClassErrorCount' -Default $null
        $accountCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'AccountCount' -Default $null
        $accountUnresolvedCountValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'AccountUnresolvedCount' -Default $null
        #endregion

        #region Status, design section 4
        if (($null -eq $computerClassCountValue) -or ($computerClassCountValue -eq 0)) {
            $status = 'Failed'
        } elseif (($classErrorCountValue -eq 0) -and ($workerErrors.Count -eq 0)) {
            $status = 'Success'
        } else {
            $status = 'Partial'
        }
        #endregion

        #region parse RawJson once, design section 6.2
        $rawJsonText = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'RawJson' -Default $null
        $parsedRaw = $null
        if ($rawJsonText) {
            try {
                $parsedRaw = $rawJsonText | ConvertFrom-Json
            } catch {
                $errors += ("parse RawJson on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }
        $namespaces = @(Get-RsopInventorySafeProperty -InputObject $parsedRaw -Name 'Namespaces' -Default @())
        #endregion

        #region walk every namespace once: settings, gpos, links, extensions, sessions, class counts and a normalized copy for raw.json
        $settingRows = @()
        $gpoRows = @()
        $linkRows = @()
        $extensionRows = @()
        $sessionRows = @()
        $classCounts = [ordered]@{}
        $classErrorItems = @()
        $userNamespaceNames = @()
        $normalizedNamespaces = @()

        foreach ($ns in $namespaces) {
            $nsName = [string](Get-RsopInventorySafeProperty -InputObject $ns -Name 'Namespace' -Default '')
            if ($nsName -ne 'Computer') { $userNamespaceNames += $nsName }

            $classes = @(Get-RsopInventorySafeProperty -InputObject $ns -Name 'Classes' -Default @())
            $nsClassErrors = @(Get-RsopInventorySafeProperty -InputObject $ns -Name 'ClassErrors' -Default @())
            foreach ($ce in $nsClassErrors) {
                $ceClass = Get-RsopInventorySafeProperty -InputObject $ce -Name 'ClassName' -Default ''
                $ceMessage = Get-RsopInventorySafeProperty -InputObject $ce -Name 'Error' -Default ''
                $classErrorItems += "${nsName}:${ceClass}:${ceMessage}"
            }

            # RSOP_GPO, RSOP_SOM and RSOP_ExtensionEventSource instances of this namespace resolve names for the rows built below, keyed on their own id, lower-cased.
            $gpoNameMap = @{}
            $somMap = @{}
            $eventSourceById = @{}
            foreach ($cls in $classes) {
                $className = [string](Get-RsopInventorySafeProperty -InputObject $cls -Name 'ClassName' -Default '')
                $instances = @(Get-RsopInventorySafeProperty -InputObject $cls -Name 'Instances' -Default @())
                if ($className -eq 'RSOP_GPO') {
                    foreach ($gi in $instances) {
                        $gid = Get-RsopInventorySafeProperty -InputObject $gi -Name 'id' -Default $null
                        if ($gid) { $gpoNameMap[$gid.ToLowerInvariant()] = Get-RsopInventorySafeProperty -InputObject $gi -Name 'name' -Default $null }
                    }
                } elseif ($className -eq 'RSOP_SOM') {
                    foreach ($si in $instances) {
                        $sid = Get-RsopInventorySafeProperty -InputObject $si -Name 'id' -Default $null
                        if ($sid) { $somMap[$sid.ToLowerInvariant()] = $si }
                    }
                } elseif ($className -eq 'RSOP_ExtensionEventSource') {
                    foreach ($ei in $instances) {
                        $eid = Get-RsopInventorySafeProperty -InputObject $ei -Name 'id' -Default $null
                        if ($eid) { $eventSourceById[$eid.ToLowerInvariant()] = $ei }
                    }
                }
            }

            # RSOP_ExtensionEventSourceLink joins an extension to its event sources, so it is resolved to a plain map before the extension rows are built.
            $eventSourceMap = @{}
            foreach ($cls in $classes) {
                $className = [string](Get-RsopInventorySafeProperty -InputObject $cls -Name 'ClassName' -Default '')
                if ($className -ne 'RSOP_ExtensionEventSourceLink') { continue }
                $linkInstances = @(Get-RsopInventorySafeProperty -InputObject $cls -Name 'Instances' -Default @())
                foreach ($li in $linkInstances) {
                    $extRef = Get-RsopInventorySafeProperty -InputObject $li -Name 'extensionStatus' -Default $null
                    $extGuid = Get-RsopInventorySafeProperty -InputObject $extRef -Name 'extensionGuid' -Default $null
                    $esRef = Get-RsopInventorySafeProperty -InputObject $li -Name 'eventSource' -Default $null
                    $esId = Get-RsopInventorySafeProperty -InputObject $esRef -Name 'id' -Default $null
                    $esFull = $esRef
                    if ($esId -and $eventSourceById.ContainsKey($esId.ToLowerInvariant())) { $esFull = $eventSourceById[$esId.ToLowerInvariant()] }
                    $logName = Get-RsopInventorySafeProperty -InputObject $esFull -Name 'eventLogName' -Default $null
                    $logSource = Get-RsopInventorySafeProperty -InputObject $esFull -Name 'eventLogSource' -Default $null
                    if ($extGuid) {
                        $mapKey = $extGuid.ToLowerInvariant()
                        if (-not $eventSourceMap.ContainsKey($mapKey)) { $eventSourceMap[$mapKey] = @() }
                        $eventSourceMap[$mapKey] += "$logName\$logSource"
                    }
                }
            }

            $normalizedClasses = @()
            foreach ($cls in $classes) {
                $className = [string](Get-RsopInventorySafeProperty -InputObject $cls -Name 'ClassName' -Default '')
                $instances = @(Get-RsopInventorySafeProperty -InputObject $cls -Name 'Instances' -Default @())

                if (-not $classCounts.Contains($className)) { $classCounts[$className] = 0 }

                $instanceCountValue = Get-RsopInventorySafeProperty -InputObject $cls -Name 'InstanceCount' -Default $instances.Count
                $normalizedClasses += [pscustomobject]@{
                    ClassName     = $className
                    InstanceCount = $instanceCountValue
                    Instances     = @($instances)
                }

                switch ($className) {
                    'RSOP_GPO' {
                        foreach ($inst in $instances) { $gpoRows += ConvertTo-RsopInventoryGpoRow -Namespace $nsName -Instance $inst }
                    }
                    'RSOP_GPLink' {
                        foreach ($inst in $instances) { $linkRows += ConvertTo-RsopInventoryLinkRow -Namespace $nsName -Instance $inst -SomMap $somMap -GpoNameMap $gpoNameMap }
                    }
                    'RSOP_ExtensionStatus' {
                        foreach ($inst in $instances) { $extensionRows += ConvertTo-RsopInventoryExtensionRow -Namespace $nsName -Instance $inst -EventSourceMap $eventSourceMap }
                    }
                    'RSOP_Session' {
                        foreach ($inst in $instances) {
                            $creationTime = Get-RsopInventorySafeProperty -InputObject $inst -Name 'creationTime' -Default $null
                            if ($creationTime -is [DateTime]) { $creationTime = $creationTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
                            $securityGroups = @(Get-RsopInventorySafeProperty -InputObject $inst -Name 'SecurityGroups' -Default @())
                            $sessionRows += [pscustomobject]@{
                                Namespace          = $nsName
                                Id                 = Get-RsopInventorySafeProperty -InputObject $inst -Name 'id' -Default $null
                                CreationTime       = $creationTime
                                TargetName         = Get-RsopInventorySafeProperty -InputObject $inst -Name 'targetName' -Default $null
                                Site               = Get-RsopInventorySafeProperty -InputObject $inst -Name 'site' -Default $null
                                SlowLink           = Get-RsopInventorySafeProperty -InputObject $inst -Name 'slowLink' -Default $null
                                SOM                = Get-RsopInventorySafeProperty -InputObject $inst -Name 'som' -Default $null
                                SecurityGroupCount = $securityGroups.Count
                            }
                        }
                    }
                    default {
                        foreach ($inst in $instances) {
                            $rows = @()
                            try {
                                $rows = @(ConvertTo-RsopInventorySettingRow -Namespace $nsName -ClassName $className -Instance $inst -GpoNameMap $gpoNameMap)
                            }
                            catch {
                                $instId = Get-RsopInventorySafeProperty -InputObject $inst -Name 'id' -Default ''
                                $errors += ("setting row ${nsName} ${className} ${instId}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
                            }
                            foreach ($row in $rows) {
                                $settingRows += $row
                                $classCounts[$className] = $classCounts[$className] + 1
                            }
                        }
                    }
                }
            }

            $normalizedNamespaces += [pscustomobject]@{
                Namespace   = $nsName
                Path        = Get-RsopInventorySafeProperty -InputObject $ns -Name 'Path' -Default $null
                Classes     = @($normalizedClasses)
                ClassErrors = @($nsClassErrors)
            }
        }

        $settingCountValue = $settingRows.Count
        #endregion

        $reportedName = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerName' -Default $RequestedComputerName
        if ([string]::IsNullOrWhiteSpace($reportedName)) { $reportedName = $RequestedComputerName }
        $reportedNameUpper = $reportedName.ToUpperInvariant()

        $buildNumber = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'CurrentBuild' -Default $null
        if ([string]::IsNullOrWhiteSpace($buildNumber)) { $buildNumber = 'unknown' }

        $folderStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
        # The reported name comes from the target. A name carrying path separators, dots or wildcard characters must not steer the folder outside the run folder or trip the provider, so anything outside letters, digits, underscore and hyphen becomes an underscore. ASCII NetBIOS names are unchanged; a name with other letters gets underscores and stays unique through the suffix rule.
        $safeReportedName = [regex]::Replace($reportedNameUpper, '[^A-Za-z0-9_-]', '_')
        # The build number is a registry string read on the target, so it gets the same treatment. The stamp is generated here and stays as it is.
        $safeBuildNumber = [regex]::Replace([string]$buildNumber, '[^A-Za-z0-9_-]', '_')
        $folderName = '{0}_{1}_{2}Z' -f $safeReportedName, $safeBuildNumber, $folderStamp
        $outputFolder = Resolve-RsopInventoryUniqueFolder -Path (Join-Path $RunFolder $folderName)

        #region settings.json and settings.csv, design section 7.2
        try {
            $settingsJson = ConvertTo-Json -InputObject @($settingRows) -Depth 6
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'settings.json') -Content $settingsJson
        } catch {
            $errors += ("write settings.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $settingCsvRows = @($settingRows | ForEach-Object { ConvertTo-RsopInventorySettingCsvRow -SettingRow $_ })
            $settingColumns = @('Namespace', 'Class', 'GpoId', 'GpoName', 'Precedence', 'SomId', 'Key', 'Name', 'ValueType', 'Value', 'Deleted', 'Status', 'ErrorCode', 'InstanceId', 'Detail')
            Write-RsopInventoryCsvFile -Row $settingCsvRows -Path (Join-Path $outputFolder 'settings.csv') -Column $settingColumns
        } catch {
            $errors += ("write settings.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        #region gpos.json and gpos.csv, design section 7.3
        try {
            $gposJson = ConvertTo-Json -InputObject @($gpoRows) -Depth 6
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'gpos.json') -Content $gposJson
        } catch {
            $errors += ("write gpos.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $gpoCsvRows = @($gpoRows | Select-Object -Property Namespace, GpoId, Name, GuidName, Enabled, AccessDenied, FilterAllowed, FilterId, Version, FileSystemPath, @{ Name = 'ExtensionIds'; Expression = { $_.ExtensionIds -join '|' } })
            $gpoColumns = @('Namespace', 'GpoId', 'Name', 'GuidName', 'Enabled', 'AccessDenied', 'FilterAllowed', 'FilterId', 'Version', 'FileSystemPath', 'ExtensionIds')
            Write-RsopInventoryCsvFile -Row $gpoCsvRows -Path (Join-Path $outputFolder 'gpos.csv') -Column $gpoColumns
        } catch {
            $errors += ("write gpos.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        #region links.json and links.csv, design section 7.4
        try {
            $linksJson = ConvertTo-Json -InputObject @($linkRows) -Depth 6
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'links.json') -Content $linksJson
        } catch {
            $errors += ("write links.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $linkColumns = @('Namespace', 'GpoId', 'GpoName', 'SomId', 'SomType', 'SomBlocked', 'SomBlocking', 'SomReason', 'AppliedOrder', 'LinkOrder', 'SomOrder', 'Enabled', 'NoOverride')
            Write-RsopInventoryCsvFile -Row @($linkRows) -Path (Join-Path $outputFolder 'links.csv') -Column $linkColumns
        } catch {
            $errors += ("write links.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        #region extensions.json and extensions.csv, design section 7.5
        try {
            $extensionsJson = ConvertTo-Json -InputObject @($extensionRows) -Depth 6
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'extensions.json') -Content $extensionsJson
        } catch {
            $errors += ("write extensions.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $extensionCsvRows = @($extensionRows | Select-Object -Property Namespace, ExtensionGuid, DisplayName, Error, BeginTime, EndTime, LoggingStatus, @{ Name = 'EventSources'; Expression = { $_.EventSources -join '|' } })
            $extensionColumns = @('Namespace', 'ExtensionGuid', 'DisplayName', 'Error', 'BeginTime', 'EndTime', 'LoggingStatus', 'EventSources')
            Write-RsopInventoryCsvFile -Row $extensionCsvRows -Path (Join-Path $outputFolder 'extensions.csv') -Column $extensionColumns
        } catch {
            $errors += ("write extensions.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        #region accounts.json and accounts.csv, shared output convention account table
        $accounts = @(Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'Accounts' -Default @())

        try {
            $accountsJson = ConvertTo-Json -InputObject @($accounts) -Depth 6
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'accounts.json') -Content $accountsJson
        } catch {
            $errors += ("write accounts.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $accountCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'Error')
            $accountCsvRows = @($accounts | Select-Object -Property $accountCsvColumns)
            Write-RsopInventoryCsvFile -Row $accountCsvRows -Path (Join-Path $outputFolder 'accounts.csv') -Column $accountCsvColumns
        } catch {
            $errors += ("write accounts.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        #region raw.json, design section 7.7, from the normalized copy so a single-instance class still round-trips as a JSON array
        try {
            $normalizedRaw = [pscustomobject]@{
                ComputerNamespace = Get-RsopInventorySafeProperty -InputObject $parsedRaw -Name 'ComputerNamespace' -Default $null
                Namespaces        = @($normalizedNamespaces)
            }
            $rawJsonOut = ConvertTo-Json -InputObject $normalizedRaw -Depth 12
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'raw.json') -Content $rawJsonOut
        } catch {
            $errors += ("write raw.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        #region summary.json, design section 7.8
        try {
            $extensionErrorItems = @($extensionRows | Where-Object { $null -ne $_.Error -and $_.Error -ne 0 } | ForEach-Object { "$($_.Namespace):$($_.DisplayName):$($_.Error)" })
            $unresolvedTokens = @($accounts | Where-Object { (Get-RsopInventorySafeProperty -InputObject $_ -Name 'Status' -Default '') -eq 'NotFound' } | ForEach-Object { $_.Token })

            $settingCountByClass = [ordered]@{}
            foreach ($className in $classCounts.Keys) { $settingCountByClass[$className] = $classCounts[$className] }

            $summaryObject = [ordered]@{
                SettingCount            = $settingCountValue
                SettingCountByClass     = [pscustomobject]$settingCountByClass
                GpoCount                = $gpoCountValue
                UserNamespaces          = @($userNamespaceNames)
                ExtensionErrorCount     = $extensionErrorCountValue
                ExtensionErrors         = $extensionErrorItems
                ClassErrorCount         = $classErrorCountValue
                ClassErrors             = $classErrorItems
                Sessions                = @($sessionRows)
                AccountCount            = $accountCountValue
                AccountUnresolvedCount  = $accountUnresolvedCountValue
                AccountUnresolvedTokens = $unresolvedTokens
                IdentityDurationMs      = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'IdentityDurationMs' -Default $null
                ComputerDurationMs      = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerDurationMs' -Default $null
                UserDurationMs          = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'UserDurationMs' -Default $null
                AccountsDurationMs      = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'AccountsDurationMs' -Default $null
            }
            $summaryJson = ConvertTo-Json -InputObject ([pscustomobject]$summaryObject) -Depth 6
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'summary.json') -Content $summaryJson
        } catch {
            $errors += ("write summary.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        #region system.json, design section 7.1, in the exact documented order
        try {
            # Built as an explicit ordered list of names, not by enumerating $WorkerObject.PSObject.Properties, so the key order in system.json always matches the output convention regardless of how a worker object happened to be built (a live worker return or a PSSerializer round trip). Values are written as the worker returned them: the worker already types PartOfDomain, IsElevated and DomainRole.
            $systemObject = [ordered]@{}
            $identityPropertyOrder = @('ComputerName', 'DnsHostName', 'Domain', 'OSCaption', 'OSVersion', 'CurrentBuild', 'UBR',
                'DisplayVersion', 'EditionID', 'InstallationType', 'Culture', 'TimeZoneId', 'PSVersion', 'CollectedBy',
                'PartOfDomain', 'IsElevated', 'DomainRole', 'CollectedUtc', 'ComputerId', 'MachineGuid')
            foreach ($name in $identityPropertyOrder) {
                $systemObject[$name] = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Collector'] = 'RemoteRSOP'
            $systemObject['CollectorVersion'] = $MyInvocation.MyCommand.Module.Version.ToString()
            $systemObject['RunId'] = Split-Path -Path $RunFolder -Leaf

            $modulePropertyOrder = @('ComputerNamespace', 'UserNamespaceRoot', 'UserNamespaces', 'ComputerClassCount', 'ComputerInstanceCount',
                'UserNamespaceCount', 'UserInstanceCount', 'SettingCount', 'GpoCount', 'ExtensionErrorCount', 'ClassErrorCount',
                'AccountCount', 'AccountUnresolvedCount')
            foreach ($name in $modulePropertyOrder) {
                $systemObject[$name] = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }
            # UserNamespaces and SettingCount are derived here from the parsed dump, not taken from the worker object; assigning to a key that already exists keeps its position in the ordered list.
            $systemObject['UserNamespaces'] = @($userNamespaceNames)
            $systemObject['SettingCount'] = $settingCountValue

            $systemObject['Errors'] = @($errors)
            $systemObject['Transport'] = $Transport
            $systemObject['RequestedComputerName'] = $RequestedComputerName
            $systemObject['Status'] = $status

            $systemJson = ConvertTo-Json -InputObject ([pscustomobject]$systemObject) -Depth 6
            Write-RsopInventoryTextFile -Path (Join-Path $outputFolder 'system.json') -Content $systemJson
        } catch {
            $errors += ("write system.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        $isElevatedValue = Get-RsopInventorySafeProperty -InputObject $WorkerObject -Name 'IsElevated' -Default $null
        if ($null -ne $isElevatedValue) { $isElevatedValue = [bool]$isElevatedValue }

        return ConvertTo-RsopInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerIdValue -Status $status -Transport $Transport `
            -OutputFolder $outputFolder -IsElevated $isElevatedValue `
            -ComputerClassCount $computerClassCountValue -ComputerInstanceCount $computerInstanceCountValue `
            -UserNamespaceCount $userNamespaceCountValue -UserInstanceCount $userInstanceCountValue `
            -SettingCount $settingCountValue -GpoCount $gpoCountValue `
            -ExtensionErrorCount $extensionErrorCountValue -ClassErrorCount $classErrorCountValue `
            -AccountCount $accountCountValue -AccountUnresolvedCount $accountUnresolvedCountValue `
            -Errors $errors
    } catch {
        $errors += ("unexpected error processing ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        return ConvertTo-RsopInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerIdValue -Status 'Failed' -Transport $Transport -Errors $errors
    }
}
