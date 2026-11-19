<#PSScriptInfo

.DESCRIPTION Turns one worker object into a result row, and writes its per-computer folder

.VERSION 1.0.0

.GUID 6d2f90a4-1c37-4e85-b0a9-3f7e5c18d246

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Complete-SystemInventoryComputer
function Complete-SystemInventoryComputer {

    <#
    .SYNOPSIS
        Turns one worker object into a result row, and writes its per-computer folder.

    .DESCRIPTION
        Turns one worker object, or nothing plus the errors that explain why there is none, into
        a result row. When a worker object is present, it also writes the per-computer folder.
        computer.json is the worker's Computer object rebuilt here with the sections and keys in
        a fixed order, so the order holds after a remoting hop, and each of the seven tables is
        rebuilt the same way from one column list that json and csv share. A column that is an
        array stays an array in json at zero and one element, and is its elements joined with a
        vertical bar in csv.
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
        The object Get-SystemInventoryWorker's scriptblock returned, or $null when the target
        produced nothing.

    .PARAMETER ExtraErrors
        Errors already known before this call, folded into the row's Errors alongside anything
        found here. May be empty or $null.

    .PARAMETER OutputFormat
        Json, Csv or Both. Decides which file of the processors, memory, disks, volumes,
        adapters, hotfixes, features, accounts and appcontainers pairs is written. computer.json, system.json
        and summary.json have no csv twin and are always written. Defaults to Json.

    .NOTES
        FUNCTION: Complete-SystemInventoryComputer
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteSystem.Result
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
        return ConvertTo-SystemInventoryResultRow -ComputerName $RequestedComputerName -Status 'Failed' -Transport $Transport -Errors $errors
    }

    # Set before the try so the catch-all below always has a value to return, even when a later step here
    # throws: a computer that was reached still carries its ComputerId.
    $computerId = $null

    try {
        # A malformed worker object can carry $null or empty-string entries in Errors, dropped here so a
        # summary or a results row never shows a blank line for one.
        $workerErrors = @(Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'Errors' -Default @() | Where-Object { -not [String]::IsNullOrEmpty($_) })
        $errors += $workerErrors

        $computerId = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerId' -Default $null
        $readCount = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'ReadCount' -Default $null
        $readFailedCount = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'ReadFailedCount' -Default $null
        $hotfixCount = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'HotfixCount' -Default $null
        $accountCount = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'AccountCount' -Default $null
        $accountUnresolvedCount = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'AccountUnresolvedCount' -Default $null
        # A worker object from before the skipped count existed, or one that carries it as null, reports 0.
        $readSkippedCount = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'ReadSkippedCount' -Default 0
        if ($null -eq $readSkippedCount) {
            $readSkippedCount = 0
        }

        # Status is computed from the worker object's own counts and its own Errors list, never from anything
        # the host adds afterward. A $null count (a malformed or partial worker object) is not the same as a
        # verified 0, so Success also requires the failed count to be present.
        if (($null -eq $readCount) -or ([Int]$readCount -eq 0)) {
            $status = 'Failed'
        }
        elseif (($null -ne $readFailedCount) -and ([Int]$readFailedCount -eq 0) -and ($workerErrors.Count -eq 0)) {
            $status = 'Success'
        }
        else {
            $status = 'Partial'
        }

        $reportedName = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerName' -Default $RequestedComputerName
        if ([String]::IsNullOrWhiteSpace($reportedName)) {
            $reportedName = $RequestedComputerName
        }
        $reportedNameUpper = $reportedName.ToUpperInvariant()

        $buildNumber = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'CurrentBuild' -Default $null
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
        $outputFolder = Resolve-SystemInventoryUniqueFolder -Path (Join-Path $RunFolder $folderName)

        #region Column lists keys and columns of every file, named once for json and csv
        # The sections of computer.json in file order. A key listed in ArrayColumns is always an array in the
        # plain object. Every other key is a plain read of the property of the same name, null when the source
        # lacks it. PageFiles is not here: it is a list of objects and is built on its own.
        $sectionDefinitions = @(
            [PSCustomObject]@{
                Name         = 'ComputerSystem'
                Columns      = @('Name', 'DNSHostName', 'Domain', 'Workgroup', 'PartOfDomain', 'DomainRole', 'Manufacturer', 'Model', 'SystemFamily', 'SystemSKUNumber', 'SystemType', 'PCSystemType', 'HypervisorPresent', 'NumberOfProcessors', 'NumberOfLogicalProcessors', 'TotalPhysicalMemory', 'AutomaticManagedPagefile', 'BootupState', 'PrimaryOwnerName', 'Roles')
                ArrayColumns = @('Roles')
            }
            [PSCustomObject]@{
                Name         = 'OperatingSystem'
                Columns      = @('Caption', 'Version', 'BuildNumber', 'OSArchitecture', 'OperatingSystemSKU', 'ProductType', 'SuiteMask', 'OSLanguage', 'Locale', 'CountryCode', 'MUILanguages', 'SystemDrive', 'WindowsDirectory', 'SystemDirectory', 'BootDevice', 'SystemDevice', 'InstallDateUtc', 'LastBootUpTimeUtc', 'RegisteredUser', 'Organization', 'SerialNumber', 'TotalVisibleMemorySize', 'DataExecutionPrevention_Available', 'DataExecutionPrevention_SupportPolicy', 'PortableOperatingSystem', 'ProductName', 'CurrentBuild', 'UBR', 'DisplayVersion', 'ReleaseId', 'EditionID', 'InstallationType', 'BuildLabEx')
                ArrayColumns = @('MUILanguages')
            }
            [PSCustomObject]@{
                Name         = 'Bios'
                Columns      = @('Manufacturer', 'SMBIOSBIOSVersion', 'Version', 'BIOSVersion', 'ReleaseDateUtc', 'SerialNumber', 'SMBIOSMajorVersion', 'SMBIOSMinorVersion', 'SystemBiosMajorVersion', 'SystemBiosMinorVersion', 'EmbeddedControllerMajorVersion', 'EmbeddedControllerMinorVersion', 'SMBIOSPresent', 'PrimaryBIOS')
                ArrayColumns = @('BIOSVersion')
            }
            [PSCustomObject]@{
                Name         = 'BaseBoard'
                Columns      = @('Manufacturer', 'Product', 'Version', 'SerialNumber')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                Name         = 'Enclosure'
                Columns      = @('Manufacturer', 'Model', 'Version', 'SerialNumber', 'SMBIOSAssetTag', 'ChassisTypes', 'SecurityStatus', 'LockPresent')
                ArrayColumns = @('ChassisTypes')
            }
            [PSCustomObject]@{
                Name         = 'Product'
                Columns      = @('Vendor', 'Name', 'Version', 'IdentifyingNumber', 'UUID', 'SKUNumber')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                Name         = 'Firmware'
                Columns      = @('SecureBoot', 'SecureBootSupported', 'UEFISecureBootEnabled', 'BootDiskPartitionStyle')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                Name         = 'Tpm'
                Columns      = @('IsActivated_InitialValue', 'IsEnabled_InitialValue', 'IsOwned_InitialValue', 'ManufacturerId', 'ManufacturerIdTxt', 'ManufacturerVersion', 'ManufacturerVersionFull20', 'ManufacturerVersionInfo', 'PhysicalPresenceVersionInfo', 'SpecVersion')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                Name         = 'DeviceGuard'
                Columns      = @('AvailableSecurityProperties', 'RequiredSecurityProperties', 'SecurityServicesConfigured', 'SecurityServicesRunning', 'SecurityFeaturesEnabled', 'CodeIntegrityPolicyEnforcementStatus', 'UsermodeCodeIntegrityPolicyEnforcementStatus', 'VirtualizationBasedSecurityStatus', 'VirtualMachineIsolation', 'VirtualMachineIsolationProperties', 'SmmIsolationLevel', 'Version')
                ArrayColumns = @('AvailableSecurityProperties', 'RequiredSecurityProperties', 'SecurityServicesConfigured', 'SecurityServicesRunning', 'SecurityFeaturesEnabled', 'VirtualMachineIsolationProperties')
            }
            [PSCustomObject]@{
                Name         = 'TimeZone'
                Columns      = @('StandardName', 'DaylightName', 'Caption', 'Bias', 'DaylightBias')
                ArrayColumns = @()
            }
        )
        $pageFileColumns = @('Name', 'AllocatedBaseSize', 'TempPageFile', 'InitialSize', 'MaximumSize')
        $domainColumns = @('PartOfDomain', 'Domain', 'Workgroup', 'DomainRole', 'MachineSid', 'DomainSid', 'ComputerAccountSid', 'DomainNetbiosName')

        # The seven tables in file order. Columns is shared by the json and the csv file of a table, and
        # ArrayColumns names the columns that hold a list.
        $tableDefinitions = @(
            [PSCustomObject]@{
                File         = 'processors'
                Source       = 'Processors'
                Columns      = @('DeviceID', 'SocketDesignation', 'Name', 'Manufacturer', 'Description', 'ProcessorId', 'Architecture', 'Family', 'Revision', 'NumberOfCores', 'NumberOfEnabledCore', 'NumberOfLogicalProcessors', 'ThreadCount', 'MaxClockSpeed', 'AddressWidth', 'DataWidth', 'L2CacheSize', 'L3CacheSize', 'VirtualizationFirmwareEnabled', 'SecondLevelAddressTranslationExtensions', 'VMMonitorModeExtensions', 'PartNumber', 'SerialNumber', 'AssetTag')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                File         = 'memory'
                Source       = 'Memory'
                Columns      = @('Tag', 'BankLabel', 'DeviceLocator', 'Manufacturer', 'PartNumber', 'SerialNumber', 'Capacity', 'Speed', 'ConfiguredClockSpeed', 'FormFactor', 'MemoryType', 'SMBIOSMemoryType', 'TypeDetail', 'DataWidth', 'TotalWidth')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                File         = 'disks'
                Source       = 'Disks'
                Columns      = @('Index', 'DeviceID', 'Model', 'SerialNumber', 'FirmwareRevision', 'InterfaceType', 'MediaType', 'Size', 'Partitions', 'BytesPerSector', 'PNPDeviceID', 'Signature', 'PartitionStyle', 'BusType', 'IsBoot', 'IsSystem', 'IsOffline', 'IsReadOnly', 'HealthStatus', 'OperationalStatus', 'UniqueId', 'Guid', 'PhysicalMediaType', 'SpindleSpeed', 'PhysicalSectorSize', 'LogicalSectorSize')
                ArrayColumns = @('OperationalStatus')
            }
            [PSCustomObject]@{
                File         = 'volumes'
                Source       = 'Volumes'
                Columns      = @('DeviceID', 'Name', 'DriveLetter', 'Label', 'FileSystem', 'DriveType', 'Capacity', 'FreeSpace', 'BlockSize', 'BootVolume', 'SystemVolume', 'PageFilePresent', 'Compressed', 'IndexingEnabled', 'Automount', 'SerialNumber')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                File         = 'adapters'
                Source       = 'Adapters'
                Columns      = @('Index', 'InterfaceIndex', 'NetConnectionID', 'Name', 'Description', 'Manufacturer', 'AdapterType', 'MACAddress', 'PhysicalAdapter', 'NetEnabled', 'NetConnectionStatus', 'Speed', 'GUID', 'PNPDeviceID', 'ServiceName', 'IPEnabled', 'DHCPEnabled', 'DHCPServer', 'IPAddress', 'IPSubnet', 'DefaultIPGateway', 'DNSServerSearchOrder', 'DNSDomain', 'DNSDomainSuffixSearchOrder', 'FullDNSRegistrationEnabled', 'DomainDNSRegistrationEnabled', 'WINSPrimaryServer', 'WINSSecondaryServer', 'TcpipNetbiosOptions')
                ArrayColumns = @('IPAddress', 'IPSubnet', 'DefaultIPGateway', 'DNSServerSearchOrder', 'DNSDomainSuffixSearchOrder')
            }
            [PSCustomObject]@{
                File         = 'hotfixes'
                Source       = 'Hotfixes'
                Columns      = @('HotFixID', 'Description', 'Caption', 'InstalledOn', 'InstalledOnDate', 'InstalledBy', 'InstalledBySid', 'ServicePackInEffect', 'FixComments')
                ArrayColumns = @()
            }
            [PSCustomObject]@{
                File         = 'features'
                Source       = 'Features'
                Columns      = @('Source', 'Name', 'Caption', 'InstallState', 'DismState', 'Id', 'ParentId')
                ArrayColumns = @()
            }
        )

        $accountColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'References', 'Error')
        $accountArrayColumns = @('References')
        $accountCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'Error')

        $appContainerColumns = @('Token', 'Kind', 'Sid', 'Name', 'ReferenceCount', 'References')
        $appContainerArrayColumns = @('References')
        $appContainerCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'ReferenceCount')
        #endregion

        #region Plain rows rebuilt from the worker object
        # One source object (live, or a property bag after a remoting hop) into one plain ordered object. Every
        # array column that holds a value is rebuilt as an array: a single value becomes a one-element array,
        # an ArrayList or an array keeps its elements, and a null element is dropped. A $null stays $null,
        # because the worker leaves a section or a column null when its read failed or found nothing, and that
        # is not the same as an empty array.
        $toPlainRow = {
            param($Source, $Columns, $ArrayColumns)
            $plain = [ordered]@{}
            # The property collection of the source is taken once per row, not once per column.
            $sourceProperties = $Source.PSObject.Properties
            foreach ($column in $Columns) {
                # Read straight from PSObject.Properties, not through Get-SystemInventorySafeProperty: a
                # function that returns an empty array delivers nothing, so the caller would see $null and an
                # empty array could never be told from an absent value.
                $value = $null
                $property = $sourceProperties[$column]
                if ($null -ne $property) {
                    $value = $property.Value
                }
                if (($null -ne $value) -and ($ArrayColumns -contains $column)) {
                    $items = [System.Collections.Generic.List[Object]]::new()
                    foreach ($item in @($value)) {
                        if ($null -ne $item) {
                            [Void]$items.Add($item)
                        }
                    }
                    $plain[$column] = $items.ToArray()
                }
                else {
                    $plain[$column] = $value
                }
            }
            return [PSCustomObject]$plain
        }

        $computerObject = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'Computer' -Default $null
        $computerProperties = $null
        if ($null -ne $computerObject) {
            $computerProperties = $computerObject.PSObject.Properties
        }

        # The sections in the fixed order of computer.json. A section the worker returned as null, or that the
        # object lacks, stays null.
        $computerJsonObject = [ordered]@{}
        foreach ($definition in $sectionDefinitions) {
            $sectionSource = $null
            if ($null -ne $computerProperties) {
                $sectionProperty = $computerProperties[$definition.Name]
                if ($null -ne $sectionProperty) {
                    $sectionSource = $sectionProperty.Value
                }
            }
            if ($null -eq $sectionSource) {
                $computerJsonObject[$definition.Name] = $null
            }
            else {
                $computerJsonObject[$definition.Name] = & $toPlainRow $sectionSource $definition.Columns $definition.ArrayColumns
            }
        }

        # PageFiles is always an array, empty when the worker returned none.
        $pageFileList = [System.Collections.Generic.List[Object]]::new()
        if ($null -ne $computerProperties) {
            $pageFileProperty = $computerProperties['PageFiles']
            if (($null -ne $pageFileProperty) -and ($null -ne $pageFileProperty.Value)) {
                foreach ($pageFile in @($pageFileProperty.Value)) {
                    if ($null -ne $pageFile) {
                        [Void]$pageFileList.Add((& $toPlainRow $pageFile $pageFileColumns @()))
                    }
                }
            }
        }
        $computerJsonObject['PageFiles'] = $pageFileList.ToArray()

        $domainSource = $null
        if ($null -ne $computerProperties) {
            $domainProperty = $computerProperties['Domain']
            if ($null -ne $domainProperty) {
                $domainSource = $domainProperty.Value
            }
        }
        if ($null -eq $domainSource) {
            $computerJsonObject['Domain'] = $null
        }
        else {
            $computerJsonObject['Domain'] = & $toPlainRow $domainSource $domainColumns @()
        }

        # Each table and the accounts as a plain array of rows, keyed by file name. A generic list handed on
        # as an array: growing an array with += is quadratic.
        $workerProperties = $WorkerObject.PSObject.Properties
        $tableRows = @{}
        foreach ($definition in $tableDefinitions) {
            $rowList = [System.Collections.Generic.List[Object]]::new()
            $tableProperty = $workerProperties[$definition.Source]
            if (($null -ne $tableProperty) -and ($null -ne $tableProperty.Value)) {
                foreach ($item in @($tableProperty.Value)) {
                    if ($null -ne $item) {
                        [Void]$rowList.Add((& $toPlainRow $item $definition.Columns $definition.ArrayColumns))
                    }
                }
            }
            $tableRows[$definition.File] = $rowList.ToArray()
        }

        $accountList = [System.Collections.Generic.List[Object]]::new()
        $accountProperty = $workerProperties['Accounts']
        if (($null -ne $accountProperty) -and ($null -ne $accountProperty.Value)) {
            foreach ($item in @($accountProperty.Value)) {
                if ($null -ne $item) {
                    [Void]$accountList.Add((& $toPlainRow $item $accountColumns $accountArrayColumns))
                }
            }
        }
        $accountRows = $accountList.ToArray()

        # A worker object without the list (an older worker) gives an empty list and a count of 0.
        $appContainerList = [System.Collections.Generic.List[Object]]::new()
        $appContainerProperty = $workerProperties['AppContainers']
        if (($null -ne $appContainerProperty) -and ($null -ne $appContainerProperty.Value)) {
            foreach ($item in @($appContainerProperty.Value)) {
                if ($null -ne $item) {
                    [Void]$appContainerList.Add((& $toPlainRow $item $appContainerColumns $appContainerArrayColumns))
                }
            }
        }
        $appContainerRows = $appContainerList.ToArray()

        $readFailedItems = @()
        $readFailedProperty = $workerProperties['ReadFailedItems']
        if (($null -ne $readFailedProperty) -and ($null -ne $readFailedProperty.Value)) {
            $readFailedItems = @($readFailedProperty.Value | Where-Object { $null -ne $_ })
        }
        $absentItems = @()
        $absentProperty = $workerProperties['AbsentItems']
        if (($null -ne $absentProperty) -and ($null -ne $absentProperty.Value)) {
            $absentItems = @($absentProperty.Value | Where-Object { $null -ne $_ })
        }
        #endregion

        #region Files computer.json and the nine pairs
        try {
            $computerJson = [PSCustomObject]$computerJsonObject | ConvertTo-Json -Depth 6
            Write-SystemInventoryTextFile -Path (Join-Path $outputFolder 'computer.json') -Content $computerJson
        }
        catch {
            $errors += ("write computer.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        foreach ($definition in $tableDefinitions) {
            $fileRows = $tableRows[$definition.File]

            if ($writeJson) {
                try {
                    # -InputObject @($rows), not a pipe, so an empty array still serialises to [] and a
                    # one-element array still serialises to a one-element array, rather than collapsing to a
                    # bare object.
                    $tableJson = ConvertTo-Json -InputObject @($fileRows) -Depth 4
                    Write-SystemInventoryTextFile -Path (Join-Path $outputFolder "$($definition.File).json") -Content $tableJson
                }
                catch {
                    $errors += ("write $($definition.File).json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
                }
            }

            if ($writeCsv) {
                try {
                    $csvList = [System.Collections.Generic.List[Object]]::new()
                    foreach ($fileRow in $fileRows) {
                        [Void]$csvList.Add((ConvertTo-SystemInventoryCsvRow -Row $fileRow -Column $definition.Columns))
                    }
                    Write-SystemInventoryCsvFile -Row $csvList.ToArray() -Path (Join-Path $outputFolder "$($definition.File).csv") -Column $definition.Columns
                }
                catch {
                    $errors += ("write $($definition.File).csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
                }
            }
        }

        if ($writeJson) {
            try {
                $accountsJson = ConvertTo-Json -InputObject @($accountRows) -Depth 4
                Write-SystemInventoryTextFile -Path (Join-Path $outputFolder 'accounts.json') -Content $accountsJson
            }
            catch {
                $errors += ("write accounts.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $accountCsvRows = @($accountRows | Select-Object -Property $accountCsvColumns)
                Write-SystemInventoryCsvFile -Row $accountCsvRows -Path (Join-Path $outputFolder 'accounts.csv') -Column $accountCsvColumns
            }
            catch {
                $errors += ("write accounts.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeJson) {
            try {
                $appContainersJson = ConvertTo-Json -InputObject @($appContainerRows) -Depth 4
                Write-SystemInventoryTextFile -Path (Join-Path $outputFolder 'appcontainers.json') -Content $appContainersJson
            }
            catch {
                $errors += ("write appcontainers.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }

        if ($writeCsv) {
            try {
                $appContainerCsvRows = @($appContainerRows | Select-Object -Property $appContainerCsvColumns)
                Write-SystemInventoryCsvFile -Row $appContainerCsvRows -Path (Join-Path $outputFolder 'appcontainers.csv') -Column $appContainerCsvColumns
            }
            catch {
                $errors += ("write appcontainers.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
            }
        }
        #endregion

        #region Files summary.json and system.json
        try {
            # EnabledFeatureCount: the optional features that are enabled and every server feature, since that
            # class lists installed roles and features only. An optional feature is enabled when the class says
            # so (InstallState 1), or when the class has no row for it and DISM says Enabled. The two DISM counts
            # are null when the DISM list did not come back, because no row could carry its state then.
            # A skipped read returned nothing either, and only the DISM read can be skipped.
            $dismSkipped = (($null -ne $readSkippedCount) -and ([Int]$readSkippedCount -gt 0))
            $dismReturned = (($readFailedItems -notcontains 'DismFeatures') -and ($absentItems -notcontains 'DismFeatures') -and (-not $dismSkipped))
            $enabledFeatureCount = 0
            $payloadRemovedFeatureCount = $null
            $dismOnlyFeatureCount = $null
            if ($dismReturned) {
                $payloadRemovedFeatureCount = 0
                $dismOnlyFeatureCount = 0
            }
            foreach ($featureRow in $tableRows['features']) {
                if ($featureRow.Source -eq 'ServerFeature') {
                    $enabledFeatureCount++
                    continue
                }
                if ($featureRow.Source -ne 'OptionalFeature') {
                    continue
                }
                if ($null -ne $featureRow.InstallState) {
                    if ($featureRow.InstallState -eq 1) {
                        $enabledFeatureCount++
                    }
                }
                elseif ($null -ne $featureRow.DismState) {
                    if ($featureRow.DismState -eq 'Enabled') {
                        $enabledFeatureCount++
                    }
                    if ($dismReturned) {
                        $dismOnlyFeatureCount++
                    }
                }
                if ($dismReturned -and ($featureRow.DismState -eq 'DisabledWithPayloadRemoved')) {
                    $payloadRemovedFeatureCount++
                }
            }

            # One value of a section of computer.json, null when the section itself is null. The section
            # objects hold every key of their column list, so the read cannot miss.
            $sectionValue = {
                param($Section, $Key)
                if ($null -eq $Section) {
                    return $null
                }
                return $Section.$Key
            }

            $computerSystemSection = $computerJsonObject['ComputerSystem']
            $biosSection = $computerJsonObject['Bios']
            $operatingSystemSection = $computerJsonObject['OperatingSystem']
            $firmwareSection = $computerJsonObject['Firmware']

            # True when the Tpm read returned an instance, false when it returned none or was absent, null when
            # it failed.
            $tpmPresent = $false
            if ($null -ne $computerJsonObject['Tpm']) {
                $tpmPresent = $true
            }
            elseif ($readFailedItems -contains 'Tpm') {
                $tpmPresent = $null
            }

            $summaryObject = [PSCustomObject]@{
                Manufacturer               = & $sectionValue $computerSystemSection 'Manufacturer'
                Model                      = & $sectionValue $computerSystemSection 'Model'
                SerialNumber               = & $sectionValue $biosSection 'SerialNumber'
                TotalPhysicalMemory        = & $sectionValue $computerSystemSection 'TotalPhysicalMemory'
                SecureBoot                 = & $sectionValue $firmwareSection 'SecureBoot'
                TpmPresent                 = $tpmPresent
                LastBootUpTimeUtc          = & $sectionValue $operatingSystemSection 'LastBootUpTimeUtc'
                ReadCount                  = $readCount
                ReadFailedCount            = $readFailedCount
                ReadSkippedCount           = $readSkippedCount
                ReadFailedItems            = $readFailedItems
                AbsentItems                = $absentItems
                ProcessorCount             = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'ProcessorCount' -Default $null
                MemoryModuleCount          = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'MemoryModuleCount' -Default $null
                DiskCount                  = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'DiskCount' -Default $null
                VolumeCount                = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'VolumeCount' -Default $null
                AdapterCount               = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'AdapterCount' -Default $null
                HotfixCount                = $hotfixCount
                FeatureCount               = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'FeatureCount' -Default $null
                EnabledFeatureCount        = $enabledFeatureCount
                PayloadRemovedFeatureCount = $payloadRemovedFeatureCount
                DismOnlyFeatureCount       = $dismOnlyFeatureCount
                ComputerDurationMs         = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerDurationMs' -Default $null
                HardwareDurationMs         = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'HardwareDurationMs' -Default $null
                HotfixesDurationMs         = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'HotfixesDurationMs' -Default $null
                FeaturesDurationMs         = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'FeaturesDurationMs' -Default $null
                AccountsDurationMs         = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'AccountsDurationMs' -Default $null
                AccountCount               = $accountCount
                AccountUnresolvedCount     = $accountUnresolvedCount
                AccountUnresolvedTokens    = @($accountRows | Where-Object { $_.Status -eq 'NotFound' } | ForEach-Object { $_.Token })
                AppContainerCount          = $appContainerRows.Count
            }
            $summaryJson = $summaryObject | ConvertTo-Json -Depth 6
            Write-SystemInventoryTextFile -Path (Join-Path $outputFolder 'summary.json') -Content $summaryJson
        }
        catch {
            $errors += ("write summary.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            # Built as an explicit ordered list of names, not by enumerating
            # $WorkerObject.PSObject.Properties, so the key order of system.json is fixed regardless of how a
            # worker object happened to be built (a live worker return or a PSSerializer round trip).
            $systemObject = [ordered]@{}
            $identityPropertyOrder = @('ComputerName', 'DnsHostName', 'Domain', 'OSCaption', 'OSVersion', 'CurrentBuild', 'UBR',
                'DisplayVersion', 'EditionID', 'InstallationType', 'Culture', 'TimeZoneId', 'PSVersion', 'CollectedBy',
                'PartOfDomain', 'IsElevated', 'DomainRole', 'CollectedUtc', 'ComputerId', 'MachineGuid',
                'MachineSid', 'DomainSid', 'ComputerAccountSid', 'DomainNetbiosName')
            foreach ($name in $identityPropertyOrder) {
                $systemObject[$name] = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Collector'] = 'RemoteSystem'
            $systemObject['CollectorVersion'] = $MyInvocation.MyCommand.Module.Version.ToString()
            $systemObject['RunId'] = Split-Path -Path $RunFolder -Leaf

            $modulePropertyOrder = @('ReadCount', 'ReadFailedCount', 'ReadSkippedCount', 'ProcessorCount', 'MemoryModuleCount', 'DiskCount', 'VolumeCount',
                'AdapterCount', 'HotfixCount', 'FeatureCount', 'AccountCount', 'AccountUnresolvedCount', 'AppContainerCount', 'ComputerDurationMs',
                'HardwareDurationMs', 'HotfixesDurationMs', 'FeaturesDurationMs', 'AccountsDurationMs')
            foreach ($name in $modulePropertyOrder) {
                # AppContainerCount is the row count of the list read above, the same value as in
                # summary.json, so a worker object without the list gives 0 and not $null. The skipped
                # count is the value resolved above for the same reason.
                if ($name -eq 'AppContainerCount') {
                    $systemObject[$name] = $appContainerRows.Count
                }
                elseif ($name -eq 'ReadSkippedCount') {
                    $systemObject[$name] = $readSkippedCount
                }
                else {
                    $systemObject[$name] = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
                }
            }

            $systemObject['Errors'] = @($errors)
            $systemObject['Transport'] = $Transport
            $systemObject['RequestedComputerName'] = $RequestedComputerName
            $systemObject['Status'] = $status

            $systemJson = [PSCustomObject]$systemObject | ConvertTo-Json -Depth 6
            Write-SystemInventoryTextFile -Path (Join-Path $outputFolder 'system.json') -Content $systemJson
        }
        catch {
            $errors += ("write system.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }
        #endregion

        $isElevatedValue = Get-SystemInventorySafeProperty -InputObject $WorkerObject -Name 'IsElevated' -Default $null
        if ($null -ne $isElevatedValue) {
            $isElevatedValue = [Bool]$isElevatedValue
        }

        return ConvertTo-SystemInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status $status -Transport $Transport `
            -OutputFolder $outputFolder -IsElevated $isElevatedValue `
            -ReadCount $readCount -ReadFailedCount $readFailedCount -HotfixCount $hotfixCount `
            -AccountCount $accountCount -AccountUnresolvedCount $accountUnresolvedCount `
            -Errors $errors
    }
    catch {
        $errors += ("unexpected error processing ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        return ConvertTo-SystemInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status 'Failed' -Transport $Transport -Errors $errors
    }
}
#endregion
