<#PSScriptInfo

.DESCRIPTION Returns the self-contained scriptblock that collects the service inventory on a target

.VERSION 1.7.0

.GUID a5357d75-4038-4214-8138-e8d692726de0

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-ServiceInventoryWorker
function Get-ServiceInventoryWorker {

    <#
    .SYNOPSIS
        Returns the self-contained scriptblock that collects the service inventory on a target.

    .DESCRIPTION
        The scriptblock this function returns is what actually runs on the target, local or
        remote, so it uses no module function, no module variable and no using: expression. It
        takes -SkipSidReference and -ScPath and depends on nothing else from the caller's
        session. It reads every Win32_Service instance, the security descriptor of every
        service, the SID of every distinct account a service runs as (a package or capability SID
        is not an account and goes to its own AppContainers list, with no lookup), the registry values that
        name a service's dependencies and its ServiceDll, and the identity and signature of
        every distinct service binary and ServiceDll, and returns one flat object describing the
        target and all five. It also reads four SID reference values: MachineSid from the local
        account with RID 500 (Win32_UserAccount filtered to the computer's own name, so a domain
        controller has none and keeps null), and, on a domain-joined computer only, DomainSid,
        ComputerAccountSid and DomainNetbiosName from the computer's own domain account through
        an account lookup. No Active Directory module and no LDAP is used. It never
        throws: every step is wrapped in its own try/catch and appends to an Errors list instead.
        It writes nothing to the target's disk.
        Invoke-ServiceInventoryLocal calls it directly for the local computer.
        Invoke-ServiceInventoryRemote passes it to Invoke-Command for every remote target.

    .PARAMETER SkipSidReference
        A parameter of the returned scriptblock, not of this function. It is the first parameter
        because the remote call passes it positionally. When true, none of the SID reference
        reads runs: the four values are null with no error. Defaults to false, for tests only.
        Every real caller passes it.

    .NOTES
        FUNCTION: Get-ServiceInventoryWorker
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

            [String]$ScPath = (Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath 'sc.exe')
        )

        # Off here, not only in the public function, so the worker behaves the same in-process as on a remote
        # target, where strict mode is off by default.
        Set-StrictMode -Off

        #region Get-ServiceInventoryExecutablePath
        function Get-ServiceInventoryExecutablePath {
            <#
            .SYNOPSIS
                Computes ExecutablePath from a raw Win32_Service PathName value.
            #>
            param(
                [AllowNull()]
                [String]$PathName
            )

            if ([String]::IsNullOrWhiteSpace($PathName)) {
                return $null
            }

            $trimmed = $PathName.Trim()
            $candidate = $null

            if ($trimmed.StartsWith('"')) {
                $closeIndex = $trimmed.IndexOf('"', 1)
                if ($closeIndex -gt 0) {
                    $candidate = $trimmed.Substring(1, $closeIndex - 1)
                }
                else {
                    $candidate = $trimmed.Substring(1)
                }
            }
            elseif ($trimmed -match '^(.*?\.(exe|sys|dll|cmd|bat))(\s|$)') {
                $candidate = $matches[1]
            }
            else {
                $candidate = ($trimmed -split '\s+')[0]
            }

            if ($candidate.StartsWith('\??\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidate = $candidate.Substring(4)
            }
            elseif ($candidate.StartsWith('\SystemRoot\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidate = $env:SystemRoot + '\' + $candidate.Substring('\SystemRoot\'.Length)
            }

            return [Environment]::ExpandEnvironmentVariables($candidate)
        }
        #endregion

        #region Get-ServiceInventoryRegistryValue
        function Get-ServiceInventoryRegistryValue {
            <#
            .SYNOPSIS
                Reads DependOnService, DependOnGroup and ServiceDll from one service key, or returns $null when
                the key does not exist.

            .DESCRIPTION
                The Parameters subkey of some services is closed to a caller without administrative rights. That
                read fails on its own: the two dependency lists stay, ServiceDll is null and Errors holds the
                reason. A dependency value that is not a string or a list of strings gives an empty list and a
                line in Errors. IsUserServiceInstance is true when the type of the key carries the per-user
                service instance bit.
            #>
            param(
                [String]$ServiceName
            )

            # The key is opened through .NET and not through the registry provider: a service name is not a
            # provider path, and a name with a bracket or an asterisk would be read as a wildcard.
            $serviceKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\' + $ServiceName)
            if ($null -eq $serviceKey) {
                return $null
            }

            try {
                $problems = [System.Collections.Generic.List[String]]::new()

                # Bit 0x80 of the service type marks a per-user service instance. Only an instance takes its
                # values from the template key.
                $typeValue = $serviceKey.GetValue('Type', 0)
                $isUserServiceInstance = ($typeValue -is [Int]) -and (([Int]$typeValue -band 0x80) -ne 0)

                # Plain loops, not pipelines: this runs once per service and a pipeline per read costs more than
                # the read. An entry that is empty or only whitespace is dropped.
                $dependencyLists = @{}
                foreach ($valueName in @('DependOnService', 'DependOnGroup')) {
                    $entries = @()
                    $rawValue = $serviceKey.GetValue($valueName, $null)
                    if ($rawValue -is [String[]]) {
                        $entries = $rawValue
                    }
                    elseif ($rawValue -is [String]) {
                        $entries = @($rawValue)
                    }
                    elseif ($null -ne $rawValue) {
                        [Void]$problems.Add($valueName + ' is ' + $serviceKey.GetValueKind($valueName))
                    }
                    $kept = [System.Collections.Generic.List[String]]::new()
                    foreach ($entry in $entries) {
                        if (-not [String]::IsNullOrWhiteSpace($entry)) {
                            [Void]$kept.Add($entry)
                        }
                    }
                    $dependencyLists[$valueName] = $kept.ToArray()
                }

                # The value is read as written, with its environment variables unexpanded. It sits under
                # Parameters for a hosted service and directly under the key for a few others.
                $serviceDll = $null
                try {
                    $parametersKey = $serviceKey.OpenSubKey('Parameters')
                    if ($null -ne $parametersKey) {
                        try {
                            $serviceDll = $parametersKey.GetValue('ServiceDll', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                        }
                        finally {
                            $parametersKey.Close()
                        }
                    }
                    if (($serviceDll -isnot [String]) -or [String]::IsNullOrWhiteSpace($serviceDll)) {
                        $serviceDll = $serviceKey.GetValue('ServiceDll', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    }
                    if (($serviceDll -isnot [String]) -or [String]::IsNullOrWhiteSpace($serviceDll)) {
                        $serviceDll = $null
                    }
                }
                catch {
                    $serviceDll = $null
                    [Void]$problems.Add($_.Exception.GetBaseException().Message)
                }

                # 32,767 characters is the longest path Windows takes, so a longer value is not a path.
                if (($null -ne $serviceDll) -and ($serviceDll.Length -gt 32767)) {
                    $serviceDll = $null
                    [Void]$problems.Add('ServiceDll too long')
                }

                return [PSCustomObject]@{
                    DependOnService       = $dependencyLists['DependOnService']
                    DependOnGroup         = $dependencyLists['DependOnGroup']
                    ServiceDll            = $serviceDll
                    IsUserServiceInstance = $isUserServiceInstance
                    Errors                = $problems.ToArray()
                }
            }
            finally {
                $serviceKey.Close()
            }
        }
        #endregion

        #region Test-ServiceInventoryLocalFilePath
        function Test-ServiceInventoryLocalFilePath {
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

            # The path comes from the registry of the target and the step runs elevated, so only a file on a
            # local fixed disk is opened. A UNC, device, pipe, relative or stream path never reaches a file call.
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
        # with a shorter inventory and IsElevated as the only signal. The output convention asks for the
        # shortfall to be named, which makes the row Partial.
        if (-not $isElevated) {
            $errors += 'not elevated: services and security descriptors the caller cannot open are not listed'
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

        #region Services
        $services = [System.Collections.Generic.List[Object]]::new()
        $serviceCount = 0
        $servicesDurationMs = 0
        $instances = @()

        $stopwatchServices = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $instances = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop -Verbose:$false)
        }
        catch {
            $errors += "services: Get-CimInstance failed: $($_.Exception.Message)"
            $instances = @()
        }
        $stopwatchServices.Stop()
        $servicesDurationMs = [Int]$stopwatchServices.ElapsedMilliseconds

        $serviceProperties = @('AcceptPause', 'AcceptStop', 'Caption', 'CheckPoint', 'CreationClassName',
            'DelayedAutoStart', 'Description', 'DesktopInteract', 'DisplayName', 'ErrorControl', 'ExitCode',
            'InstallDate', 'Name', 'PathName', 'ProcessId', 'ServiceSpecificExitCode', 'ServiceType', 'Started',
            'StartMode', 'StartName', 'State', 'Status', 'SystemCreationClassName', 'SystemName', 'TagId', 'WaitHint')

        foreach ($instance in $instances) {
            $svc = [ordered]@{}
            foreach ($propName in $serviceProperties) {
                # A direct read: strict mode is off here, so a property the instance lacks reads as $null,
                # which is what the column wants.
                $value = $instance.$propName
                if ($propName -eq 'InstallDate' -and $null -ne $value) {
                    # InstallDate arrives from CIM as a [datetime]. A value that does not convert or format
                    # nulls out rather than throwing.
                    try {
                        $svc[$propName] = ([DateTime]$value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                    catch {
                        $svc[$propName] = $null
                    }
                }
                else {
                    $svc[$propName] = $value
                }
            }

            $execPath = Get-ServiceInventoryExecutablePath -PathName $svc['PathName']
            $svc['ExecutablePath'] = $execPath
            $svc['Sddl'] = $null
            $svc['SddlExitCode'] = $null
            $svc['SddlStdOut'] = $null
            $svc['StartNameSid'] = $null
            $svc['DependOnService'] = @()
            $svc['DependOnGroup'] = @()
            $svc['ServiceDll'] = $null
            $svc['ServiceDllPath'] = $null

            [Void]$services.Add([PSCustomObject]$svc)
        }

        $services.Sort( [Comparison[Object]] { param($A, $B) [String]::Compare($A.Name, $B.Name, [System.StringComparison]::OrdinalIgnoreCase) } )
        # .ToArray(), not @(...): wrapping a generic List[object] with the array subexpression operator here
        # hits a PowerShell dynamic-binder mismatch ("Argument types do not match") once enough CIM types have
        # been loaded in the session.
        $services = $services.ToArray()

        $serviceCount = $services.Count
        #endregion

        #region Security descriptors
        $sddlFailedCount = 0
        $sddlDurationMs = 0

        $scExists = $false
        try {
            # -ErrorAction Stop so a failing read of the path lands in the catch and is named, rather than
            # being swallowed as a plain "not found" when the worker runs at Continue in a remote session.
            $scExists = Test-Path -LiteralPath $ScPath -ErrorAction Stop
        }
        catch {
            $errors += "test sc path: $($_.Exception.Message)"
        }

        if (-not $scExists) {
            $errors += "sc path not found: $ScPath"
            $sddlFailedCount = $services.Count
        }
        else {
            $stopwatchSddl = [System.Diagnostics.Stopwatch]::StartNew()
            foreach ($svc in $services) {
                $sddlArgs = @('sdshow', $svc.Name)
                $exitCode = $null
                $stdOut = ''
                $sddlLine = $null
                $invocationFailed = $false

                $prevEap = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    $stdOut = (& $ScPath @sddlArgs 2>&1 | ForEach-Object { "$_" } | Out-String)
                    $exitCode = $LASTEXITCODE
                }
                catch {
                    $errors += "sc sdshow $($svc.Name) invocation failed: $($_.Exception.Message)"
                    $invocationFailed = $true
                }
                finally {
                    $ErrorActionPreference = $prevEap
                }

                $trimmedOut = $stdOut.Trim()
                # The error text embeds native stdout, so every run of whitespace, line breaks included,
                # collapses to one space, while SddlStdOut keeps the original text.
                $collapsedOut = $trimmedOut -replace '\s+', ' '
                if ($exitCode -eq 0) {
                    foreach ($line in ($stdOut -split "`r`n|`n|`r")) {
                        if ($line.TrimStart().StartsWith('D:')) {
                            $sddlLine = $line.TrimStart()
                            break
                        }
                    }
                }

                if ($invocationFailed) {
                    $sddlFailedCount++
                }
                elseif ($exitCode -ne 0 -or -not $sddlLine) {
                    $errors += "sc sdshow $($svc.Name) exit ${exitCode}: $collapsedOut"
                    $sddlFailedCount++
                }

                $svc.Sddl = $sddlLine
                $svc.SddlExitCode = $exitCode
                $svc.SddlStdOut = $trimmedOut
            }
            $stopwatchSddl.Stop()
            $sddlDurationMs = [Int]$stopwatchSddl.ElapsedMilliseconds
        }
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
        # this step (an exotic StartName value included) never stops the binaries step that follows: the
        # account data for this run is simply empty, with the reason in $errors.
        try {
            # First spelling seen per case-insensitive StartName is kept as the account's Token, so two
            # services differing only by StartName casing still resolve to one account row.
            $tokenServiceNames = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $tokenOrder = New-Object System.Collections.Generic.List[string]
            foreach ($svc in $services) {
                $startName = $svc.StartName
                if ([String]::IsNullOrEmpty($startName)) {
                    continue
                }
                if (-not $tokenServiceNames.ContainsKey($startName)) {
                    $tokenServiceNames[$startName] = New-Object System.Collections.Generic.List[string]
                    [Void]$tokenOrder.Add($startName)
                }
                $tokenServiceNames[$startName].Add($svc.Name)
            }

            $tokenOrder.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::Ordinal) } )

            $accountByToken = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $appContainerByToken = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

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
                    $appContainerServiceNames = $tokenServiceNames[$token]
                    $appContainerServiceNames.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )

                    $appContainerObject = [PSCustomObject]@{
                        Token          = $token
                        Kind           = $appContainerKind
                        Sid            = $sidCandidate
                        Name           = $null
                        ReferenceCount = $appContainerServiceNames.Count
                        References     = @($appContainerServiceNames.ToArray())
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

                # The list was built in this step and is read nowhere else after this point, so it is sorted
                # in place rather than copied first.
                $serviceNamesForToken = $tokenServiceNames[$token]
                # Sorted with the same comparer the Services array itself uses, ordinal case-insensitive.
                $serviceNamesForToken.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::OrdinalIgnoreCase) } )

                $accountObject = [PSCustomObject]@{
                    Token          = $token
                    Kind           = $kind
                    Sid            = $sid
                    Name           = $accountName
                    Status         = $status
                    ReferenceCount = $serviceNamesForToken.Count
                    References     = @($serviceNamesForToken.ToArray())
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

            foreach ($svc in $services) {
                $startName = $svc.StartName
                if ([String]::IsNullOrEmpty($startName)) {
                    $svc.StartNameSid = $null
                    continue
                }
                # A package or capability token has no account row, its SID is the token text and needs no lookup.
                $matchedAppContainer = $appContainerByToken[$startName]
                if ($null -ne $matchedAppContainer) {
                    $svc.StartNameSid = $matchedAppContainer.Sid
                    continue
                }
                $matchedAccount = $accountByToken[$startName]
                if (($null -ne $matchedAccount) -and ($matchedAccount.Status -eq 'Resolved')) {
                    $svc.StartNameSid = $matchedAccount.Sid
                }
                else {
                    $svc.StartNameSid = $null
                }
            }
        }
        catch {
            $errors += "accounts: $($_.Exception.Message)"
            $accounts = @()
            $accountCount = 0
            $accountUnresolvedCount = 0
            $appContainers = @()
            $appContainerCount = 0
            foreach ($svc in $services) {
                $svc.StartNameSid = $null
            }
        }
        finally {
            $stopwatchAccounts.Stop()
            $accountsDurationMs = [Int]$stopwatchAccounts.ElapsedMilliseconds
        }
        #endregion

        #region Registry
        # One registry read per service. A per-user instance (Name_<suffix>) keeps none of the three values on
        # its own key, they sit on the template key Name, so an instance that holds nothing is read from there.
        # The distinct ServiceDll paths join the binaries step below.
        $serviceDllCount = 0
        $registryDurationMs = 0
        $serviceDllPathSet = New-Object 'System.Collections.Generic.HashSet[String]' ([System.StringComparer]::OrdinalIgnoreCase)
        $serviceDllPathList = New-Object System.Collections.Generic.List[String]

        $stopwatchRegistry = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($svc in $services) {
            $serviceName = [String]$svc.Name
            $dependOnService = @()
            $dependOnGroup = @()
            $serviceDll = $null
            $serviceDllPath = $null

            try {
                $registryValues = Get-ServiceInventoryRegistryValue -ServiceName $serviceName
                if ($null -ne $registryValues) {
                    foreach ($problem in $registryValues.Errors) {
                        $errors += ("registry: ${serviceName}: $problem" -replace '\s+', ' ').Trim()
                    }
                }
                $hasValue = ($null -ne $registryValues) -and (($registryValues.DependOnService.Count -gt 0) -or ($registryValues.DependOnGroup.Count -gt 0) -or ($null -ne $registryValues.ServiceDll))
                # Only a per-user service instance (its own key has the instance bit) reads the template key.
                if ((-not $hasValue) -and ($null -ne $registryValues) -and $registryValues.IsUserServiceInstance) {
                    $underscoreIndex = $serviceName.LastIndexOf('_')
                    if (($underscoreIndex -gt 0) -and ($underscoreIndex -lt ($serviceName.Length - 1))) {
                        $templateName = $serviceName.Substring(0, $underscoreIndex)
                        $templateValues = Get-ServiceInventoryRegistryValue -ServiceName $templateName
                        if ($null -ne $templateValues) {
                            $registryValues = $templateValues
                            foreach ($problem in $registryValues.Errors) {
                                $errors += ("registry: ${serviceName}: $problem" -replace '\s+', ' ').Trim()
                            }
                        }
                    }
                }

                if ($null -ne $registryValues) {
                    $dependOnService = @($registryValues.DependOnService)
                    $dependOnGroup = @($registryValues.DependOnGroup)
                    $serviceDll = $registryValues.ServiceDll
                    if ($null -ne $serviceDll) {
                        $dllCandidate = $serviceDll
                        if ($dllCandidate.StartsWith('\??\', [System.StringComparison]::OrdinalIgnoreCase)) {
                            $dllCandidate = $dllCandidate.Substring(4)
                        }
                        $serviceDllPath = [Environment]::ExpandEnvironmentVariables($dllCandidate)
                    }
                }
            }
            catch {
                $dependOnService = @()
                $dependOnGroup = @()
                $serviceDll = $null
                $serviceDllPath = $null
                $errors += ("registry: ${serviceName}: $($_.Exception.GetBaseException().Message)" -replace '\s+', ' ').Trim()
            }
            $svc.DependOnService = $dependOnService
            $svc.DependOnGroup = $dependOnGroup
            $svc.ServiceDll = $serviceDll
            $svc.ServiceDllPath = $serviceDllPath

            if ($serviceDllPath -and $serviceDllPathSet.Add($serviceDllPath)) {
                [Void]$serviceDllPathList.Add($serviceDllPath)
            }
        }
        $stopwatchRegistry.Stop()
        $registryDurationMs = [Int]$stopwatchRegistry.ElapsedMilliseconds
        $serviceDllCount = $serviceDllPathList.Count
        #endregion

        #region Binaries
        $binaries = @()
        $binaryCount = 0
        $binaryMissingCount = 0
        $binariesDurationMs = 0

        $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $binaryPathList = New-Object System.Collections.Generic.List[String]
        foreach ($svc in $services) {
            $ep = $svc.ExecutablePath
            if ($ep -and $seenPaths.Add($ep)) {
                [Void]$binaryPathList.Add($ep)
            }
        }
        foreach ($dllPath in $serviceDllPathList) {
            if ($seenPaths.Add($dllPath)) {
                [Void]$binaryPathList.Add($dllPath)
            }
        }
        $binaryPathList.Sort( [Comparison[String]] { param($A, $B) [String]::Compare($A, $B, [System.StringComparison]::Ordinal) } )

        # The drive list is read once for the run. A failed read leaves it empty, so no path is accepted.
        $fixedDriveLetters = New-Object 'System.Collections.Generic.HashSet[String]' ([System.StringComparer]::OrdinalIgnoreCase)
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

        $stopwatchBinaries = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($path in $binaryPathList) {
            $exists = $false
            $length = $null
            $lastWrite = $null
            $fileVersion = $null
            $productVersion = $null
            $companyName = $null
            $productName = $null
            $fileDescription = $null
            $originalFilename = $null
            $internalName = $null
            $sha256 = $null
            $sigStatus = $null
            $sigStatusMessage = $null
            $signerSubject = $null
            $signerThumbprint = $null
            $binError = ''

            $isLocalFile = Test-ServiceInventoryLocalFilePath -Path $path -FixedDriveLetter $fixedDriveLetters
            if ($isLocalFile) {
                try {
                    $exists = Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop
                }
                catch {
                    $exists = $false
                }
            }

            if (-not $isLocalFile) {
                $binError = 'not a local file path'
                $errors += "binary ${path}: not a local file path"
                $binaryMissingCount++
            }
            elseif (-not $exists) {
                $binError = 'not found'
                $errors += "binary ${path}: not found"
                $binaryMissingCount++
            }
            else {
                try {
                    $fileInfo = Get-Item -LiteralPath $path -ErrorAction Stop
                    $length = [Int64]$fileInfo.Length
                    $lastWrite = $fileInfo.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

                    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
                    $fileVersion = $versionInfo.FileVersion
                    $productVersion = $versionInfo.ProductVersion
                    $companyName = $versionInfo.CompanyName
                    $productName = $versionInfo.ProductName
                    $fileDescription = $versionInfo.FileDescription
                    $originalFilename = $versionInfo.OriginalFilename
                    $internalName = $versionInfo.InternalName

                    $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()

                    $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
                    $sigStatus = $signature.Status.ToString()
                    $sigStatusMessage = $signature.StatusMessage
                    if ($null -ne $signature.SignerCertificate) {
                        $signerSubject = $signature.SignerCertificate.Subject
                        $signerThumbprint = $signature.SignerCertificate.Thumbprint
                    }
                }
                catch {
                    $binError = "binary ${path}: $($_.Exception.Message)"
                    $errors += $binError
                    $binaryMissingCount++
                }
            }

            $binaries += [PSCustomObject]@{
                Path                   = $path
                Exists                 = $exists
                Length                 = $length
                LastWriteTimeUtc       = $lastWrite
                FileVersion            = $fileVersion
                ProductVersion         = $productVersion
                CompanyName            = $companyName
                ProductName            = $productName
                FileDescription        = $fileDescription
                OriginalFilename       = $originalFilename
                InternalName           = $internalName
                Sha256                 = $sha256
                SignatureStatus        = $sigStatus
                SignatureStatusMessage = $sigStatusMessage
                SignerSubject          = $signerSubject
                SignerThumbprint       = $signerThumbprint
                Error                  = $binError
            }
        }
        $stopwatchBinaries.Stop()
        $binariesDurationMs = [Int]$stopwatchBinaries.ElapsedMilliseconds
        $binaryCount = $binaries.Count
        #endregion

        #region Return
        $collectedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

        [PSCustomObject]@{
            ComputerName        = $env:COMPUTERNAME
            DnsHostName         = $dnsHostName
            Domain              = $domain
            OSCaption           = $osCaption
            OSVersion           = $osVersion
            CurrentBuild        = $currentBuild
            UBR                 = $ubr
            DisplayVersion      = $displayVersion
            EditionID           = $editionId
            InstallationType    = $installationType
            Culture             = $culture
            TimeZoneId          = $timeZoneId
            PSVersion           = $PSVersionTable.PSVersion.ToString()
            CollectedBy         = $collectedBy
            PartOfDomain        = [Bool]$partOfDomain
            IsElevated          = [Bool]$isElevated
            DomainRole          = [Int]$domainRole
            CollectedUtc        = $collectedUtc
            ComputerId          = $computerId
            MachineGuid         = $machineGuid
            MachineSid          = $machineSid
            DomainSid           = $domainSid
            ComputerAccountSid  = $computerAccountSid
            DomainNetbiosName   = $domainNetbiosName
            ScPath              = $ScPath
            ServiceCount        = [Int]$serviceCount
            SddlFailedCount     = [Int]$sddlFailedCount
            BinaryCount         = [Int]$binaryCount
            BinaryMissingCount  = [Int]$binaryMissingCount
            AccountCount        = [Int]$accountCount
            AccountUnresolvedCount = [Int]$accountUnresolvedCount
            AppContainerCount   = [Int]$appContainerCount
            ServiceDllCount     = [Int]$serviceDllCount
            ServicesDurationMs  = [Int]$servicesDurationMs
            SddlDurationMs      = [Int]$sddlDurationMs
            AccountsDurationMs  = [Int]$accountsDurationMs
            BinariesDurationMs  = [Int]$binariesDurationMs
            RegistryDurationMs  = [Int]$registryDurationMs
            Services            = @($services)
            Accounts            = @($accounts)
            AppContainers       = @($appContainers)
            Binaries            = @($binaries)
            Errors              = @($errors | ForEach-Object { ([String]$_).Trim() -replace '\s+', ' ' })
        }
        #endregion
    }
}
#endregion
