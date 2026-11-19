<#PSScriptInfo

.DESCRIPTION Returns the self-contained scriptblock that collects the event log inventory on a target

.VERSION 1.0.0

.GUID b4d9a051-d43a-4108-9282-e22b28608c2e

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-EventLogInventoryWorker
function Get-EventLogInventoryWorker {

    <#
    .SYNOPSIS
        Returns the self-contained scriptblock that collects the event log inventory on a target.

    .DESCRIPTION
        The scriptblock this function returns is what actually runs on the target, local or
        remote, so it uses no module function, no module variable and no using: expression. It
        takes -SkipSidReference and depends on nothing else from the caller's session. It lists
        every event log the event log service knows, the Analytical and Debug logs included,
        reads the configuration and the file state of each, reads the oldest and the newest record
        of every non-empty log that is not an Analytical or Debug log, reads the Group Policy
        values under the event log policy key, lists the archive files beside each log file, and
        resolves the security identifiers named in each log's security descriptor. An application
        package SID or a capability SID is not looked up: it is listed in AppContainers, classed
        from its text, and the account lookup is kept for real accounts. It also reads
        four SID reference values: MachineSid from the local account with RID 500
        (Win32_UserAccount filtered to the computer's own name, so a domain controller has none
        and keeps null), and, on a domain-joined computer only, DomainSid, ComputerAccountSid and
        DomainNetbiosName from the computer's own domain account through an account lookup. No
        Active Directory module and no LDAP is used. It never throws: every step is wrapped in
        its own try/catch and appends to an Errors list instead. It reads the events of no log
        and writes nothing to the target's disk.
        Invoke-EventLogInventoryLocal calls it directly for the local computer.
        Invoke-EventLogInventoryRemote passes it to Invoke-Command for every remote target.

    .PARAMETER SkipSidReference
        A parameter of the returned scriptblock, not of this function. It is the first parameter
        because the remote call passes it positionally. When true, none of the SID reference
        reads runs: the four values are null with no error. Defaults to false, for tests only.
        Every real caller passes it.

    .PARAMETER LogSource
        A parameter of the returned scriptblock, not of this function. A hashtable of four
        scriptblocks (Names, Configuration, Information, Boundary) that replaces the .NET event
        log classes, which a test cannot mock. Null by default, which builds the table from the
        real classes. Tests only.

    .PARAMETER PolicyKey
        A parameter of the returned scriptblock, not of this function. The hive and path of the
        event log policy key. Only HKEY_LOCAL_MACHINE and HKEY_CURRENT_USER are accepted as the
        hive. Tests only.

    .NOTES
        FUNCTION: Get-EventLogInventoryWorker
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock
    #>

    param()

    return {
        param(
            [Bool]$SkipSidReference = $false,

            [Hashtable]$LogSource = $null,

            [String]$PolicyKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\EventLog'
        )

        # Off here, not only in the public function, so the worker behaves the same in-process as on a remote
        # target, where strict mode is off by default.
        Set-StrictMode -Off

        #region ConvertTo-EventLogInventoryMessage
        function ConvertTo-EventLogInventoryMessage {
            <#
            .SYNOPSIS
                Returns a message as a single trimmed line.
            #>
            param(
                [AllowNull()]
                [String]$Text
            )

            return ([String]$Text).Trim() -replace '\s+', ' '
        }
        #endregion

        #region ConvertTo-EventLogInventoryUtcDateTime
        function ConvertTo-EventLogInventoryUtcDateTime {
            <#
            .SYNOPSIS
                Returns a time as a DateTime in UTC, or $null for $null.

            .DESCRIPTION
                The event log classes give DateTime values of kind Local. A DateTimeOffset is taken as it is.
            #>
            param(
                [AllowNull()]
                [Object]$Value
            )

            if ($null -eq $Value) {
                return $null
            }

            $time = $Value
            if ($time -is [DateTimeOffset]) {
                $time = $time.UtcDateTime
            }
            return ([DateTime]$time).ToUniversalTime()
        }
        #endregion

        #region ConvertTo-EventLogInventoryUtcText
        function ConvertTo-EventLogInventoryUtcText {
            <#
            .SYNOPSIS
                Returns a time as an ISO 8601 UTC string, or $null for $null.
            #>
            param(
                [AllowNull()]
                [Object]$Value
            )

            $utc = ConvertTo-EventLogInventoryUtcDateTime -Value $Value
            if ($null -eq $utc) {
                return $null
            }
            return $utc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        #endregion

        #region Get-EventLogInventoryColumnValue
        function Get-EventLogInventoryColumnValue {
            <#
            .SYNOPSIS
                Reads the named properties of one object and returns them as plain data in a hashtable.

            .DESCRIPTION
                Kinds is a hashtable of property name to kind: Text (a string, an enumeration value becomes its
                display string), Bool, Int64, Time (an ISO 8601 UTC string) and Count (the number of entries of
                a list). A property the object lacks, or one that holds null, gives null. A read or a
                conversion that fails throws to the caller, so one log's failure is named by that log's row.
            #>
            param(
                [AllowNull()]
                [Object]$InputObject,

                [Hashtable]$Kinds
            )

            $values = @{}
            if ($null -eq $InputObject) {
                return $values
            }

            $properties = $InputObject.PSObject.Properties
            foreach ($propertyName in $Kinds.Keys) {
                $value = $null
                $member = $properties[$propertyName]
                if ($null -ne $member) {
                    $value = $member.Value
                }
                if ($null -ne $value) {
                    $kind = $Kinds[$propertyName]
                    if ($kind -eq 'Text') {
                        $value = [String]$value
                    }
                    elseif ($kind -eq 'Bool') {
                        $value = [Bool]$value
                    }
                    elseif ($kind -eq 'Int64') {
                        $value = [Int64]$value
                    }
                    elseif ($kind -eq 'Time') {
                        $value = ConvertTo-EventLogInventoryUtcText -Value $value
                    }
                    elseif ($kind -eq 'Count') {
                        $value = [Int]@($value).Count
                    }
                }
                $values[$propertyName] = $value
            }
            return $values
        }
        #endregion

        #region Test-EventLogInventoryLocalFilePath
        function Test-EventLogInventoryLocalFilePath {
            <#
            .SYNOPSIS
                Returns true only for a drive-letter path on a local fixed disk.
            #>
            param(
                [AllowNull()]
                [AllowEmptyString()]
                [String]$Path,

                [AllowNull()]
                [System.Collections.Generic.HashSet[String]]$FixedDriveLetter
            )

            # The path comes from the configuration of a log on the target and the step may run elevated, so only
            # a folder on a local fixed disk is listed. A UNC, device, pipe, relative or stream path never reaches
            # a file call.
            if (($null -eq $FixedDriveLetter) -or [String]::IsNullOrEmpty($Path)) {
                return $false
            }
            if ($Path -notmatch '^[A-Za-z]:\\') {
                return $false
            }
            if ($Path.IndexOf(':', 2) -ge 0) {
                return $false
            }
            return $FixedDriveLetter.Contains($Path.Substring(0, 1))
        }
        #endregion

        #region Test-EventLogInventoryRedirectedProcess
        function Test-EventLogInventoryRedirectedProcess {
            <#
            .SYNOPSIS
                Returns true in a 32-bit process on a 64-bit Windows, where System32 is redirected.
            #>
            param()

            return ((-not [Environment]::Is64BitProcess) -and [Environment]::Is64BitOperatingSystem)
        }
        #endregion

        #region Get-EventLogInventoryListingPath
        function Get-EventLogInventoryListingPath {
            <#
            .SYNOPSIS
                Returns the path a log folder is listed through.
            #>
            param(
                [Parameter(Mandatory = $true)]
                [String]$Folder,

                [AllowNull()]
                [AllowEmptyString()]
                [String]$SystemRoot,

                [Bool]$Redirected
            )

            # A 32-bit process on a 64-bit Windows sees the folder System32 as SysWOW64. The log files are in the
            # real System32, which such a process reaches through the name Sysnative. Any other folder, and every
            # process that is not redirected, lists the folder as it is.
            if ((-not $Redirected) -or [String]::IsNullOrEmpty($SystemRoot)) {
                return $Folder
            }
            $root = $SystemRoot.TrimEnd('\')
            $systemFolder = $root + '\System32'
            if ($Folder.Equals($systemFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $root + '\Sysnative'
            }
            if ($Folder.StartsWith($systemFolder + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                return $root + '\Sysnative' + $Folder.Substring($systemFolder.Length)
            }
            return $Folder
        }
        #endregion

        #region Test-EventLogInventorySymbolicLinkPath
        function Test-EventLogInventorySymbolicLinkPath {
            <#
            .SYNOPSIS
                Returns true when a folder or any folder above it is a symbolic link.
            #>
            param(
                [Parameter(Mandatory = $true)]
                [String]$Path
            )

            # A symbolic link can point to a remote share, and a listing through it would leave the local disk
            # the gate has just vouched for. A junction cannot point to a remote path, so it is accepted. The
            # path is walked from the drive root down and the first link ends the walk. The attributes are read
            # without opening a file, and the link type is asked only of a folder that is a reparse point.
            $parts = $Path.Split('\')
            $current = $parts[0] + '\'
            for ($index = 1; $index -lt $parts.Count; $index++) {
                if ([String]::IsNullOrEmpty($parts[$index])) {
                    continue
                }
                if ($current.EndsWith('\')) {
                    $current = $current + $parts[$index]
                }
                else {
                    $current = $current + '\' + $parts[$index]
                }
                try {
                    $attributes = [System.IO.File]::GetAttributes($current)
                }
                catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
                    # Nothing below a missing folder exists, so there is no link further down.
                    return $false
                }
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $linkItem = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                    if ($linkItem.LinkType -eq 'SymbolicLink') {
                        return $true
                    }
                }
            }
            return $false
        }
        #endregion
        $errors = @()

        #region Identity
        $dnsHostName = $null
        $domain = $null
        $partOfDomain = $false
        $domainRole = -1
        $osCaption = $null
        $osVersion = $null
        $currentBuild = $null
        $ubr = $null
        $displayVersion = $null
        $editionId = $null
        $installationType = $null
        $culture = $null
        $timeZoneId = $null
        $isElevated = $false
        $collectedBy = $null

        try {
            $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $currentBuild = $cv.CurrentBuild
            if ($null -ne $cv.UBR) {
                $ubr = $cv.UBR.ToString()
            }
            $displayVersion = $cv.DisplayVersion
            $editionId = $cv.EditionID
            $installationType = $cv.InstallationType
        }
        catch {
            $errors += "CurrentVersion key: $($_.Exception.Message)"
        }

        $os = $null
        $cs = $null
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop -Verbose:$false
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop -Verbose:$false
        }
        catch {
            $errors += "Get-CimInstance failed: $($_.Exception.Message)"
        }

        if ($null -ne $os) {
            $osCaption = $os.Caption
            $osVersion = $os.Version
        }
        if ($null -ne $cs) {
            $dnsHostName = $cs.DNSHostName
            $domain = $cs.Domain
            $partOfDomain = [Bool]$cs.PartOfDomain
            if ($null -ne $cs.DomainRole) {
                $domainRole = [Int]$cs.DomainRole
            }
        }

        try {
            $culture = [System.Globalization.CultureInfo]::CurrentCulture.Name
        }
        catch {
            $errors += "culture: $($_.Exception.Message)"
        }

        try {
            $timeZoneId = [System.TimeZoneInfo]::Local.Id
        }
        catch {
            $errors += "time zone: $($_.Exception.Message)"
        }

        try {
            $winIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $collectedBy = $winIdentity.Name
            $winPrincipal = New-Object System.Security.Principal.WindowsPrincipal($winIdentity)
            $isElevated = $winPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch {
            $errors += "elevation check: $($_.Exception.Message)"
            $isElevated = $false
        }

        # An unelevated caller sees only the items it may open. Without this line the row would be Success
        # with a shorter inventory and IsElevated as the only signal. With the line the shortfall is named
        # in the row, which makes it Partial.
        if (-not $isElevated) {
            $errors += 'not elevated: event logs the caller cannot open are not listed'
        }
        #endregion

        #region Computer identity
        $computerId = $null
        $machineGuid = $null
        try {
            $product = $null
            $product = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop -Verbose:$false
            if ($null -ne $product -and $null -ne $product.PSObject.Properties['UUID'] -and -not [String]::IsNullOrWhiteSpace([String]$product.UUID)) {
                $computerId = ([String]$product.UUID).Trim().ToUpperInvariant()
            }
        }
        catch {
            $errors += "identity: ComputerId: $($_.Exception.Message)"
        }
        try {
            $machineGuid = [String](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        }
        catch {
            $errors += "identity: MachineGuid: $($_.Exception.Message)"
        }
        #endregion

        #region SID reference
        # Four reference values that say whose an S-1-5-21 SID is. None is used as identity. MachineSid is the
        # SID of the computer's own account database: the built-in Administrator (RID 500, whatever its name
        # or state) without the RID. The filter names the computer as the domain, so only the local accounts
        # are read. A domain controller has no such row and keeps null with no error. The domain values come
        # from the computer's own account and are read only on a domain-joined computer. -SkipSidReference
        # leaves all four null with no error.
        $machineSid = $null
        $domainSid = $null
        $computerAccountSid = $null
        $domainNetbiosName = $null
        if (-not $SkipSidReference) {
            try {
                $localAccounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter ('Domain = "{0}"' -f $env:COMPUTERNAME) -ErrorAction Stop -Verbose:$false)
                foreach ($localAccount in $localAccounts) {
                    if ([String]$localAccount.SID -match '^(S-1-5-21-\d+-\d+-\d+)-500$') {
                        $machineSid = $matches[1]
                        break
                    }
                }
            }
            catch {
                $errors += "identity: MachineSid: $($_.Exception.Message)"
            }

            if ($partOfDomain) {
                $computerAccountSidObject = $null
                try {
                    $computerAccount = New-Object System.Security.Principal.NTAccount(($domain + '\' + $env:COMPUTERNAME + '$'))
                    $computerAccountSidObject = $computerAccount.Translate([System.Security.Principal.SecurityIdentifier])
                    $computerAccountSid = $computerAccountSidObject.Value
                    $domainSid = $computerAccountSidObject.AccountDomainSid.Value
                }
                catch {
                    $computerAccountSidObject = $null
                    $computerAccountSid = $null
                    $domainSid = $null
                    $errors += "identity: DomainSid: $($_.Exception.GetBaseException().Message)"
                }

                if ($null -ne $computerAccountSidObject) {
                    try {
                        $computerAccountName = $computerAccountSidObject.Translate([System.Security.Principal.NTAccount]).Value
                        $separatorIndex = $computerAccountName.IndexOf('\')
                        if ($separatorIndex -gt 0) {
                            $domainNetbiosName = $computerAccountName.Substring(0, $separatorIndex)
                        }
                    }
                    catch {
                        $errors += "identity: DomainNetbiosName: $($_.Exception.GetBaseException().Message)"
                    }
                }
            }
        }
        #endregion

        #region Log source
        # The four reads sit in one table so a test can replace them: the .NET event log classes cannot be
        # mocked. The blocks are closures, so they keep the session and run the same wherever the table is
        # called from. A configuration object is copied into a plain object and disposed at once, and a reader
        # and its record are disposed in a finally, because a reader that stays open holds the log file. A
        # block throws when its read fails and the caller names the log.
        $eventLogSession = $null
        $sessionError = $null
        if ($null -eq $LogSource) {
            try {
                $eventLogSession = [System.Diagnostics.Eventing.Reader.EventLogSession]::new()
            }
            catch {
                $sessionError = ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message
            }

            $LogSource = @{
                Names         = {
                    if ($null -eq $eventLogSession) {
                        throw $sessionError
                    }
                    $eventLogSession.GetLogNames()
                }.GetNewClosure()
                Configuration = {
                    param($Name)

                    $configuration = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new($Name, $eventLogSession)
                    try {
                        [PSCustomObject]@{
                            LogType            = $configuration.LogType
                            IsClassicLog       = $configuration.IsClassicLog
                            IsEnabled          = $configuration.IsEnabled
                            LogMode            = $configuration.LogMode
                            LogIsolation       = $configuration.LogIsolation
                            OwningProviderName = $configuration.OwningProviderName
                            LogFilePath        = $configuration.LogFilePath
                            MaximumSizeInBytes = $configuration.MaximumSizeInBytes
                            SecurityDescriptor = $configuration.SecurityDescriptor
                        }
                    }
                    finally {
                        $configuration.Dispose()
                    }
                }.GetNewClosure()
                Information   = {
                    param($Name)

                    $eventLogSession.GetLogInformation($Name, [System.Diagnostics.Eventing.Reader.PathType]::LogName)
                }.GetNewClosure()
                Boundary      = {
                    param($Name, $Reverse)

                    $query = [System.Diagnostics.Eventing.Reader.EventLogQuery]::new($Name, [System.Diagnostics.Eventing.Reader.PathType]::LogName)
                    $query.ReverseDirection = [Bool]$Reverse
                    $reader = [System.Diagnostics.Eventing.Reader.EventLogReader]::new($query)
                    try {
                        $record = $reader.ReadEvent()
                        if ($null -eq $record) {
                            return $null
                        }
                        try {
                            [PSCustomObject]@{
                                RecordId    = $record.RecordId
                                TimeCreated = $record.TimeCreated
                            }
                        }
                        finally {
                            $record.Dispose()
                        }
                    }
                    finally {
                        $reader.Dispose()
                    }
                }.GetNewClosure()
            }
        }
        #endregion

        #region Logs
        $logRows = @()
        $logCount = $null
        $enabledLogCount = $null
        $logReadFailedCount = $null
        $logReadFailedItems = [System.Collections.Generic.List[String]]::new()
        $logsDurationMs = 0
        $namesRead = $false
        $rowByName = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)

        $stopwatchLogs = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $nameList = [System.Collections.Generic.List[String]]::new()
            try {
                foreach ($listedName in @(& $LogSource.Names)) {
                    if (-not [String]::IsNullOrEmpty([String]$listedName)) {
                        [Void]$nameList.Add([String]$listedName)
                    }
                }
                $namesRead = $true
            }
            catch {
                $errors += "logs: $(ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)"
            }

            if ($namesRead) {
                if ($nameList.Count -eq 0) {
                    $errors += 'logs: no log returned'
                }
                $nameList.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )

                # Source property name to kind. The columns that carry another name (the three times) are taken
                # from the result by their source name below.
                $configurationKinds = @{
                    LogType            = 'Text'
                    IsClassicLog       = 'Bool'
                    IsEnabled          = 'Bool'
                    LogMode            = 'Text'
                    LogIsolation       = 'Text'
                    OwningProviderName = 'Text'
                    LogFilePath        = 'Text'
                    MaximumSizeInBytes = 'Int64'
                    SecurityDescriptor = 'Text'
                }
                $informationKinds = @{
                    CreationTime       = 'Time'
                    LastWriteTime      = 'Time'
                    LastAccessTime     = 'Time'
                    FileSize           = 'Int64'
                    RecordCount        = 'Int64'
                    OldestRecordNumber = 'Int64'
                    IsLogFull          = 'Bool'
                }

                # A generic list, not an array grown per log: there can be more than a thousand logs.
                $rowList = [System.Collections.Generic.List[Object]]::new()
                $enabledCounter = 0
                $failedCounter = 0

                foreach ($logName in $nameList) {
                    $configurationValues = @{}
                    $informationValues = @{}
                    $configurationError = ''
                    $informationError = ''

                    try {
                        $configurationValues = Get-EventLogInventoryColumnValue -InputObject (& $LogSource.Configuration $logName) -Kinds $configurationKinds
                    }
                    catch {
                        $configurationValues = @{}
                        $configurationError = 'configuration: ' + (ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)
                    }

                    try {
                        $informationValues = Get-EventLogInventoryColumnValue -InputObject (& $LogSource.Information $logName) -Kinds $informationKinds
                    }
                    catch {
                        $informationValues = @{}
                        $informationError = 'information: ' + (ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)
                    }

                    # When both reads fail the row names the configuration one.
                    $readError = $configurationError
                    if ($readError -eq '') {
                        $readError = $informationError
                    }

                    $logFilePath = $configurationValues['LogFilePath']
                    $logFilePathExpanded = $null
                    if ($null -ne $logFilePath) {
                        $logFilePathExpanded = [Environment]::ExpandEnvironmentVariables($logFilePath)
                    }

                    $row = [PSCustomObject][ordered]@{
                        LogName                  = $logName
                        LogType                  = $configurationValues['LogType']
                        IsClassicLog             = $configurationValues['IsClassicLog']
                        IsEnabled                = $configurationValues['IsEnabled']
                        LogMode                  = $configurationValues['LogMode']
                        LogIsolation             = $configurationValues['LogIsolation']
                        OwningProviderName       = $configurationValues['OwningProviderName']
                        LogFilePath              = $logFilePath
                        LogFilePathExpanded      = $logFilePathExpanded
                        MaximumSizeInBytes       = $configurationValues['MaximumSizeInBytes']
                        SecurityDescriptor       = $configurationValues['SecurityDescriptor']
                        FileSize                 = $informationValues['FileSize']
                        RecordCount              = $informationValues['RecordCount']
                        OldestRecordNumber       = $informationValues['OldestRecordNumber']
                        IsLogFull                = $informationValues['IsLogFull']
                        CreationUtc              = $informationValues['CreationTime']
                        LastWriteUtc             = $informationValues['LastWriteTime']
                        LastAccessUtc            = $informationValues['LastAccessTime']
                        OldestRecordId           = $null
                        OldestEventUtc           = $null
                        NewestRecordId           = $null
                        NewestEventUtc           = $null
                        CoveredSeconds           = $null
                        PolicyMaxSize            = $null
                        PolicyRetention          = $null
                        PolicyAutoBackupLogFiles = $null
                        PolicyChannelAccess      = $null
                        PolicyFile               = $null
                        PolicyEnabled            = $null
                        ArchiveCount             = $null
                        ArchiveBytes             = $null
                        ArchiveOldestWriteUtc    = $null
                        ArchiveNewestWriteUtc    = $null
                        ReadError                = $readError
                    }

                    if ($readError -ne '') {
                        $errors += "log ${logName}: $readError"
                        $failedCounter++
                        [Void]$logReadFailedItems.Add($logName)
                    }
                    if ($row.IsEnabled -eq $true) {
                        $enabledCounter++
                    }

                    [Void]$rowList.Add($row)
                    $rowByName[$logName] = $row
                }

                # .ToArray(), not @(...): wrapping a generic List[object] with the array subexpression operator
                # can hit a PowerShell dynamic-binder mismatch once enough types have been loaded.
                $logRows = $rowList.ToArray()
                $logCount = $logRows.Count
                $enabledLogCount = $enabledCounter
                $logReadFailedCount = $failedCounter
            }
        }
        catch {
            # Nothing in the step is expected to throw out. A failure here leaves what was read and says why.
            $errors += "logs: $(ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)"
        }
        finally {
            $stopwatchLogs.Stop()
            $logsDurationMs = [Int]$stopwatchLogs.ElapsedMilliseconds
        }
        #endregion

        #region Records
        # The first and the last record of each log that holds records. OldestRecordNumber from the information
        # read is not the id of the first record on every Windows version, so the first record is read from the
        # log itself. An Analytical or Debug log is not read: it holds no records unless enabled and a read of
        # it can be slow. The two directions are separate reads, and a failure in one leaves the other.
        $recordsDurationMs = 0
        $stopwatchRecords = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            foreach ($logRow in $logRows) {
                if (($logRow.LogType -eq 'Analytical') -or ($logRow.LogType -eq 'Debug')) {
                    continue
                }
                if (($null -eq $logRow.RecordCount) -or ($logRow.RecordCount -le 0)) {
                    continue
                }

                $oldestTime = $null
                $newestTime = $null

                foreach ($reverse in @($false, $true)) {
                    $direction = 'oldest'
                    $columnPrefix = 'Oldest'
                    if ($reverse) {
                        $direction = 'newest'
                        $columnPrefix = 'Newest'
                    }

                    try {
                        $boundary = & $LogSource.Boundary $logRow.LogName $reverse
                        if ($null -ne $boundary) {
                            $recordId = $null
                            $eventTime = $null
                            $idMember = $boundary.PSObject.Properties['RecordId']
                            if (($null -ne $idMember) -and ($null -ne $idMember.Value)) {
                                $recordId = [Int64]$idMember.Value
                            }
                            $timeMember = $boundary.PSObject.Properties['TimeCreated']
                            if ($null -ne $timeMember) {
                                $eventTime = ConvertTo-EventLogInventoryUtcDateTime -Value $timeMember.Value
                            }

                            $logRow.PSObject.Properties[$columnPrefix + 'RecordId'].Value = $recordId
                            if ($null -ne $eventTime) {
                                $logRow.PSObject.Properties[$columnPrefix + 'EventUtc'].Value = $eventTime.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
                            }
                            if ($reverse) {
                                $newestTime = $eventTime
                            }
                            else {
                                $oldestTime = $eventTime
                            }
                        }
                    }
                    catch {
                        # The row keeps the first reason it got. A later failure of the same row adds no
                        # second error line and no second count.
                        if ($logRow.ReadError -eq '') {
                            $logRow.ReadError = $direction + ': ' + (ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)
                            $errors += "log $($logRow.LogName): $($logRow.ReadError)"
                            $logReadFailedCount++
                            [Void]$logReadFailedItems.Add($logRow.LogName)
                        }
                    }
                }

                # From the two times themselves, so the sub-second part of each counts before the cut.
                if (($null -ne $oldestTime) -and ($null -ne $newestTime)) {
                    $logRow.CoveredSeconds = [Int64][Math]::Floor(($newestTime - $oldestTime).TotalSeconds)
                }
            }
        }
        catch {
            $errors += "records: $(ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)"
        }
        finally {
            $stopwatchRecords.Stop()
            $recordsDurationMs = [Int]$stopwatchRecords.ElapsedMilliseconds
            if ($null -ne $eventLogSession) {
                try {
                    $eventLogSession.Dispose()
                }
                catch {
                    $errors += "records: session: $(ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)"
                }
            }
        }
        #endregion

        #region Policy
        # The Group Policy values of the event log policy key. The key is opened through .NET and not through
        # the registry provider, because a log name can hold a slash. Values are read unexpanded and copied in
        # the type the registry holds. Nothing is applied to a row before the whole key has been read, so a
        # failure leaves no half-filled columns.
        $policyKeyPresent = $null
        $policyLogNames = [System.Collections.Generic.List[String]]::new()
        $policyUnmatchedNames = [System.Collections.Generic.List[String]]::new()
        $policyDurationMs = 0

        if ($namesRead) {
            $stopwatchPolicy = [System.Diagnostics.Stopwatch]::StartNew()
            $policyRootKey = $null
            try {
                $policyValueNames = @('MaxSize', 'Retention', 'AutoBackupLogFiles', 'ChannelAccess', 'File', 'Enabled')

                $hiveSeparatorIndex = $PolicyKey.IndexOf('\')
                if ($hiveSeparatorIndex -lt 1) {
                    throw "PolicyKey '$PolicyKey' has no hive and path"
                }
                $hiveName = $PolicyKey.Substring(0, $hiveSeparatorIndex)
                $hivePath = $PolicyKey.Substring($hiveSeparatorIndex + 1)

                $hive = $null
                if ($hiveName -ieq 'HKEY_LOCAL_MACHINE') {
                    $hive = [Microsoft.Win32.Registry]::LocalMachine
                }
                elseif ($hiveName -ieq 'HKEY_CURRENT_USER') {
                    $hive = [Microsoft.Win32.Registry]::CurrentUser
                }
                else {
                    throw "hive '$hiveName' is not supported"
                }

                $policyRootKey = $hive.OpenSubKey($hivePath)
                if ($null -eq $policyRootKey) {
                    $policyKeyPresent = $false
                }
                else {
                    $policyEntries = [System.Collections.Generic.List[Object]]::new()
                    $policyProblems = [System.Collections.Generic.List[String]]::new()
                    $matchedNames = [System.Collections.Generic.List[String]]::new()
                    $unmatchedNames = [System.Collections.Generic.List[String]]::new()

                    foreach ($subKeyName in $policyRootKey.GetSubKeyNames()) {
                        $subKey = $policyRootKey.OpenSubKey($subKeyName)
                        if ($null -eq $subKey) {
                            continue
                        }

                        try {
                            $presentNames = [System.Collections.Generic.HashSet[String]]::new([String[]]$subKey.GetValueNames(), [System.StringComparer]::OrdinalIgnoreCase)
                            $subKeyValues = @{}
                            foreach ($policyValueName in $policyValueNames) {
                                if (-not $presentNames.Contains($policyValueName)) {
                                    continue
                                }

                                $valueKind = $subKey.GetValueKind($policyValueName)
                                $rawValue = $subKey.GetValue($policyValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                                if ($valueKind -eq [Microsoft.Win32.RegistryValueKind]::DWord) {
                                    # The registry hands a DWORD back as a signed number, so a value above
                                    # 2147483647 is widened as unsigned.
                                    $subKeyValues[$policyValueName] = ([Int64]$rawValue) -band 4294967295
                                }
                                elseif (($valueKind -eq [Microsoft.Win32.RegistryValueKind]::String) -or ($valueKind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString)) {
                                    $subKeyValues[$policyValueName] = [String]$rawValue
                                }
                                else {
                                    [Void]$policyProblems.Add("policy $subKeyName ${policyValueName}: kind $valueKind")
                                }
                            }
                        }
                        finally {
                            $subKey.Close()
                        }

                        [Void]$policyEntries.Add([PSCustomObject]@{
                                Name   = $subKeyName
                                Values = $subKeyValues
                            })
                        if ($rowByName.ContainsKey($subKeyName)) {
                            [Void]$matchedNames.Add($subKeyName)
                        }
                        else {
                            [Void]$unmatchedNames.Add($subKeyName)
                        }
                    }

                    foreach ($policyEntry in $policyEntries) {
                        if ($rowByName.ContainsKey($policyEntry.Name)) {
                            $policyRow = $rowByName[$policyEntry.Name]
                            foreach ($policyValueName in $policyEntry.Values.Keys) {
                                $policyRow.PSObject.Properties['Policy' + $policyValueName].Value = $policyEntry.Values[$policyValueName]
                            }
                        }
                    }

                    $matchedNames.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )
                    $unmatchedNames.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )
                    $policyLogNames.AddRange($matchedNames)
                    $policyUnmatchedNames.AddRange($unmatchedNames)
                    foreach ($policyProblem in $policyProblems) {
                        $errors += $policyProblem
                    }
                    $policyKeyPresent = $true
                }
            }
            catch {
                $policyKeyPresent = $null
                $policyLogNames.Clear()
                $policyUnmatchedNames.Clear()
                $errors += "policy: $(ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)"
            }
            finally {
                if ($null -ne $policyRootKey) {
                    $policyRootKey.Close()
                }
                $stopwatchPolicy.Stop()
                $policyDurationMs = [Int]$stopwatchPolicy.ElapsedMilliseconds
            }
        }
        #endregion

        #region Archives
        # One listing per distinct log folder, not one per log. A file Archive-<base>-<stamp>.evtx belongs to
        # the log whose file name without extension is <base>. When two bases both fit, as Archive-Foo-Bar-1.evtx
        # does for Foo and Foo-Bar, the longest base wins. A folder that is not on a local fixed disk, has a
        # symbolic link in its path or cannot be listed is named in the errors and leaves the archive columns of
        # its logs null. A folder that does not exist has no archives, so its logs get 0, 0, null and null.
        $archiveCount = $null
        $archivesDurationMs = 0

        if ($namesRead) {
            $archiveCount = 0
            $stopwatchArchives = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $folderRows = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $folderOrder = [System.Collections.Generic.List[String]]::new()
                foreach ($logRow in $logRows) {
                    $expandedPath = $logRow.LogFilePathExpanded
                    if ([String]::IsNullOrEmpty($expandedPath)) {
                        continue
                    }

                    # String work, not a path API: a path from a registration may hold a character that .NET
                    # Framework path methods refuse.
                    $folder = $expandedPath
                    $folderSeparatorIndex = $expandedPath.LastIndexOf('\')
                    if (($folderSeparatorIndex -eq 2) -and ($expandedPath[1] -eq ':')) {
                        $folder = $expandedPath.Substring(0, 3)
                    }
                    elseif ($folderSeparatorIndex -gt 0) {
                        $folder = $expandedPath.Substring(0, $folderSeparatorIndex)
                    }

                    if (-not $folderRows.ContainsKey($folder)) {
                        $folderRows[$folder] = [System.Collections.Generic.List[Object]]::new()
                        [Void]$folderOrder.Add($folder)
                    }
                    [Void]$folderRows[$folder].Add($logRow)
                }

                # The drive list is read once for the run. A failed read leaves it empty, so no folder is accepted.
                $fixedDriveLetters = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
                if ($folderOrder.Count -gt 0) {
                    try {
                        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
                            if ($drive.DriveType -eq [System.IO.DriveType]::Fixed) {
                                [Void]$fixedDriveLetters.Add($drive.Name.Substring(0, 1))
                            }
                        }
                    }
                    catch {
                        $fixedDriveLetters.Clear()
                    }
                }

                $redirected = Test-EventLogInventoryRedirectedProcess

                foreach ($folder in $folderOrder) {
                    $folderError = $null
                    $archiveFiles = @()
                    if (-not (Test-EventLogInventoryLocalFilePath -Path $folder -FixedDriveLetter $fixedDriveLetters)) {
                        $folderError = 'not a local fixed disk path'
                    }
                    else {
                        try {
                            $listingPath = Get-EventLogInventoryListingPath -Folder $folder -SystemRoot $env:SystemRoot -Redirected $redirected
                            if (Test-EventLogInventorySymbolicLinkPath -Path $listingPath) {
                                $folderError = 'a symbolic link is in the path'
                            }
                            else {
                                $archiveFiles = @(Get-ChildItem -LiteralPath $listingPath -Filter 'Archive-*.evtx' -File -ErrorAction Stop)
                            }
                        }
                        catch [System.Management.Automation.ItemNotFoundException] {
                            # A folder that is not there holds no archives. That is no error, and the logs
                            # keep the zero counts set below.
                            $archiveFiles = @()
                        }
                        catch {
                            $folderError = ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message
                        }
                    }

                    if ($null -ne $folderError) {
                        $errors += "archives ${folder}: $folderError"
                        continue
                    }

                    # The log file name without its extension is the base. Two logs on one file name keep the
                    # first in log name order.
                    $rowByBase = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($folderRow in $folderRows[$folder]) {
                        $folderRow.ArchiveCount = 0
                        $folderRow.ArchiveBytes = [Int64]0
                        $logFileName = $folderRow.LogFilePathExpanded.Substring($folderRow.LogFilePathExpanded.LastIndexOf('\') + 1)
                        $extensionIndex = $logFileName.LastIndexOf('.')
                        if ($extensionIndex -gt 0) {
                            $logFileName = $logFileName.Substring(0, $extensionIndex)
                        }
                        if (-not $rowByBase.ContainsKey($logFileName)) {
                            $rowByBase[$logFileName] = $folderRow
                        }
                    }

                    foreach ($archiveFile in $archiveFiles) {
                        # Every dash after the prefix may end the base, so each candidate is looked up in the table
                        # instead of every base being compared with the file name. The walk starts at the last dash,
                        # so the first hit is the longest base.
                        $archiveName = $archiveFile.Name
                        $bestBase = $null
                        $dashIndex = -1
                        if ($archiveName.StartsWith('Archive-', [System.StringComparison]::OrdinalIgnoreCase)) {
                            $dashIndex = $archiveName.LastIndexOf('-')
                        }
                        while ($dashIndex -ge 8) {
                            $candidateBase = $archiveName.Substring(8, $dashIndex - 8)
                            if ($rowByBase.ContainsKey($candidateBase)) {
                                $bestBase = $candidateBase
                                break
                            }
                            if ($dashIndex -eq 8) {
                                break
                            }
                            $dashIndex = $archiveName.LastIndexOf('-', $dashIndex - 1)
                        }
                        if ($null -eq $bestBase) {
                            continue
                        }

                        $archiveRow = $rowByBase[$bestBase]
                        $writeText = $archiveFile.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
                        $archiveRow.ArchiveCount++
                        $archiveRow.ArchiveBytes += [Int64]$archiveFile.Length
                        # The fixed-width UTC text sorts the same as the time it holds.
                        if (($null -eq $archiveRow.ArchiveOldestWriteUtc) -or ([String]::CompareOrdinal($writeText, $archiveRow.ArchiveOldestWriteUtc) -lt 0)) {
                            $archiveRow.ArchiveOldestWriteUtc = $writeText
                        }
                        if (($null -eq $archiveRow.ArchiveNewestWriteUtc) -or ([String]::CompareOrdinal($writeText, $archiveRow.ArchiveNewestWriteUtc) -gt 0)) {
                            $archiveRow.ArchiveNewestWriteUtc = $writeText
                        }
                        $archiveCount++
                    }
                }
            }
            catch {
                $errors += "archives: $(ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message)"
            }
            finally {
                $stopwatchArchives.Stop()
                $archivesDurationMs = [Int]$stopwatchArchives.ElapsedMilliseconds
            }
        }
        #endregion

        #region Accounts
        $accounts = @()
        $accountCount = 0
        $accountUnresolvedCount = 0
        $appContainers = @()
        $appContainerCount = 0
        $accountsDurationMs = 0
        $sddlFailedCount = $null
        $sddlFailedItems = @()

        $stopwatchAccounts = [System.Diagnostics.Stopwatch]::StartNew()

        # The log read is a precondition: without it nothing was examined, so SddlFailedCount stays null and
        # the loops below have no logs to walk.
        if ($namesRead) {
            $sddlFailedCount = 0
        }

        # The grouping and every lookup sit inside one try/catch, so a failure anywhere in this step never
        # stops the return: the account data for this run is simply empty, with the reason in $errors.
        try {
            $sddlFailedList = [System.Collections.Generic.List[String]]::new()

            # Each distinct descriptor text is parsed once, however many logs carry it. A text maps either to the
            # SIDs of its access control entries (discretionary and system list, not the owner or the group) or
            # to the reason it did not parse.
            $descriptorSids = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::Ordinal)
            $descriptorFailures = [System.Collections.Generic.Dictionary[String, String]]::new([System.StringComparer]::Ordinal)

            # First spelling seen per case-insensitive token is kept as the account's Token.
            $tokenLogNames = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $tokenOrder = [System.Collections.Generic.List[String]]::new()

            foreach ($logRow in $logRows) {
                $descriptorText = $logRow.SecurityDescriptor
                if ([String]::IsNullOrEmpty($descriptorText)) {
                    continue
                }

                if ((-not $descriptorSids.ContainsKey($descriptorText)) -and (-not $descriptorFailures.ContainsKey($descriptorText))) {
                    try {
                        $descriptor = New-Object System.Security.AccessControl.RawSecurityDescriptor ($descriptorText) -ErrorAction Stop
                        $sidSeen = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $sidList = [System.Collections.Generic.List[String]]::new()
                        foreach ($acl in @($descriptor.DiscretionaryAcl, $descriptor.SystemAcl)) {
                            if ($null -eq $acl) {
                                continue
                            }
                            foreach ($ace in $acl) {
                                if ($null -ne $ace.SecurityIdentifier) {
                                    $aceSid = [String]$ace.SecurityIdentifier.Value
                                    if ($sidSeen.Add($aceSid)) {
                                        [Void]$sidList.Add($aceSid)
                                    }
                                }
                            }
                        }
                        $descriptorSids[$descriptorText] = $sidList.ToArray()
                    }
                    catch {
                        $descriptorFailures[$descriptorText] = ConvertTo-EventLogInventoryMessage -Text $_.Exception.GetBaseException().Message
                    }
                }

                if ($descriptorFailures.ContainsKey($descriptorText)) {
                    $sddlFailedCount++
                    [Void]$sddlFailedList.Add($logRow.LogName)
                    $errors += "sddl $($logRow.LogName): $($descriptorFailures[$descriptorText])"
                    continue
                }

                foreach ($sidText in $descriptorSids[$descriptorText]) {
                    if (-not $tokenLogNames.ContainsKey($sidText)) {
                        $tokenLogNames[$sidText] = [System.Collections.Generic.List[String]]::new()
                        [Void]$tokenOrder.Add($sidText)
                    }
                    $tokenLogNames[$sidText].Add($logRow.LogName)
                }
            }
            $sddlFailedItems = $sddlFailedList.ToArray()

            $tokenOrder.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::Ordinal) } )

            foreach ($token in $tokenOrder) {
                # A leading * (the secedit export form) is ignored for the Kind test only, never for the token itself.
                $sidCandidate = $token
                if ($sidCandidate.StartsWith('*', [System.StringComparison]::Ordinal)) {
                    $sidCandidate = $sidCandidate.Substring(1)
                }

                $kind = 'Name'
                if ($sidCandidate -match '^S-1-\d+(-\d+)+$') {
                    $kind = 'Sid'
                }

                # An application package SID or a capability SID names an application, not an account.
                # No account lookup can answer it, so it is classed from its text and kept out of the lookup.
                # S-1-15-2-1 and S-1-15-2-2 are well-known groups and stay accounts.
                $appContainerKind = $null
                if ($kind -eq 'Sid') {
                    if ($sidCandidate.StartsWith('S-1-15-3-', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $appContainerKind = 'Capability'
                    }
                    elseif ($sidCandidate -match '^S-1-15-2(-\d+){2,}$') {
                        $appContainerKind = 'Package'
                    }
                }

                if ($null -ne $appContainerKind) {
                    $appContainerLogNames = $tokenLogNames[$token]
                    $appContainerLogNames.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )

                    $appContainerObject = [PSCustomObject]@{
                        Token          = $token
                        Kind           = $appContainerKind
                        Sid            = $sidCandidate
                        Name           = $null
                        ReferenceCount = $appContainerLogNames.Count
                        References     = @($appContainerLogNames.ToArray())
                    }

                    $appContainers += $appContainerObject
                    continue
                }

                $sid = $null
                $accountName = $null
                $status = 'Resolved'
                $acctError = ''

                if ($kind -eq 'Sid') {
                    $sid = $sidCandidate
                    try {
                        $securityId = New-Object System.Security.Principal.SecurityIdentifier($sidCandidate)
                        $translatedAccount = $securityId.Translate([System.Security.Principal.NTAccount])
                        $accountName = $translatedAccount.Value
                    }
                    catch {
                        $status = 'NotFound'
                        $accountName = $null
                        # The innermost exception's own message, not the method-invocation wrapper, trimmed
                        # and with every run of whitespace, line breaks included, collapsed to one space, so a
                        # NotFound account's Error is always a single line.
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $acctError = ([String]$rawMessage).Trim() -replace '\s+', ' '
                    }
                }
                else {
                    $lookupName = $token
                    try {
                        if ($token -ieq 'LocalSystem') {
                            # The Service Control Manager's own alias, not a real account, so it never goes
                            # through a lookup.
                            $sid = 'S-1-5-18'
                        }
                        else {
                            if ($token.StartsWith('.\', [System.StringComparison]::Ordinal)) {
                                $lookupName = $env:COMPUTERNAME + $token.Substring(1)
                            }
                            $ntAccount = New-Object System.Security.Principal.NTAccount($lookupName)
                            $translated = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
                            $sid = $translated.Value
                        }
                    }
                    catch {
                        $status = 'NotFound'
                        $sid = $null
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $acctError = ([String]$rawMessage).Trim() -replace '\s+', ' '
                    }
                    $accountName = $lookupName
                }

                # The token's own list, sorted in place: it is read nowhere else after this loop, so a copy
                # would only cost memory. Sorted with the same comparer the Logs array itself uses, ordinal
                # case-insensitive.
                $logNamesForToken = $tokenLogNames[$token]
                $logNamesForToken.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )

                $accountObject = [PSCustomObject]@{
                    Token          = $token
                    Kind           = $kind
                    Sid            = $sid
                    Name           = $accountName
                    Status         = $status
                    ReferenceCount = $logNamesForToken.Count
                    References     = @($logNamesForToken.ToArray())
                    Error          = $acctError
                }

                $accounts += $accountObject

                if ($status -eq 'NotFound') {
                    $accountUnresolvedCount++
                }
            }

            $accountCount = $accounts.Count
            $appContainerCount = $appContainers.Count
        }
        catch {
            $errors += "accounts: $(ConvertTo-EventLogInventoryMessage -Text $_.Exception.Message)"
            $accounts = @()
            $accountCount = 0
            $accountUnresolvedCount = 0
            $appContainers = @()
            $appContainerCount = 0
        }
        finally {
            $stopwatchAccounts.Stop()
            $accountsDurationMs = [Int]$stopwatchAccounts.ElapsedMilliseconds
        }
        #endregion

        #region Return
        $collectedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

        $logCountOut = $null
        $enabledLogCountOut = $null
        $logReadFailedCountOut = $null
        $sddlFailedOut = $null
        $archiveCountOut = $null
        if ($null -ne $logCount) {
            $logCountOut = [Int]$logCount
            $enabledLogCountOut = [Int]$enabledLogCount
            $logReadFailedCountOut = [Int]$logReadFailedCount
            if ($null -ne $sddlFailedCount) {
                $sddlFailedOut = [Int]$sddlFailedCount
            }
            if ($null -ne $archiveCount) {
                $archiveCountOut = [Int]$archiveCount
            }
        }

        [PSCustomObject]@{
            ComputerName           = $env:COMPUTERNAME
            DnsHostName            = $dnsHostName
            Domain                 = $domain
            OSCaption              = $osCaption
            OSVersion              = $osVersion
            CurrentBuild           = $currentBuild
            UBR                    = $ubr
            DisplayVersion         = $displayVersion
            EditionID              = $editionId
            InstallationType       = $installationType
            Culture                = $culture
            TimeZoneId             = $timeZoneId
            PSVersion              = $PSVersionTable.PSVersion.ToString()
            CollectedBy            = $collectedBy
            PartOfDomain           = [Bool]$partOfDomain
            IsElevated             = [Bool]$isElevated
            DomainRole             = [Int]$domainRole
            CollectedUtc           = $collectedUtc
            ComputerId             = $computerId
            MachineGuid            = $machineGuid
            MachineSid             = $machineSid
            DomainSid              = $domainSid
            ComputerAccountSid     = $computerAccountSid
            DomainNetbiosName      = $domainNetbiosName
            LogCount               = $logCountOut
            EnabledLogCount        = $enabledLogCountOut
            LogReadFailedCount     = $logReadFailedCountOut
            SddlFailedCount        = $sddlFailedOut
            ArchiveCount           = $archiveCountOut
            AccountCount           = [Int]$accountCount
            AccountUnresolvedCount = [Int]$accountUnresolvedCount
            AppContainerCount      = [Int]$appContainerCount
            PolicyKeyPresent       = $policyKeyPresent
            LogsDurationMs         = [Int]$logsDurationMs
            RecordsDurationMs      = [Int]$recordsDurationMs
            PolicyDurationMs       = [Int]$policyDurationMs
            ArchivesDurationMs     = [Int]$archivesDurationMs
            AccountsDurationMs     = [Int]$accountsDurationMs
            LogReadFailedItems     = @($logReadFailedItems.ToArray())
            SddlFailedItems        = @($sddlFailedItems)
            PolicyLogNames         = @($policyLogNames.ToArray())
            PolicyUnmatchedNames   = @($policyUnmatchedNames.ToArray())
            Logs                   = @($logRows)
            Accounts               = @($accounts)
            AppContainers          = @($appContainers)
            Errors                 = @($errors | ForEach-Object { ([String]$_).Trim() -replace '\s+', ' ' })
        }
        #endregion
    }
}
#endregion
