<#PSScriptInfo

.DESCRIPTION Turns one worker object into a result row, and writes its per-computer folder

.VERSION 1.5.0

.GUID 5f11320f-e8ed-4a58-8391-6686acde3c78

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Complete-FirewallInventoryComputer
function Complete-FirewallInventoryComputer {

    <#
    .SYNOPSIS
        Turns one worker object into a result row, and writes its per-computer folder.

    .DESCRIPTION
        Turns one worker object, or nothing plus the errors that explain why there is none, into
        a result row. When a worker object is present, it also writes the per-computer folder:
        profiles, rules, accounts and appcontainers (application package and capability SIDs, kept out of
        accounts) as json, csv or both, globalsettings.json (only when the
        worker object carries settings), summary.json and system.json. Called once per computer: a caller with several local aliases for the same
        computer calls this once for the first alias and copies the returned row for every later
        one, changing only ComputerName, so no two rows for one folder can ever disagree on
        Status, a count or Errors. Status is computed from the worker object's own counts and its
        own Errors list alone, before any host-side error (a write failure) is appended, so a
        problem the host has while writing the files never changes a Status the target-side
        collection already earned.

        A worker object without an AppContainers list gives an empty appcontainers file and a count
        of 0.

        Every array field of the profile, rule, account and appcontainer rows is rebuilt as an array before it
        is written, because after a WinRM hop a nested array arrives as an ArrayList and a nested
        object as a property bag, and a one-element or empty array must stay an array in json.

        The folder name is built from the computer name the worker object reports with every
        character outside letters, digits, underscore and hyphen replaced by an underscore, because
        that name comes from the target. The name in the json and csv files stays as reported.

    .PARAMETER RequestedComputerName
        The name as the caller requested it, used for the result row and any error messages.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER RunFolder
        The run folder a new per-computer folder is created under. Its leaf name is also the
        RunId recorded in system.json.

    .PARAMETER WorkerObject
        The object Get-FirewallInventoryWorker's scriptblock returned, or $null when the target
        produced nothing.

    .PARAMETER ExtraErrors
        Errors already known before this call, folded into the row's Errors alongside anything
        found here. May be empty or $null.

    .PARAMETER OutputFormat
        Json, Csv or Both. Decides which file of the profiles, rules, accounts and appcontainers pairs is
        written. globalsettings.json, system.json and summary.json have no csv twin and are
        always written. Defaults to Json.

    .NOTES
        FUNCTION: Complete-FirewallInventoryComputer
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteFirewall.Result
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
        return ConvertTo-FirewallInventoryResultRow -ComputerName $RequestedComputerName -Status 'Failed' -Transport $Transport -Errors $errors
    }

    # Set before the try so the catch-all below always has a value to return, even when a later step here
    # throws: a computer that was reached still carries its ComputerId.
    $computerId = $null

    try {
        # A malformed worker object can carry $null or empty-string entries in Errors, dropped here so a
        # summary or a results row never shows a blank line for one.
        $workerErrors = @(Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'Errors' -Default @() | Where-Object { -not [String]::IsNullOrEmpty($_) })
        $errors += $workerErrors

        $computerId = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerId' -Default $null
        $profileCount = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'ProfileCount' -Default $null
        $ruleCount = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'RuleCount' -Default $null
        $filterFailedCount = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'FilterFailedCount' -Default $null
        $sddlFailedCount = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'SddlFailedCount' -Default $null
        $accountCount = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'AccountCount' -Default $null
        $accountUnresolvedCount = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'AccountUnresolvedCount' -Default $null

        # Status is computed from the worker object's own counts and its own Errors list, never from anything
        # the host adds afterward. A $null count (a malformed or partial worker object, or a rules read that
        # failed) is not the same as a verified 0, so Success also requires both counts to be present.
        if (($null -eq $ruleCount) -or ([Int]$ruleCount -eq 0)) {
            $status = 'Failed'
        }
        elseif (($null -ne $filterFailedCount) -and ($null -ne $sddlFailedCount) -and ([Int]$filterFailedCount -eq 0) -and ([Int]$sddlFailedCount -eq 0) -and ($workerErrors.Count -eq 0)) {
            $status = 'Success'
        }
        else {
            $status = 'Partial'
        }

        $reportedName = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerName' -Default $RequestedComputerName
        if ([String]::IsNullOrWhiteSpace($reportedName)) {
            $reportedName = $RequestedComputerName
        }
        $reportedNameUpper = $reportedName.ToUpperInvariant()

        $buildNumber = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'CurrentBuild' -Default $null
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
        $outputFolder = Resolve-FirewallInventoryUniqueFolder -Path (Join-Path $RunFolder $folderName)

        # The column lists in file order. A column of an array list is always an array in the plain row, never
        # null or a bare string. Every other column is a plain read of the property of the same name, null
        # when the source lacks it.
        $profileColumns = @('Name', 'Enabled', 'DefaultInboundAction', 'DefaultOutboundAction', 'AllowInboundRules', 'AllowLocalFirewallRules', 'AllowLocalIPsecRules', 'AllowUserApps', 'AllowUserPorts', 'AllowUnicastResponseToMulticast', 'NotifyOnListen', 'EnableStealthModeForIPsec', 'LogFileName', 'LogMaxSizeKilobytes', 'LogAllowed', 'LogBlocked', 'LogIgnored', 'DisabledInterfaceAliases')
        $profileArrayColumns = @('DisabledInterfaceAliases')
        $settingsColumns = @('ActiveProfile', 'Exemptions', 'EnableStatefulFtp', 'EnableStatefulPptp', 'RequireFullAuthSupport', 'CertValidationLevel', 'AllowIPsecThroughNAT', 'MaxSAIdleTimeSeconds', 'KeyEncoding', 'EnablePacketQueuing', 'RemoteMachineTransportAuthorizationList', 'RemoteMachineTunnelAuthorizationList', 'RemoteUserTransportAuthorizationList', 'RemoteUserTunnelAuthorizationList')
        $ruleColumns = @('Name', 'InstanceID', 'DisplayName', 'Description', 'Group', 'DisplayGroup', 'Enabled', 'Profile', 'Direction', 'Action', 'EdgeTraversalPolicy', 'LooseSourceMapping', 'LocalOnlyMapping', 'Owner', 'Platform', 'PolicyStoreSource', 'PolicyStoreSourceType', 'PrimaryStatus', 'Status', 'StatusCode', 'EnforcementStatus', 'PackageFamilyName', 'PolicyAppId', 'RemoteDynamicKeywordAddresses', 'Protocol', 'LocalPort', 'RemotePort', 'IcmpType', 'DynamicTransport', 'LocalAddress', 'RemoteAddress', 'Program', 'Package', 'Service', 'InterfaceAlias', 'InterfaceType', 'Authentication', 'Encryption', 'OverrideBlockRules', 'LocalUser', 'RemoteUser', 'RemoteMachine')
        $ruleArrayColumns = @('Platform', 'EnforcementStatus', 'RemoteDynamicKeywordAddresses', 'LocalPort', 'RemotePort', 'IcmpType', 'LocalAddress', 'RemoteAddress', 'InterfaceAlias')
        $accountColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'References', 'Error')
        $accountArrayColumns = @('References')
        $accountCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'Error')
        $appContainerColumns = @('Token', 'Kind', 'Sid', 'Name', 'ReferenceCount', 'References')
        $appContainerCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'ReferenceCount')
        # The array column lists as sets, for a lookup per column that does not scan a list.
        $profileArraySet = [System.Collections.Generic.HashSet[String]]::new([String[]]$profileArrayColumns, [System.StringComparer]::OrdinalIgnoreCase)
        $ruleArraySet = [System.Collections.Generic.HashSet[String]]::new([String[]]$ruleArrayColumns, [System.StringComparer]::OrdinalIgnoreCase)
        $accountArraySet = [System.Collections.Generic.HashSet[String]]::new([String[]]$accountArrayColumns, [System.StringComparer]::OrdinalIgnoreCase)
        $noArraySet = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # One source object (live, or a property bag after a remoting hop) into one plain ordered row. Every
        # array column that holds a value is rebuilt as an array: a single value becomes a one-element array,
        # an ArrayList or an array keeps its elements. A $null stays $null, because the worker leaves the
        # columns of a filter class whose read failed null, and that is not the same as an empty array.
        $toPlainRow = {
            param($Source, $Columns, $ArrayColumns)
            $plain = [ordered]@{}
            # The property collection of the source is taken once per row, not once per column.
            $sourceProperties = $Source.PSObject.Properties
            foreach ($column in $Columns) {
                # Read straight from PSObject.Properties, not through Get-FirewallInventorySafeProperty: a
                # function that returns an empty array delivers nothing, so the caller would see $null and an
                # empty array could never be told from an absent value.
                $value = $null
                $property = $sourceProperties[$column]
                if ($null -ne $property) {
                    $value = $property.Value
                }
                if (($null -ne $value) -and $ArrayColumns.Contains($column)) {
                    $items = [System.Collections.Generic.List[Object]]::new()
                    foreach ($item in @($value)) {
                        [Void]$items.Add($item)
                    }
                    $plain[$column] = $items.ToArray()
                }
                else {
                    $plain[$column] = $value
                }
            }
            return [PSCustomObject]$plain
        }

        # An array field of a csv row: elements joined with a vertical bar, whitespace runs collapsed so a row
        # stays on one line, null staying null.
        $toCsvCell = {
            param($Value)
            if ($null -eq $Value) {
                return $null
            }
            if (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [String])) {
                $parts = [System.Collections.Generic.List[String]]::new()
                foreach ($item in $Value) {
                    [Void]$parts.Add("$item")
                }
                return (($parts -join '|') -replace '\s+', ' ')
            }
            if ($Value -is [String]) {
                return ($Value -replace '\s+', ' ')
            }
            return $Value
        }

        # Every per-rule, per-profile and per-account collection is a generic list handed on as an array:
        # growing an array with += is quadratic (97 s for 20,000 rules on Windows PowerShell 5.1).
        $profileList = [System.Collections.Generic.List[Object]]::new()
        foreach ($item in @(Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'Profiles' -Default @() | Where-Object { $null -ne $_ })) {
            [Void]$profileList.Add((& $toPlainRow $item $profileColumns $profileArraySet))
        }
        $profileRows = $profileList.ToArray()
        # profiles.json and profiles.csv are ordered Domain, Private, Public, then any other profile by name,
        # whatever order the target returned them in.
        $profileRank = @{ 'domain' = 0; 'private' = 1; 'public' = 2 }
        $profileRows = @($profileRows | Sort-Object -Property @{ Expression = {
                    $rank = 3
                    $profileKey = ([String]$_.Name).ToLowerInvariant()
                    if ($profileRank.ContainsKey($profileKey)) {
                        $rank = $profileRank[$profileKey]
                    }
                    $rank
                }
            }, @{ Expression = { [String]$_.Name } })

        $settingsObject = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'Settings' -Default $null
        $settingsRow = $null
        if ($null -ne $settingsObject) {
            $settingsRow = & $toPlainRow $settingsObject $settingsColumns $noArraySet
        }

        $ruleList = [System.Collections.Generic.List[Object]]::new()
        foreach ($item in @(Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'Rules' -Default @() | Where-Object { $null -ne $_ })) {
            [Void]$ruleList.Add((& $toPlainRow $item $ruleColumns $ruleArraySet))
        }
        $ruleRows = $ruleList.ToArray()

        $accountList = [System.Collections.Generic.List[Object]]::new()
        foreach ($item in @(Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'Accounts' -Default @() | Where-Object { $null -ne $_ })) {
            [Void]$accountList.Add((& $toPlainRow $item $accountColumns $accountArraySet))
        }
        $accountRows = $accountList.ToArray()

        # A worker object without the list (an older worker, a fake) gives an empty list and a count of 0.
        $appContainerList = [System.Collections.Generic.List[Object]]::new()
        foreach ($item in @(Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'AppContainers' -Default @() | Where-Object { $null -ne $_ })) {
            [Void]$appContainerList.Add((& $toPlainRow $item $appContainerColumns $accountArraySet))
        }
        $appContainerRows = $appContainerList.ToArray()

        if ($writeJson) {
            try {
                # -InputObject @($rows), not a pipe, so an empty array still serialises to [] and a one-element
                # array still serialises to a one-element array, rather than collapsing to a bare object.
                $profilesJson = ConvertTo-Json -InputObject @($profileRows) -Depth 4
                Write-FirewallInventoryTextFile -Path (Join-Path $outputFolder 'profiles.json') -Content $profilesJson
            }
            catch {
                $errors += ("write profiles.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $profileCsvList = [System.Collections.Generic.List[Object]]::new()
                foreach ($row in $profileRows) {
                    $csvRow = [ordered]@{}
                    foreach ($column in $profileColumns) {
                        $csvRow[$column] = & $toCsvCell $row.$column
                    }
                    [Void]$profileCsvList.Add([PSCustomObject]$csvRow)
                }
                Write-FirewallInventoryCsvFile -Row $profileCsvList.ToArray() -Path (Join-Path $outputFolder 'profiles.csv') -Column $profileColumns
            }
            catch {
                $errors += ("write profiles.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        # Written only when the worker read the settings: a null Settings means the read failed and the worker
        # already said so in Errors.
        if ($null -ne $settingsRow) {
            try {
                $settingsJson = $settingsRow | ConvertTo-Json -Depth 4
                Write-FirewallInventoryTextFile -Path (Join-Path $outputFolder 'globalsettings.json') -Content $settingsJson
            }
            catch {
                $errors += ("write globalsettings.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeJson) {
            try {
                $rulesJson = ConvertTo-Json -InputObject @($ruleRows) -Depth 4
                Write-FirewallInventoryTextFile -Path (Join-Path $outputFolder 'rules.json') -Content $rulesJson
            }
            catch {
                $errors += ("write rules.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $ruleCsvList = [System.Collections.Generic.List[Object]]::new()
                foreach ($row in $ruleRows) {
                    [Void]$ruleCsvList.Add((ConvertTo-FirewallInventoryRuleCsvRow -Rule $row))
                }
                Write-FirewallInventoryCsvFile -Row $ruleCsvList.ToArray() -Path (Join-Path $outputFolder 'rules.csv') -Column $ruleColumns
            }
            catch {
                $errors += ("write rules.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeJson) {
            try {
                $accountsJson = ConvertTo-Json -InputObject @($accountRows) -Depth 4
                Write-FirewallInventoryTextFile -Path (Join-Path $outputFolder 'accounts.json') -Content $accountsJson
            }
            catch {
                $errors += ("write accounts.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $accountCsvRows = @($accountRows | Select-Object -Property $accountCsvColumns)
                Write-FirewallInventoryCsvFile -Row $accountCsvRows -Path (Join-Path $outputFolder 'accounts.csv') -Column $accountCsvColumns
            }
            catch {
                $errors += ("write accounts.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeJson) {
            try {
                $appContainersJson = ConvertTo-Json -InputObject @($appContainerRows) -Depth 4
                Write-FirewallInventoryTextFile -Path (Join-Path $outputFolder 'appcontainers.json') -Content $appContainersJson
            }
            catch {
                $errors += ("write appcontainers.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $appContainerCsvRows = @($appContainerRows | Select-Object -Property $appContainerCsvColumns)
                Write-FirewallInventoryCsvFile -Row $appContainerCsvRows -Path (Join-Path $outputFolder 'appcontainers.csv') -Column $appContainerCsvColumns
            }
            catch {
                $errors += ("write appcontainers.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        try {
            # Package rows the packages read could not name. Null when that read did not return, because then
            # no package could have been named and a count would say nothing.
            $packageCountValue = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'PackageCount' -Default $null
            $appContainerUnnamedCount = $null
            if ($null -ne $packageCountValue) {
                $appContainerUnnamedCount = 0
                foreach ($appContainerRow in $appContainerRows) {
                    if (($appContainerRow.Kind -eq 'Package') -and [String]::IsNullOrEmpty($appContainerRow.Name)) {
                        $appContainerUnnamedCount++
                    }
                }
            }

            # One key per PolicyStoreSourceType value seen, sorted ordinal by key, with its count. A rule
            # without the value counts under no key.
            $sourceCounts = New-Object 'System.Collections.Generic.SortedDictionary[string,int]' ([System.StringComparer]::Ordinal)
            foreach ($row in $ruleRows) {
                $sourceType = $row.PolicyStoreSourceType
                if (-not [String]::IsNullOrEmpty($sourceType)) {
                    $sourceKey = [String]$sourceType
                    if ($sourceCounts.ContainsKey($sourceKey)) {
                        $sourceCounts[$sourceKey] = $sourceCounts[$sourceKey] + 1
                    }
                    else {
                        $sourceCounts[$sourceKey] = 1
                    }
                }
            }
            $sourceCountObject = [ordered]@{}
            foreach ($sourceKey in $sourceCounts.Keys) {
                $sourceCountObject[$sourceKey] = $sourceCounts[$sourceKey]
            }

            $summaryObject = [PSCustomObject]@{
                ActiveProfile            = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'ActiveProfile' -Default $null
                ProfileCount             = $profileCount
                RuleCount                = $ruleCount
                EnabledRuleCount         = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'EnabledRuleCount' -Default $null
                RuleCountBySourceType    = [PSCustomObject]$sourceCountObject
                FilterFailedCount        = $filterFailedCount
                FilterFailedItems        = @(Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'FilterFailedItems' -Default @() | Where-Object { $null -ne $_ })
                SddlFailedCount          = $sddlFailedCount
                SddlFailedItems          = @(Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'SddlFailedItems' -Default @() | Where-Object { $null -ne $_ })
                PackageCount             = $packageCountValue
                AppContainerUnnamedCount = $appContainerUnnamedCount
                ProfilesDurationMs       = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'ProfilesDurationMs' -Default $null
                RulesDurationMs          = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'RulesDurationMs' -Default $null
                FiltersDurationMs        = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'FiltersDurationMs' -Default $null
                PackagesDurationMs       = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'PackagesDurationMs' -Default $null
                AccountsDurationMs       = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'AccountsDurationMs' -Default $null
                AccountCount             = $accountCount
                AccountUnresolvedCount   = $accountUnresolvedCount
                AccountUnresolvedTokens  = @($accountRows | Where-Object { $_.Status -eq 'NotFound' } | ForEach-Object { $_.Token })
                AppContainerCount        = $appContainerRows.Count
            }
            $summaryJson = $summaryObject | ConvertTo-Json -Depth 6
            Write-FirewallInventoryTextFile -Path (Join-Path $outputFolder 'summary.json') -Content $summaryJson
        }
        catch {
            $errors += ("write summary.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            # Built as an explicit ordered list of names, not by enumerating
            # $WorkerObject.PSObject.Properties, so the key order in system.json always matches the output
            # convention regardless of how a worker object happened to be built (a live worker return or a
            # PSSerializer round trip).
            $systemObject = [ordered]@{}
            $identityPropertyOrder = @('ComputerName', 'DnsHostName', 'Domain', 'OSCaption', 'OSVersion', 'CurrentBuild', 'UBR',
                'DisplayVersion', 'EditionID', 'InstallationType', 'Culture', 'TimeZoneId', 'PSVersion', 'CollectedBy',
                'PartOfDomain', 'IsElevated', 'DomainRole', 'CollectedUtc', 'ComputerId', 'MachineGuid',
                'MachineSid', 'DomainSid', 'ComputerAccountSid', 'DomainNetbiosName')
            foreach ($name in $identityPropertyOrder) {
                $systemObject[$name] = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Collector'] = 'RemoteFirewall'
            $systemObject['CollectorVersion'] = $MyInvocation.MyCommand.Module.Version.ToString()
            $systemObject['RunId'] = Split-Path -Path $RunFolder -Leaf

            $modulePropertyOrder = @('ActiveProfile', 'ProfileCount', 'RuleCount', 'EnabledRuleCount', 'FilterFailedCount', 'SddlFailedCount', 'PackageCount',
                'AccountCount', 'AccountUnresolvedCount', 'AppContainerCount', 'ProfilesDurationMs', 'RulesDurationMs', 'FiltersDurationMs', 'PackagesDurationMs', 'AccountsDurationMs')
            foreach ($name in $modulePropertyOrder) {
                # AppContainerCount is the row count of the list read above, the same value as in
                # summary.json, so a worker object without the list gives 0 and not $null.
                if ($name -eq 'AppContainerCount') {
                    $systemObject[$name] = $appContainerRows.Count
                }
                else {
                    $systemObject[$name] = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
                }
            }

            $systemObject['Errors'] = @($errors)
            $systemObject['Transport'] = $Transport
            $systemObject['RequestedComputerName'] = $RequestedComputerName
            $systemObject['Status'] = $status

            $systemJson = [PSCustomObject]$systemObject | ConvertTo-Json -Depth 6
            Write-FirewallInventoryTextFile -Path (Join-Path $outputFolder 'system.json') -Content $systemJson
        }
        catch {
            $errors += ("write system.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        $isElevatedValue = Get-FirewallInventorySafeProperty -InputObject $WorkerObject -Name 'IsElevated' -Default $null
        if ($null -ne $isElevatedValue) {
            $isElevatedValue = [Bool]$isElevatedValue
        }

        return ConvertTo-FirewallInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status $status -Transport $Transport `
            -OutputFolder $outputFolder -IsElevated $isElevatedValue `
            -ProfileCount $profileCount -RuleCount $ruleCount `
            -FilterFailedCount $filterFailedCount -SddlFailedCount $sddlFailedCount `
            -AccountCount $accountCount -AccountUnresolvedCount $accountUnresolvedCount `
            -Errors $errors
    }
    catch {
        $errors += ("unexpected error processing ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        return ConvertTo-FirewallInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status 'Failed' -Transport $Transport -Errors $errors
    }
}
#endregion
