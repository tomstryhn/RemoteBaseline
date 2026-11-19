<#PSScriptInfo

.DESCRIPTION Returns the self-contained scriptblock that collects the system inventory on a target

.VERSION 1.0.0

.GUID 1658ca11-8a6e-47b3-8f51-5acef6750bd2

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-SystemInventoryWorker
function Get-SystemInventoryWorker {

    <#
    .SYNOPSIS
        Returns the self-contained scriptblock that collects the system inventory on a target.

    .DESCRIPTION
        The scriptblock this function returns is what actually runs on the target, local or
        remote, so it uses no module function, no module variable and no using: expression. It
        takes -SkipSidReference and -SkipDismFeatures and depends on nothing else from the
        caller's session. It reads the computer system, operating system, firmware, TPM, device
        guard, time zone, page file, domain, processor, memory, disk, volume, network adapter,
        installed update and Windows feature descriptions (the feature class and, beside it, the
        DISM feature list, which needs elevation), resolves the account that installed each
        update (an application package SID or a capability SID is no account, so it is classed
        from its text into AppContainers and never looked up), and returns one flat object
        holding all of it. Every read goes through a cmdlet and ends as read, absent (the source
        does not exist on this computer), failed or, for the DISM list with
        -SkipDismFeatures, skipped. It also reads four SID reference
        values: MachineSid from the local account with RID 500 (Win32_UserAccount filtered to the
        computer's own name, so a domain controller has none and keeps null), and, on a
        domain-joined computer only, DomainSid, ComputerAccountSid and DomainNetbiosName from the
        computer's own domain account through an account lookup. No Active Directory module and
        no LDAP is used. It never throws: every step is wrapped in its own try/catch and appends to
        an Errors list instead. It writes no file of its own on the target. The DISM feature list
        makes Windows append to its own dism.log, and -SkipDismFeatures leaves it out.
        Invoke-SystemInventoryLocal calls it directly for the local computer.
        Invoke-SystemInventoryRemote passes it to Invoke-Command for every remote target.

    .PARAMETER SkipSidReference
        A parameter of the returned scriptblock, not of this function. It is the first parameter
        because the remote call passes it positionally. When true, the SID reference of the
        identity columns is not read and those four values are null with no error. The Domain
        section of the computer object always holds the four SIDs, so with this switch that step
        reads them itself and names its errors with a Domain prefix. Defaults to false, for tests
        only. Every real caller passes it.

    .PARAMETER SkipDismFeatures
        A parameter of the returned scriptblock, not of this function. It is the second parameter
        because the remote call passes it positionally after SkipSidReference. When true, the
        DISM feature list is not read: the read is recorded as Skipped, which is no error and no
        failed read, DismState is null on every feature row, and the unelevated line no longer
        names the DISM feature list. The ReadSkippedCount of the return object is 1. Defaults to
        false, for tests only. Every real caller passes it.

    .NOTES
        FUNCTION: Get-SystemInventoryWorker
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock
    #>

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'The worker runs on Windows PowerShell 5.1 on the target, where Get-WindowsOptionalFeature is a cmdlet of the Dism module. The compatibility profile of PowerShell 7 does not list it, and the worker checks for the command before it calls it.')]
    param()

    return {
        # Both are positional: Invoke-Command passes its ArgumentList by position, so a parameter added
        # before one of them would receive the wrong value.
        param(
            [Bool]$SkipSidReference = $false,

            [Bool]$SkipDismFeatures = $false
        )

        # Off here, not only in the public function, so the worker behaves the same in-process as on a remote
        # target, where strict mode is off by default.
        Set-StrictMode -Off

        #region ConvertTo-SystemInventoryPlainValue
        function ConvertTo-SystemInventoryPlainValue {
            <#
            .SYNOPSIS
                Turns one CIM or registry value into plain data.
            #>
            param(
                [AllowNull()]
                $Value
            )

            if ($null -eq $Value) {
                return $null
            }
            if (($Value -is [Bool]) -or ($Value -is [String])) {
                return $Value
            }
            if ($Value -is [DateTime]) {
                # A Local value converts as local time, an Utc value stays, so one instant gives one text.
                return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            if ($Value -is [DateTimeOffset]) {
                return $Value.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            if (($Value -is [Int64]) -or ($Value -is [Int32]) -or ($Value -is [Int16]) -or ($Value -is [SByte]) -or ($Value -is [Byte]) -or ($Value -is [UInt16]) -or ($Value -is [UInt32])) {
                return [Int64]$Value
            }
            if ($Value -is [UInt64]) {
                # Int64 whenever it fits, UInt64 above that, so a large counter is never lost.
                if ([UInt64]$Value -le [UInt64][Int64]::MaxValue) {
                    return [Int64]$Value
                }
                return [UInt64]$Value
            }
            if (($Value -is [Double]) -or ($Value -is [Single]) -or ($Value -is [Decimal])) {
                return $Value
            }
            return [String]$Value
        }
        #endregion

        #region ConvertTo-SystemInventoryRowData
        function ConvertTo-SystemInventoryRowData {
            <#
            .SYNOPSIS
                Reads the listed properties of one instance into an ordered table of plain data.

            .DESCRIPTION
                A key is either a name, or Output=Source when the column is named differently from the
                property. A CIM instance is read through its own property list, because PowerShell type data
                can lay a script property of the same name over a class property and turn the value into
                another one (a parsed date, a name for a number). Any other object is read through
                PSObject.Properties. A property the instance lacks, and an instance that is null, give null
                for the key. A key named in ArrayKeys (or a property that holds an array) is always an array
                once the property exists: null gives an empty array, a scalar gives one element and a null
                element is dropped. Pass -Row to add columns to a table that already holds some.
            #>
            param(
                [AllowNull()]
                $Instance,

                [Parameter(Mandatory)]
                [String[]]$Keys,

                [String[]]$ArrayKeys = @(),

                [System.Collections.Specialized.OrderedDictionary]$Row
            )

            if ($null -eq $Row) {
                $Row = [ordered]@{}
            }

            # The property collection is taken once per instance: each lookup on a CIM instance is slow.
            # The type is matched by name so the check holds on a target where the CIM assembly is not loaded
            # yet, and only the exact CIM instance type counts.
            $properties = $null
            if ($null -ne $Instance) {
                if ($Instance.GetType().FullName -eq 'Microsoft.Management.Infrastructure.CimInstance') {
                    $properties = $Instance.PSBase.CimInstanceProperties
                }
                else {
                    $properties = $Instance.PSObject.Properties
                }
            }

            foreach ($key in $Keys) {
                $outputName = $key
                $sourceName = $key
                $separatorIndex = $key.IndexOf('=')
                if ($separatorIndex -gt 0) {
                    $outputName = $key.Substring(0, $separatorIndex)
                    $sourceName = $key.Substring($separatorIndex + 1)
                }

                $property = $null
                if ($null -ne $properties) {
                    $property = $properties[$sourceName]
                }
                if ($null -eq $property) {
                    $Row[$outputName] = $null
                    continue
                }

                $value = $property.Value
                if (($ArrayKeys -contains $outputName) -or ($value -is [Array])) {
                    # Stored into the table, never returned, so an empty or one-element array is not unrolled.
                    $items = [System.Collections.Generic.List[Object]]::new()
                    if ($null -ne $value) {
                        foreach ($element in @($value)) {
                            if ($null -ne $element) {
                                [Void]$items.Add((ConvertTo-SystemInventoryPlainValue -Value $element))
                            }
                        }
                    }
                    $Row[$outputName] = $items.ToArray()
                }
                else {
                    $Row[$outputName] = ConvertTo-SystemInventoryPlainValue -Value $value
                }
            }

            return $Row
        }
        #endregion

        #region Invoke-SystemInventoryRead
        function Invoke-SystemInventoryRead {
            <#
            .SYNOPSIS
                Runs one read and classifies its outcome as Read, Absent or Failed.

            .DESCRIPTION
                Read means the read returned, with or without instances. Absent means the source does not exist
                on this computer: a CIM class or namespace that is invalid, a registry key that does not exist,
                firmware that is not UEFI, firmware that has no Secure Boot variable (an error id that starts
                with VarNotFoundException), or a required command that is not there. Anything else that throws
                is Failed and adds a line named after the read to the shared error list. The outcome is also
                stored in the shared table under the read name. The result carries the error id of the failure,
                null when the read did not throw. The instances come back as an array without null elements.
            #>
            param(
                [Parameter(Mandatory)]
                [String]$Name,

                [Parameter(Mandatory)]
                [ScriptBlock]$ReadScript,

                [Parameter(Mandatory)]
                [Hashtable]$State,

                [String]$RequiresCommand
            )

            $outcome = 'Read'
            $cause = $null
            $errorId = $null
            $items = [System.Collections.Generic.List[Object]]::new()

            try {
                # Ignore, not SilentlyContinue: a missing command is an answer here and leaves no error record.
                if ((-not [String]::IsNullOrEmpty($RequiresCommand)) -and ($null -eq (Get-Command -Name $RequiresCommand -ErrorAction Ignore))) {
                    $outcome = 'Absent'
                }
                else {
                    foreach ($item in @(& $ReadScript)) {
                        if ($null -ne $item) {
                            [Void]$items.Add($item)
                        }
                    }
                }
            }
            catch {
                $outcome = 'Failed'
                $cause = $_.Exception
                $failureMessage = $_.Exception.Message
                $errorId = [String]$_.FullyQualifiedErrorId

                # Firmware that is UEFI but holds no Secure Boot variable fails with an exception of the
                # cmdlet's own type, so the error id is the only thing that names it.
                if ($errorId.StartsWith('VarNotFoundException', [System.StringComparison]::Ordinal)) {
                    $outcome = 'Absent'
                }

                # The type is matched by name so the check holds on a target where the CIM assembly is not
                # loaded yet. The chain is walked in case a wrapper sits around the real exception.
                $cursor = $cause
                $depth = 0
                while (($null -ne $cursor) -and ($depth -lt 5)) {
                    $typeName = $cursor.GetType().FullName
                    if ($typeName -eq 'Microsoft.Management.Infrastructure.CimException') {
                        $nativeCode = $null
                        $codeProperty = $cursor.PSObject.Properties['NativeErrorCode']
                        if ($null -ne $codeProperty) {
                            $nativeCode = [String]$codeProperty.Value
                        }
                        if (($nativeCode -eq 'InvalidClass') -or ($nativeCode -eq 'InvalidNamespace')) {
                            $outcome = 'Absent'
                            $cause = $cursor
                        }
                    }
                    elseif (($cursor -is [System.Management.Automation.ItemNotFoundException]) -or ($cursor -is [System.PlatformNotSupportedException])) {
                        $outcome = 'Absent'
                        $cause = $cursor
                    }
                    $cursor = $cursor.InnerException
                    $depth++
                }

                if ($outcome -eq 'Failed') {
                    [Void]$State.Errors.Add("${Name}: $failureMessage")
                }
            }

            $State.Outcomes[$Name] = $outcome

            return [PSCustomObject]@{
                Name    = $Name
                Outcome = $outcome
                Cause   = $cause
                ErrorId = $errorId
                Items   = $items.ToArray()
            }
        }
        #endregion

        #region Get-SystemInventoryFirstItem
        function Get-SystemInventoryFirstItem {
            <#
            .SYNOPSIS
                Returns the first instance of a read, or null when the read gave none.
            #>
            param(
                [Parameter(Mandatory)]
                $Read
            )

            if ($Read.Items.Count -gt 0) {
                return $Read.Items[0]
            }
            return $null
        }
        #endregion

        $errors = @()

        # The shortfall line of an unelevated caller. It is named here, ahead of the identity step, because that
        # step is the family's shared code and holds no switch of this module. Without the DISM read the line
        # has no DISM part.
        $notElevatedLine = 'not elevated: the TPM, the Secure Boot state and the DISM feature list are not read'
        if ($SkipDismFeatures) {
            $notElevatedLine = 'not elevated: the TPM and the Secure Boot state are not read'
        }

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
        # with a shorter inventory and IsElevated as the only signal. The shortfall is named, which makes the
        # row Partial.
        if (-not $isElevated) {
            $errors += $notElevatedLine
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

        #region Read bookkeeping the shared error list and the outcome of every read
        # From here on every line goes into one list, so the order of the Errors follows the order of the steps.
        $errorList = [System.Collections.Generic.List[String]]::new()
        foreach ($errorLine in $errors) {
            [Void]$errorList.Add([String]$errorLine)
        }
        $state = @{
            Errors   = $errorList
            Outcomes = [System.Collections.Generic.Dictionary[String, String]]::new()
        }

        # The reads in their fixed order. The report lists failed and absent reads in this order,
        # whatever order the steps ran them in.
        $readNames = @('ComputerSystem', 'OperatingSystem', 'CurrentVersion', 'Bios', 'BaseBoard', 'Enclosure',
            'Product', 'SecureBoot', 'SecureBootState', 'Tpm', 'DeviceGuard', 'TimeZone', 'PageFileUsage',
            'PageFileSetting', 'Domain', 'Processors', 'Memory', 'DiskDrives', 'StorageDisks', 'PhysicalDisks',
            'Volumes', 'Adapters', 'AdapterConfigurations', 'Hotfixes', 'OptionalFeatures', 'DismFeatures',
            'ServerFeatures')
        #endregion

        #region Computer
        $stopwatchComputer = [System.Diagnostics.Stopwatch]::StartNew()

        $readComputerSystem = Invoke-SystemInventoryRead -Name 'ComputerSystem' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop -Verbose:$false
        }
        $readOperatingSystem = Invoke-SystemInventoryRead -Name 'OperatingSystem' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop -Verbose:$false
        }
        $readCurrentVersion = Invoke-SystemInventoryRead -Name 'CurrentVersion' -State $state -ReadScript {
            Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        }
        $readBios = Invoke-SystemInventoryRead -Name 'Bios' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop -Verbose:$false
        }
        $readBaseBoard = Invoke-SystemInventoryRead -Name 'BaseBoard' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop -Verbose:$false
        }
        $readEnclosure = Invoke-SystemInventoryRead -Name 'Enclosure' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop -Verbose:$false
        }
        $readProduct = Invoke-SystemInventoryRead -Name 'Product' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop -Verbose:$false
        }
        $readSecureBoot = Invoke-SystemInventoryRead -Name 'SecureBoot' -State $state -RequiresCommand 'Confirm-SecureBootUEFI' -ReadScript {
            Confirm-SecureBootUEFI -ErrorAction Stop
        }
        $readSecureBootState = Invoke-SystemInventoryRead -Name 'SecureBootState' -State $state -ReadScript {
            Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction Stop
        }
        $readTpm = Invoke-SystemInventoryRead -Name 'Tpm' -State $state -ReadScript {
            Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop -Verbose:$false
        }
        $readDeviceGuard = Invoke-SystemInventoryRead -Name 'DeviceGuard' -State $state -ReadScript {
            Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop -Verbose:$false
        }
        $readTimeZone = Invoke-SystemInventoryRead -Name 'TimeZone' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_TimeZone -ErrorAction Stop -Verbose:$false
        }
        $readPageFileUsage = Invoke-SystemInventoryRead -Name 'PageFileUsage' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop -Verbose:$false
        }
        $readPageFileSetting = Invoke-SystemInventoryRead -Name 'PageFileSetting' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction Stop -Verbose:$false
        }

        # A section is null when its read failed, was absent or returned no instance, which is what the
        # first-instance helper gives for each of those.
        $computerSystemInstance = Get-SystemInventoryFirstItem -Read $readComputerSystem
        $computerSystemSection = $null
        if ($null -ne $computerSystemInstance) {
            $computerSystemSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $computerSystemInstance -ArrayKeys @('Roles') -Keys @(
                    'Name', 'DNSHostName', 'Domain', 'Workgroup', 'PartOfDomain', 'DomainRole', 'Manufacturer', 'Model',
                    'SystemFamily', 'SystemSKUNumber', 'SystemType', 'PCSystemType', 'HypervisorPresent',
                    'NumberOfProcessors', 'NumberOfLogicalProcessors', 'TotalPhysicalMemory',
                    'AutomaticManagedPagefile', 'BootupState', 'PrimaryOwnerName', 'Roles'))
        }

        # The section exists when either of its two reads gave something. The keys of the other read are null.
        $operatingSystemInstance = Get-SystemInventoryFirstItem -Read $readOperatingSystem
        $currentVersionInstance = Get-SystemInventoryFirstItem -Read $readCurrentVersion
        $operatingSystemSection = $null
        if (($null -ne $operatingSystemInstance) -or ($null -ne $currentVersionInstance)) {
            $operatingSystemRow = ConvertTo-SystemInventoryRowData -Instance $operatingSystemInstance -ArrayKeys @('MUILanguages') -Keys @(
                'Caption', 'Version', 'BuildNumber', 'OSArchitecture', 'OperatingSystemSKU', 'ProductType', 'SuiteMask',
                'OSLanguage', 'Locale', 'CountryCode', 'MUILanguages', 'SystemDrive', 'WindowsDirectory',
                'SystemDirectory', 'BootDevice', 'SystemDevice', 'InstallDateUtc=InstallDate',
                'LastBootUpTimeUtc=LastBootUpTime', 'RegisteredUser', 'Organization', 'SerialNumber',
                'TotalVisibleMemorySize', 'DataExecutionPrevention_Available',
                'DataExecutionPrevention_SupportPolicy', 'PortableOperatingSystem')
            $null = ConvertTo-SystemInventoryRowData -Instance $currentVersionInstance -Row $operatingSystemRow -Keys @(
                'ProductName', 'CurrentBuild', 'UBR', 'DisplayVersion', 'ReleaseId', 'EditionID', 'InstallationType',
                'BuildLabEx')
            $operatingSystemSection = [PSCustomObject]$operatingSystemRow
        }

        $biosSection = $null
        $biosInstance = Get-SystemInventoryFirstItem -Read $readBios
        if ($null -ne $biosInstance) {
            $biosSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $biosInstance -ArrayKeys @('BIOSVersion') -Keys @(
                    'Manufacturer', 'SMBIOSBIOSVersion', 'Version', 'BIOSVersion', 'ReleaseDateUtc=ReleaseDate',
                    'SerialNumber', 'SMBIOSMajorVersion', 'SMBIOSMinorVersion', 'SystemBiosMajorVersion',
                    'SystemBiosMinorVersion', 'EmbeddedControllerMajorVersion', 'EmbeddedControllerMinorVersion',
                    'SMBIOSPresent', 'PrimaryBIOS'))
        }

        $baseBoardSection = $null
        $baseBoardInstance = Get-SystemInventoryFirstItem -Read $readBaseBoard
        if ($null -ne $baseBoardInstance) {
            $baseBoardSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $baseBoardInstance -Keys @(
                    'Manufacturer', 'Product', 'Version', 'SerialNumber'))
        }

        $enclosureSection = $null
        $enclosureInstance = Get-SystemInventoryFirstItem -Read $readEnclosure
        if ($null -ne $enclosureInstance) {
            $enclosureSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $enclosureInstance -ArrayKeys @('ChassisTypes') -Keys @(
                    'Manufacturer', 'Model', 'Version', 'SerialNumber', 'SMBIOSAssetTag', 'ChassisTypes',
                    'SecurityStatus', 'LockPresent'))
        }

        $productSection = $null
        $productInstance = Get-SystemInventoryFirstItem -Read $readProduct
        if ($null -ne $productInstance) {
            $productSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $productInstance -Keys @(
                    'Vendor', 'Name', 'Version', 'IdentifyingNumber', 'UUID', 'SKUNumber'))
        }

        # SecureBoot is the cmdlet's boolean. SecureBootSupported is true when the cmdlet answered, false when
        # it reported firmware that is not UEFI or that has no Secure Boot variable, and null when the answer
        # is unknown (the command is not there, or the call failed). BootDiskPartitionStyle waits for the
        # disk reads of the hardware step.
        $secureBoot = $null
        $secureBootSupported = $null
        if ($readSecureBoot.Outcome -eq 'Read') {
            $secureBootSupported = $true
            $secureBootValue = Get-SystemInventoryFirstItem -Read $readSecureBoot
            if ($secureBootValue -is [Bool]) {
                $secureBoot = $secureBootValue
            }
        }
        elseif ($readSecureBoot.Outcome -eq 'Absent') {
            $noVariable = ([String]$readSecureBoot.ErrorId).StartsWith('VarNotFoundException', [System.StringComparison]::Ordinal)
            if (($readSecureBoot.Cause -is [System.PlatformNotSupportedException]) -or $noVariable) {
                $secureBootSupported = $false
            }
        }

        $uefiSecureBootEnabled = $null
        $secureBootStateInstance = Get-SystemInventoryFirstItem -Read $readSecureBootState
        if ($null -ne $secureBootStateInstance) {
            $secureBootStateRow = ConvertTo-SystemInventoryRowData -Instance $secureBootStateInstance -Keys @('UEFISecureBootEnabled')
            $uefiSecureBootEnabled = $secureBootStateRow['UEFISecureBootEnabled']
        }

        $firmwareRow = [ordered]@{
            SecureBoot             = $secureBoot
            SecureBootSupported    = $secureBootSupported
            UEFISecureBootEnabled  = $uefiSecureBootEnabled
            BootDiskPartitionStyle = $null
        }

        $tpmSection = $null
        $tpmInstance = Get-SystemInventoryFirstItem -Read $readTpm
        if ($null -ne $tpmInstance) {
            $tpmSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $tpmInstance -Keys @(
                    'IsActivated_InitialValue', 'IsEnabled_InitialValue', 'IsOwned_InitialValue', 'ManufacturerId',
                    'ManufacturerIdTxt', 'ManufacturerVersion', 'ManufacturerVersionFull20',
                    'ManufacturerVersionInfo', 'PhysicalPresenceVersionInfo', 'SpecVersion'))
        }

        $deviceGuardSection = $null
        $deviceGuardInstance = Get-SystemInventoryFirstItem -Read $readDeviceGuard
        if ($null -ne $deviceGuardInstance) {
            $deviceGuardArrayKeys = @('AvailableSecurityProperties', 'RequiredSecurityProperties', 'SecurityServicesConfigured',
                'SecurityServicesRunning', 'SecurityFeaturesEnabled', 'VirtualMachineIsolationProperties')
            $deviceGuardSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $deviceGuardInstance -ArrayKeys $deviceGuardArrayKeys -Keys @(
                    'AvailableSecurityProperties', 'RequiredSecurityProperties', 'SecurityServicesConfigured',
                    'SecurityServicesRunning', 'SecurityFeaturesEnabled', 'CodeIntegrityPolicyEnforcementStatus',
                    'UsermodeCodeIntegrityPolicyEnforcementStatus', 'VirtualizationBasedSecurityStatus',
                    'VirtualMachineIsolation', 'VirtualMachineIsolationProperties', 'SmmIsolationLevel', 'Version'))
        }

        $timeZoneSection = $null
        $timeZoneInstance = Get-SystemInventoryFirstItem -Read $readTimeZone
        if ($null -ne $timeZoneInstance) {
            $timeZoneSection = [PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $timeZoneInstance -Keys @(
                    'StandardName', 'DaylightName', 'Caption', 'Bias', 'DaylightBias'))
        }

        # One entry per page file in use. The setting of the same name adds the configured sizes, and a file
        # without one is system managed, which leaves both sizes null.
        $settingByName = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($setting in $readPageFileSetting.Items) {
            $settingName = [String]$setting.Name
            if ((-not [String]::IsNullOrEmpty($settingName)) -and (-not $settingByName.ContainsKey($settingName))) {
                $settingByName[$settingName] = $setting
            }
        }
        $pageFileList = [System.Collections.Generic.List[Object]]::new()
        foreach ($usage in $readPageFileUsage.Items) {
            $pageFileRow = ConvertTo-SystemInventoryRowData -Instance $usage -Keys @('Name', 'AllocatedBaseSize', 'TempPageFile')
            $matchedSetting = $null
            $usageName = [String]$usage.Name
            if ((-not [String]::IsNullOrEmpty($usageName)) -and $settingByName.ContainsKey($usageName)) {
                $matchedSetting = $settingByName[$usageName]
            }
            $null = ConvertTo-SystemInventoryRowData -Instance $matchedSetting -Row $pageFileRow -Keys @('InitialSize', 'MaximumSize')
            [Void]$pageFileList.Add([PSCustomObject]$pageFileRow)
        }
        $pageFileList.Sort( [Comparison[Object]] { param($A, $B) [String]::Compare($A.Name, $B.Name, [System.StringComparison]::OrdinalIgnoreCase) } )
        $pageFiles = $pageFileList.ToArray()
        #endregion

        #region Domain the SID values of the Domain section
        # With the SID reference of the identity step the four values are copied. With -SkipSidReference that
        # step left them null, so they are read here with the same rules and the errors carry a Domain prefix.
        $referenceMachineSid = $null
        $referenceDomainSid = $null
        $referenceComputerAccountSid = $null
        $referenceDomainNetbiosName = $null
        $domainReadFailed = $false

        if ($SkipSidReference) {
            try {
                $referenceAccounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter ('Domain = "{0}"' -f $env:COMPUTERNAME) -ErrorAction Stop -Verbose:$false)
                foreach ($referenceAccount in $referenceAccounts) {
                    if ([String]$referenceAccount.SID -match '^(S-1-5-21-\d+-\d+-\d+)-500$') {
                        $referenceMachineSid = $matches[1]
                        break
                    }
                }
            }
            catch {
                $domainReadFailed = $true
                [Void]$errorList.Add("Domain: MachineSid: $($_.Exception.Message)")
            }

            if ($partOfDomain) {
                $referenceAccountSidObject = $null
                try {
                    $referenceComputerAccount = New-Object System.Security.Principal.NTAccount(($domain + '\' + $env:COMPUTERNAME + '$'))
                    $referenceAccountSidObject = $referenceComputerAccount.Translate([System.Security.Principal.SecurityIdentifier])
                    $referenceComputerAccountSid = $referenceAccountSidObject.Value
                    $referenceDomainSid = $referenceAccountSidObject.AccountDomainSid.Value
                }
                catch {
                    $domainReadFailed = $true
                    $referenceAccountSidObject = $null
                    $referenceComputerAccountSid = $null
                    $referenceDomainSid = $null
                    [Void]$errorList.Add("Domain: DomainSid: $($_.Exception.GetBaseException().Message)")
                }

                if ($null -ne $referenceAccountSidObject) {
                    try {
                        $referenceAccountName = $referenceAccountSidObject.Translate([System.Security.Principal.NTAccount]).Value
                        $referenceSeparatorIndex = $referenceAccountName.IndexOf('\')
                        if ($referenceSeparatorIndex -gt 0) {
                            $referenceDomainNetbiosName = $referenceAccountName.Substring(0, $referenceSeparatorIndex)
                        }
                    }
                    catch {
                        $domainReadFailed = $true
                        [Void]$errorList.Add("Domain: DomainNetbiosName: $($_.Exception.GetBaseException().Message)")
                    }
                }
            }
        }
        else {
            $referenceMachineSid = $machineSid
            $referenceDomainSid = $domainSid
            $referenceComputerAccountSid = $computerAccountSid
            $referenceDomainNetbiosName = $domainNetbiosName
            foreach ($errorLine in $errors) {
                if (([String]$errorLine).StartsWith('identity: MachineSid:') -or ([String]$errorLine).StartsWith('identity: DomainSid:') -or ([String]$errorLine).StartsWith('identity: DomainNetbiosName:')) {
                    $domainReadFailed = $true
                }
            }
        }

        if ($domainReadFailed) {
            $state.Outcomes['Domain'] = 'Failed'
        }
        else {
            $state.Outcomes['Domain'] = 'Read'
        }

        # The section is always an object. The four values from the computer system read are null when that
        # read gave no instance. A failed SID read leaves its value null.
        $domainRow = ConvertTo-SystemInventoryRowData -Instance $computerSystemInstance -Keys @('PartOfDomain', 'Domain', 'Workgroup', 'DomainRole')
        $domainRow['MachineSid'] = $referenceMachineSid
        $domainRow['DomainSid'] = $referenceDomainSid
        $domainRow['ComputerAccountSid'] = $referenceComputerAccountSid
        $domainRow['DomainNetbiosName'] = $referenceDomainNetbiosName
        $domainSection = [PSCustomObject]$domainRow

        $stopwatchComputer.Stop()
        $computerDurationMs = [Int]$stopwatchComputer.ElapsedMilliseconds
        #endregion

        #region Hardware
        $stopwatchHardware = [System.Diagnostics.Stopwatch]::StartNew()

        # The columns are named in the read: the full read of this class samples the load and takes about a
        # second, the named read about ten milliseconds. A target that lacks one of the columns refuses the
        # query as invalid, and then the full read is the answer.
        $processorColumns = @('DeviceID', 'SocketDesignation', 'Name', 'Manufacturer', 'Description', 'ProcessorId',
            'Architecture', 'Family', 'Revision', 'NumberOfCores', 'NumberOfEnabledCore',
            'NumberOfLogicalProcessors', 'ThreadCount', 'MaxClockSpeed', 'AddressWidth', 'DataWidth',
            'L2CacheSize', 'L3CacheSize', 'VirtualizationFirmwareEnabled',
            'SecondLevelAddressTranslationExtensions', 'VMMonitorModeExtensions', 'PartNumber',
            'SerialNumber', 'AssetTag')

        $readProcessors = Invoke-SystemInventoryRead -Name 'Processors' -State $state -ReadScript {
            try {
                Get-CimInstance -ClassName Win32_Processor -Property $processorColumns -ErrorAction Stop -Verbose:$false
            }
            catch {
                if ([String]$_.Exception.PSObject.Properties['NativeErrorCode'].Value -eq 'InvalidQuery') {
                    Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop -Verbose:$false
                }
                else {
                    throw
                }
            }
        }
        $readMemory = Invoke-SystemInventoryRead -Name 'Memory' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop -Verbose:$false
        }
        $readDiskDrives = Invoke-SystemInventoryRead -Name 'DiskDrives' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop -Verbose:$false
        }
        $readStorageDisks = Invoke-SystemInventoryRead -Name 'StorageDisks' -State $state -ReadScript {
            Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_Disk -ErrorAction Stop -Verbose:$false
        }
        $readPhysicalDisks = Invoke-SystemInventoryRead -Name 'PhysicalDisks' -State $state -ReadScript {
            Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop -Verbose:$false
        }
        $readVolumes = Invoke-SystemInventoryRead -Name 'Volumes' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop -Verbose:$false
        }
        $readAdapters = Invoke-SystemInventoryRead -Name 'Adapters' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop -Verbose:$false
        }
        $readAdapterConfigurations = Invoke-SystemInventoryRead -Name 'AdapterConfigurations' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop -Verbose:$false
        }

        #region Processors one row per processor, by DeviceID
        $processorList = [System.Collections.Generic.List[Object]]::new()
        foreach ($processor in $readProcessors.Items) {
            [Void]$processorList.Add([PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $processor -Keys $processorColumns))
        }
        $processorList.Sort( [Comparison[Object]] { param($A, $B) [String]::Compare($A.DeviceID, $B.DeviceID, [System.StringComparison]::OrdinalIgnoreCase) } )
        $processors = $processorList.ToArray()
        #endregion

        #region Memory one row per module, by Tag
        $memoryList = [System.Collections.Generic.List[Object]]::new()
        foreach ($module in $readMemory.Items) {
            [Void]$memoryList.Add([PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $module -Keys @(
                        'Tag', 'BankLabel', 'DeviceLocator', 'Manufacturer', 'PartNumber', 'SerialNumber', 'Capacity',
                        'Speed', 'ConfiguredClockSpeed', 'FormFactor', 'MemoryType', 'SMBIOSMemoryType', 'TypeDetail',
                        'DataWidth', 'TotalWidth')))
        }
        $memoryList.Sort( [Comparison[Object]] { param($A, $B) [String]::Compare($A.Tag, $B.Tag, [System.StringComparison]::OrdinalIgnoreCase) } )
        $memory = $memoryList.ToArray()
        #endregion

        #region Disks one row per drive, by Index, with the storage columns of the one matching instance
        # The storage instances are indexed by their number as text. A drive takes the columns of its match
        # only when exactly one instance carries its Index, so no match and several matches both leave null.
        $storageDiskByNumber = [System.Collections.Generic.Dictionary[String, System.Collections.Generic.List[Object]]]::new()
        foreach ($storageDisk in $readStorageDisks.Items) {
            $numberText = [String]$storageDisk.Number
            if (-not $storageDiskByNumber.ContainsKey($numberText)) {
                $storageDiskByNumber[$numberText] = [System.Collections.Generic.List[Object]]::new()
            }
            [Void]$storageDiskByNumber[$numberText].Add($storageDisk)
        }
        $physicalDiskById = [System.Collections.Generic.Dictionary[String, System.Collections.Generic.List[Object]]]::new()
        foreach ($physicalDisk in $readPhysicalDisks.Items) {
            $idText = [String]$physicalDisk.DeviceId
            if (-not $physicalDiskById.ContainsKey($idText)) {
                $physicalDiskById[$idText] = [System.Collections.Generic.List[Object]]::new()
            }
            [Void]$physicalDiskById[$idText].Add($physicalDisk)
        }

        $diskList = [System.Collections.Generic.List[Object]]::new()
        foreach ($drive in $readDiskDrives.Items) {
            $diskRow = ConvertTo-SystemInventoryRowData -Instance $drive -Keys @(
                'Index', 'DeviceID', 'Model', 'SerialNumber', 'FirmwareRevision', 'InterfaceType', 'MediaType', 'Size',
                'Partitions', 'BytesPerSector', 'PNPDeviceID', 'Signature')
            $driveIndexText = [String]$drive.Index

            $matchedStorageDisk = $null
            if ($storageDiskByNumber.ContainsKey($driveIndexText) -and ($storageDiskByNumber[$driveIndexText].Count -eq 1)) {
                $matchedStorageDisk = $storageDiskByNumber[$driveIndexText][0]
            }
            $null = ConvertTo-SystemInventoryRowData -Instance $matchedStorageDisk -Row $diskRow -ArrayKeys @('OperationalStatus') -Keys @(
                'PartitionStyle', 'BusType', 'IsBoot', 'IsSystem', 'IsOffline', 'IsReadOnly', 'HealthStatus',
                'OperationalStatus', 'UniqueId', 'Guid')

            $matchedPhysicalDisk = $null
            if ($physicalDiskById.ContainsKey($driveIndexText) -and ($physicalDiskById[$driveIndexText].Count -eq 1)) {
                $matchedPhysicalDisk = $physicalDiskById[$driveIndexText][0]
            }
            $null = ConvertTo-SystemInventoryRowData -Instance $matchedPhysicalDisk -Row $diskRow -Keys @(
                'PhysicalMediaType=MediaType', 'SpindleSpeed', 'PhysicalSectorSize', 'LogicalSectorSize')

            [Void]$diskList.Add([PSCustomObject]$diskRow)
        }
        $diskList.Sort( [Comparison[Object]] { param($A, $B) ([Int64]$A.Index).CompareTo([Int64]$B.Index) } )
        $disks = $diskList.ToArray()

        # The disk the computer booted from, by its partition style (1 is MBR, 2 is GPT). A disk list that did
        # not come back leaves it null.
        foreach ($storageDisk in $readStorageDisks.Items) {
            $bootStyleRow = ConvertTo-SystemInventoryRowData -Instance $storageDisk -Keys @('IsBoot', 'PartitionStyle')
            if ($bootStyleRow['IsBoot'] -eq $true) {
                $firmwareRow['BootDiskPartitionStyle'] = $bootStyleRow['PartitionStyle']
                break
            }
        }
        #endregion

        #region Volumes one row per volume, by DeviceID
        $volumeList = [System.Collections.Generic.List[Object]]::new()
        foreach ($volume in $readVolumes.Items) {
            [Void]$volumeList.Add([PSCustomObject](ConvertTo-SystemInventoryRowData -Instance $volume -Keys @(
                        'DeviceID', 'Name', 'DriveLetter', 'Label', 'FileSystem', 'DriveType', 'Capacity', 'FreeSpace',
                        'BlockSize', 'BootVolume', 'SystemVolume', 'PageFilePresent', 'Compressed', 'IndexingEnabled',
                        'Automount', 'SerialNumber')))
        }
        $volumeList.Sort( [Comparison[Object]] { param($A, $B) [String]::Compare($A.DeviceID, $B.DeviceID, [System.StringComparison]::OrdinalIgnoreCase) } )
        $volumes = $volumeList.ToArray()
        #endregion

        #region Adapters one row per kept adapter, by Index
        # An adapter is kept when it is physical or its configuration has IP enabled. Without the adapter read
        # the rows come from the enabled configurations alone and the adapter columns that the configuration
        # does not hold stay null. A configuration read that did not come back leaves the configuration columns
        # null.
        $adapterKeys = @('Index', 'InterfaceIndex', 'NetConnectionID', 'Name', 'Description', 'Manufacturer', 'AdapterType',
            'MACAddress', 'PhysicalAdapter', 'NetEnabled', 'NetConnectionStatus', 'Speed', 'GUID', 'PNPDeviceID', 'ServiceName')
        $configurationKeys = @('IPEnabled', 'DHCPEnabled', 'DHCPServer', 'IPAddress', 'IPSubnet', 'DefaultIPGateway',
            'DNSServerSearchOrder', 'DNSDomain', 'DNSDomainSuffixSearchOrder', 'FullDNSRegistrationEnabled',
            'DomainDNSRegistrationEnabled', 'WINSPrimaryServer', 'WINSSecondaryServer', 'TcpipNetbiosOptions')
        $configurationArrayKeys = @('IPAddress', 'IPSubnet', 'DefaultIPGateway', 'DNSServerSearchOrder', 'DNSDomainSuffixSearchOrder')
        $configurationOnlyKeys = @('Index', 'InterfaceIndex', 'Description', 'MACAddress', 'ServiceName')

        $configurationByIndex = [System.Collections.Generic.Dictionary[String, Object]]::new()
        foreach ($configuration in $readAdapterConfigurations.Items) {
            $configurationIndexText = [String]$configuration.Index
            if (-not $configurationByIndex.ContainsKey($configurationIndexText)) {
                $configurationByIndex[$configurationIndexText] = $configuration
            }
        }

        $adapterList = [System.Collections.Generic.List[Object]]::new()
        if ($readAdapters.Outcome -eq 'Read') {
            foreach ($adapter in $readAdapters.Items) {
                $adapterConfiguration = $null
                $adapterIndexText = [String]$adapter.Index
                if ($configurationByIndex.ContainsKey($adapterIndexText)) {
                    $adapterConfiguration = $configurationByIndex[$adapterIndexText]
                }
                $isKept = ($adapter.PhysicalAdapter -eq $true) -or (($null -ne $adapterConfiguration) -and ($adapterConfiguration.IPEnabled -eq $true))
                if ($isKept) {
                    $adapterRow = ConvertTo-SystemInventoryRowData -Instance $adapter -Keys $adapterKeys
                    $null = ConvertTo-SystemInventoryRowData -Instance $adapterConfiguration -Row $adapterRow -ArrayKeys $configurationArrayKeys -Keys $configurationKeys
                    [Void]$adapterList.Add([PSCustomObject]$adapterRow)
                }
            }
        }
        else {
            foreach ($configuration in $readAdapterConfigurations.Items) {
                if ($configuration.IPEnabled -eq $true) {
                    $adapterRow = ConvertTo-SystemInventoryRowData -Instance $null -Keys $adapterKeys
                    $null = ConvertTo-SystemInventoryRowData -Instance $configuration -Row $adapterRow -Keys $configurationOnlyKeys
                    $null = ConvertTo-SystemInventoryRowData -Instance $configuration -Row $adapterRow -ArrayKeys $configurationArrayKeys -Keys $configurationKeys
                    [Void]$adapterList.Add([PSCustomObject]$adapterRow)
                }
            }
        }
        $adapterList.Sort( [Comparison[Object]] { param($A, $B) ([Int64]$A.Index).CompareTo([Int64]$B.Index) } )
        $adapters = $adapterList.ToArray()
        #endregion

        $stopwatchHardware.Stop()
        $hardwareDurationMs = [Int]$stopwatchHardware.ElapsedMilliseconds
        #endregion

        #region Hotfixes
        $stopwatchHotfixes = [System.Diagnostics.Stopwatch]::StartNew()

        $readHotfixes = Invoke-SystemInventoryRead -Name 'Hotfixes' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop -Verbose:$false
        }

        # InstalledOn is kept as the text the class gives. A CIM instance is read through its own property, so
        # the script property that PowerShell lays over it, and parses the text into a date, is never seen.
        # InstalledOnDate is filled only when that text is exactly month/day/year, so a text in another form
        # never becomes a guessed date. An object that is not a CIM instance may hand the value over as a
        # date at local midnight. That one is written as its own calendar day in the same month/day/year
        # form, because a conversion to UTC would move it to the day before.
        $hotfixList = [System.Collections.Generic.List[Object]]::new()
        foreach ($hotfix in $readHotfixes.Items) {
            $hotfixRow = ConvertTo-SystemInventoryRowData -Instance $hotfix -Keys @('HotFixID', 'Description', 'Caption', 'InstalledOn')
            if ($hotfix.GetType().FullName -ne 'Microsoft.Management.Infrastructure.CimInstance') {
                $installedOnProperty = $hotfix.PSObject.Properties['InstalledOn']
                if (($null -ne $installedOnProperty) -and ($installedOnProperty.Value -is [DateTime])) {
                    $hotfixRow['InstalledOn'] = $installedOnProperty.Value.ToString('M/d/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
                }
            }
            $installedOnDate = $null
            $parsedDate = [DateTime]::MinValue
            if (($hotfixRow['InstalledOn'] -is [String]) -and [DateTime]::TryParseExact($hotfixRow['InstalledOn'], 'M/d/yyyy', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
                $installedOnDate = $parsedDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            $hotfixRow['InstalledOnDate'] = $installedOnDate
            $null = ConvertTo-SystemInventoryRowData -Instance $hotfix -Row $hotfixRow -Keys @('InstalledBy')
            $hotfixRow['InstalledBySid'] = $null
            $null = ConvertTo-SystemInventoryRowData -Instance $hotfix -Row $hotfixRow -Keys @('ServicePackInEffect', 'FixComments')
            [Void]$hotfixList.Add([PSCustomObject]$hotfixRow)
        }
        $hotfixList.Sort( [Comparison[Object]] {
                param($A, $B)
                $result = [String]::Compare($A.HotFixID, $B.HotFixID, [System.StringComparison]::OrdinalIgnoreCase)
                if ($result -eq 0) {
                    $result = [String]::Compare($A.InstalledOn, $B.InstalledOn, [System.StringComparison]::Ordinal)
                }
                if ($result -eq 0) {
                    $result = [String]::Compare($A.InstalledBy, $B.InstalledBy, [System.StringComparison]::Ordinal)
                }
                $result
            } )
        $hotfixes = $hotfixList.ToArray()

        $stopwatchHotfixes.Stop()
        $hotfixesDurationMs = [Int]$stopwatchHotfixes.ElapsedMilliseconds
        #endregion

        #region Features
        $stopwatchFeatures = [System.Diagnostics.Stopwatch]::StartNew()

        $readOptionalFeatures = Invoke-SystemInventoryRead -Name 'OptionalFeatures' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_OptionalFeature -ErrorAction Stop -Verbose:$false
        }
        # The servicing stack list is a second source for the same features. The class folds two of the four
        # states into one and the DISM list folds two others, so both are kept side by side. The cmdlet needs
        # elevation and takes seconds, and a computer without the module has no such command. With
        # -SkipDismFeatures the cmdlet is never called, because it makes Windows write a trace to dism.log on
        # the target. The read is recorded as Skipped, which is no error and no failed read, and it returns no
        # items, so every DismState stays null.
        if ($SkipDismFeatures) {
            $state.Outcomes['DismFeatures'] = 'Skipped'
            $readDismFeatures = [PSCustomObject]@{
                Name    = 'DismFeatures'
                Outcome = 'Skipped'
                Cause   = $null
                ErrorId = $null
                Items   = @()
            }
        }
        else {
            $readDismFeatures = Invoke-SystemInventoryRead -Name 'DismFeatures' -State $state -RequiresCommand 'Get-WindowsOptionalFeature' -ReadScript {
                Get-WindowsOptionalFeature -Online -ErrorAction Stop
            }
        }
        $readServerFeatures = Invoke-SystemInventoryRead -Name 'ServerFeatures' -State $state -ReadScript {
            Get-CimInstance -ClassName Win32_ServerFeature -ErrorAction Stop -Verbose:$false
        }

        # The DISM state as its display string, by feature name ignoring case. The first entry of a name wins.
        # The string is made here, on the target, so no enumeration type of the cmdlet leaves it.
        $dismStateByName = [System.Collections.Generic.Dictionary[String, String]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $dismNames = [System.Collections.Generic.List[String]]::new()
        foreach ($dismFeature in $readDismFeatures.Items) {
            $dismNameProperty = $dismFeature.PSObject.Properties['FeatureName']
            $dismStateProperty = $dismFeature.PSObject.Properties['State']
            if (($null -eq $dismNameProperty) -or [String]::IsNullOrEmpty([String]$dismNameProperty.Value)) {
                continue
            }
            $dismName = [String]$dismNameProperty.Value
            if ($dismStateByName.ContainsKey($dismName)) {
                continue
            }
            $dismState = $null
            if (($null -ne $dismStateProperty) -and ($null -ne $dismStateProperty.Value)) {
                $dismState = [String]$dismStateProperty.Value
            }
            $dismStateByName[$dismName] = $dismState
            [Void]$dismNames.Add($dismName)
        }

        # Every instance is kept, the disabled optional features too. The two classes and the DISM list share
        # the Source, Name, Caption, InstallState, DismState, Id and ParentId columns and each leaves the ones it
        # lacks null. A class instance and a DISM feature of the same name are one row. A feature that only DISM
        # lists gets a row of its own, and without the class every optional feature row comes from DISM.
        $featureList = [System.Collections.Generic.List[Object]]::new()
        $dismMatched = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($optionalFeature in $readOptionalFeatures.Items) {
            $featureRow = [ordered]@{
                Source = 'OptionalFeature'
            }
            $null = ConvertTo-SystemInventoryRowData -Instance $optionalFeature -Row $featureRow -Keys @('Name', 'Caption', 'InstallState')
            $classDismState = $null
            $classFeatureName = [String]$featureRow['Name']
            if ((-not [String]::IsNullOrEmpty($classFeatureName)) -and $dismStateByName.ContainsKey($classFeatureName)) {
                $classDismState = $dismStateByName[$classFeatureName]
                [Void]$dismMatched.Add($classFeatureName)
            }
            $featureRow['DismState'] = $classDismState
            $featureRow['Id'] = $null
            $featureRow['ParentId'] = $null
            [Void]$featureList.Add([PSCustomObject]$featureRow)
        }
        foreach ($dismName in $dismNames) {
            if (-not $dismMatched.Contains($dismName)) {
                $featureRow = [ordered]@{
                    Source       = 'OptionalFeature'
                    Name         = $dismName
                    Caption      = $null
                    InstallState = $null
                    DismState    = $dismStateByName[$dismName]
                    Id           = $null
                    ParentId     = $null
                }
                [Void]$featureList.Add([PSCustomObject]$featureRow)
            }
        }
        foreach ($serverFeature in $readServerFeatures.Items) {
            $featureRow = [ordered]@{
                Source = 'ServerFeature'
            }
            $null = ConvertTo-SystemInventoryRowData -Instance $serverFeature -Row $featureRow -Keys @('Name')
            $featureRow['Caption'] = $null
            $featureRow['InstallState'] = $null
            $featureRow['DismState'] = $null
            $null = ConvertTo-SystemInventoryRowData -Instance $serverFeature -Row $featureRow -Keys @('Id=ID', 'ParentId=ParentID')
            [Void]$featureList.Add([PSCustomObject]$featureRow)
        }
        $featureList.Sort( [Comparison[Object]] {
                param($A, $B)
                $result = [String]::Compare($A.Source, $B.Source, [System.StringComparison]::Ordinal)
                if ($result -eq 0) {
                    $result = [String]::Compare($A.Name, $B.Name, [System.StringComparison]::OrdinalIgnoreCase)
                }
                if ($result -eq 0) {
                    $result = [String]::Compare([String]$A.Id, [String]$B.Id, [System.StringComparison]::Ordinal)
                }
                $result
            } )
        $features = $featureList.ToArray()

        $stopwatchFeatures.Stop()
        $featuresDurationMs = [Int]$stopwatchFeatures.ElapsedMilliseconds
        #endregion

        #region Accounts
        $accounts = @()
        $accountCount = 0
        $accountUnresolvedCount = 0
        $appContainers = @()
        $appContainerCount = 0
        $accountsDurationMs = 0

        $stopwatchAccounts = [System.Diagnostics.Stopwatch]::StartNew()

        # The grouping, every lookup and the fill-back all sit inside one try/catch, so a failure anywhere in
        # this step never stops the return: the account data for this run is simply empty, with the reason in
        # the error list.
        try {
            # First spelling seen per case-insensitive InstalledBy is kept as the account's Token, so two updates
            # differing only by the casing of the installer still resolve to one account row. Each token
            # collects the HotFixID of every update it installed, each id once.
            $tokenReferenceSets = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $tokenOrder = [System.Collections.Generic.List[String]]::new()
            foreach ($hotfix in $hotfixes) {
                $installedBy = $hotfix.InstalledBy
                if ([String]::IsNullOrEmpty($installedBy)) {
                    continue
                }
                if (-not $tokenReferenceSets.ContainsKey($installedBy)) {
                    $tokenReferenceSets[$installedBy] = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    [Void]$tokenOrder.Add($installedBy)
                }
                if (-not [String]::IsNullOrEmpty($hotfix.HotFixID)) {
                    [Void]$tokenReferenceSets[$installedBy].Add($hotfix.HotFixID)
                }
            }

            $tokenOrder.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::Ordinal) } )

            $accountByToken = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $appContainerByToken = [System.Collections.Generic.Dictionary[String, Object]]::new([System.StringComparer]::OrdinalIgnoreCase)

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
                    $appContainerReferences = [System.Collections.Generic.List[String]]::new($tokenReferenceSets[$token])
                    $appContainerReferences.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )

                    $appContainerObject = [PSCustomObject]@{
                        Token          = $token
                        Kind           = $appContainerKind
                        Sid            = $sidCandidate
                        Name           = $null
                        ReferenceCount = $appContainerReferences.Count
                        References     = @($appContainerReferences.ToArray())
                    }

                    $appContainers += $appContainerObject
                    $appContainerByToken[$token] = $appContainerObject
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
                            # The Service Control Manager's own alias for the SYSTEM account, not a real
                            # account name, so it never goes through a lookup.
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

                # The list is built here and read nowhere else after this point, so it is sorted in place.
                $referencesForToken = [System.Collections.Generic.List[String]]::new($tokenReferenceSets[$token])
                # Sorted ordinal case-insensitive, the same comparer the hotfix list uses for the id.
                $referencesForToken.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )

                $accountObject = [PSCustomObject]@{
                    Token          = $token
                    Kind           = $kind
                    Sid            = $sid
                    Name           = $accountName
                    Status         = $status
                    ReferenceCount = $referencesForToken.Count
                    References     = @($referencesForToken.ToArray())
                    Error          = $acctError
                }

                $accounts += $accountObject
                $accountByToken[$token] = $accountObject

                if ($status -eq 'NotFound') {
                    $accountUnresolvedCount++
                }
            }

            $accountCount = $accounts.Count
            $appContainerCount = $appContainers.Count

            foreach ($hotfix in $hotfixes) {
                $installedBy = $hotfix.InstalledBy
                if ([String]::IsNullOrEmpty($installedBy)) {
                    $hotfix.InstalledBySid = $null
                    continue
                }
                # A package or capability token has no account row, its SID is the token text and needs no lookup.
                $matchedAppContainer = $appContainerByToken[$installedBy]
                if ($null -ne $matchedAppContainer) {
                    $hotfix.InstalledBySid = $matchedAppContainer.Sid
                    continue
                }
                $matchedAccount = $accountByToken[$installedBy]
                if (($null -ne $matchedAccount) -and ($matchedAccount.Status -eq 'Resolved')) {
                    $hotfix.InstalledBySid = $matchedAccount.Sid
                }
                else {
                    $hotfix.InstalledBySid = $null
                }
            }
        }
        catch {
            [Void]$errorList.Add("accounts: $($_.Exception.Message)")
            $accounts = @()
            $accountCount = 0
            $accountUnresolvedCount = 0
            $appContainers = @()
            $appContainerCount = 0
            foreach ($hotfix in $hotfixes) {
                $hotfix.InstalledBySid = $null
            }
        }
        finally {
            $stopwatchAccounts.Stop()
            $accountsDurationMs = [Int]$stopwatchAccounts.ElapsedMilliseconds
        }
        #endregion

        #region Return
        $readCount = 0
        $readFailedCount = 0
        $readSkippedCount = 0
        $readFailedItems = [System.Collections.Generic.List[String]]::new()
        $absentItems = [System.Collections.Generic.List[String]]::new()
        foreach ($readName in $readNames) {
            $readOutcome = $state.Outcomes[$readName]
            if ($readOutcome -eq 'Failed') {
                $readFailedCount++
                [Void]$readFailedItems.Add($readName)
            }
            elseif ($readOutcome -eq 'Skipped') {
                # A read that was not attempted is neither read nor failed, so it counts in neither.
                $readSkippedCount++
            }
            else {
                $readCount++
                if ($readOutcome -eq 'Absent') {
                    [Void]$absentItems.Add($readName)
                }
            }
        }

        $computerObject = [PSCustomObject]@{
            ComputerSystem  = $computerSystemSection
            OperatingSystem = $operatingSystemSection
            Bios            = $biosSection
            BaseBoard       = $baseBoardSection
            Enclosure       = $enclosureSection
            Product         = $productSection
            Firmware        = [PSCustomObject]$firmwareRow
            Tpm             = $tpmSection
            DeviceGuard     = $deviceGuardSection
            TimeZone        = $timeZoneSection
            PageFiles       = @($pageFiles)
            Domain          = $domainSection
        }

        $collectedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

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
            ReadCount              = [Int]$readCount
            ReadFailedCount        = [Int]$readFailedCount
            ReadSkippedCount       = [Int]$readSkippedCount
            ProcessorCount         = [Int]$processors.Count
            MemoryModuleCount      = [Int]$memory.Count
            DiskCount              = [Int]$disks.Count
            VolumeCount            = [Int]$volumes.Count
            AdapterCount           = [Int]$adapters.Count
            HotfixCount            = [Int]$hotfixes.Count
            FeatureCount           = [Int]$features.Count
            AccountCount           = [Int]$accountCount
            AccountUnresolvedCount = [Int]$accountUnresolvedCount
            AppContainerCount      = [Int]$appContainerCount
            ComputerDurationMs     = [Int]$computerDurationMs
            HardwareDurationMs     = [Int]$hardwareDurationMs
            HotfixesDurationMs     = [Int]$hotfixesDurationMs
            FeaturesDurationMs     = [Int]$featuresDurationMs
            AccountsDurationMs     = [Int]$accountsDurationMs
            ReadFailedItems        = $readFailedItems.ToArray()
            AbsentItems            = $absentItems.ToArray()
            Computer               = $computerObject
            Processors             = @($processors)
            Memory                 = @($memory)
            Disks                  = @($disks)
            Volumes                = @($volumes)
            Adapters               = @($adapters)
            Hotfixes               = @($hotfixes)
            Features               = @($features)
            Accounts               = @($accounts)
            AppContainers          = @($appContainers)
            Errors                 = @($errorList.ToArray() | ForEach-Object { ([String]$_).Trim() -replace '\s+', ' ' })
        }
        #endregion
    }
}
#endregion
