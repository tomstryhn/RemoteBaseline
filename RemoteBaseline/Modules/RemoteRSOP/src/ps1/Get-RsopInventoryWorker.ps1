<#PSScriptInfo

.DESCRIPTION Returns the self-contained scriptblock that reads the RSOP WMI namespaces on a target

.VERSION 1.3.0

.GUID 71dfb9d4-6b98-4258-abc0-0f05f1ef5835

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Get-RsopInventoryWorker {

    <#
    .SYNOPSIS
        Returns the self-contained scriptblock that reads the RSOP WMI namespaces on a target.

    .DESCRIPTION
        The scriptblock this function returns is what actually runs on the target, local or
        remote, so it uses no module function, no module variable and no using: expression. It
        takes a SkipSidReference flag (first, because the remote call passes it positionally), the
        computer namespace and the user namespace root, enumerates every populated
        class in root\RSOP\Computer and every root\RSOP\User\<SID> namespace, projects each
        instance into a plain object, resolves every account referenced by a user right or a
        restricted group, and returns one flat object carrying the target identity, the counts,
        the whole dump as one RawJson string and the account table. It never throws: every step
        sits in its own try/catch and appends to an Errors list instead. The identity step also
        reads the SID reference: MachineSid from the local account with RID 500 (Win32_UserAccount
        filtered on the computer name as the domain, so a domain controller gives null), and on a
        domain-joined computer DomainSid, ComputerAccountSid and DomainNetbiosName from a
        translation of the computer's own domain account. SkipSidReference true leaves all four
        null with no error. Invoke-RsopInventoryLocal
        calls it directly for the local computer. Invoke-RsopInventoryRemote passes it to
        Invoke-Command for every remote target.

    .NOTES
        FUNCTION: Get-RsopInventoryWorker
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
            [bool]$SkipSidReference = $false,
            [string]$ComputerNamespace = 'root\RSOP\Computer',
            [string]$UserNamespaceRoot = 'root\RSOP\User'
        )

        # Off here, not only in the public function, so the worker behaves the same in-process as on a remote target, where strict mode is off by default
        Set-StrictMode -Off

        $errors = @()

        function Test-RsopInventorySkippableClass {
            <#
            .SYNOPSIS
                Decides whether a CIM class is one of the system or parent classes step 2 skips.
            #>
            param(
                $Class
            )

            $className = $Class.CimClassName

            if ($className.StartsWith('__', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($className.StartsWith('CIM_', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($className.StartsWith('MSFT_', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($className -eq 'RSOP_PolicySetting' -or $className -eq 'RSOP_SecuritySettings') { return $true }

            foreach ($qualifier in $Class.CimClassQualifiers) {
                if ($qualifier.Name -ieq 'abstract') { return $true }
            }

            return $false
        }

        function ConvertTo-RsopInventoryPlainValue {
            <#
            .SYNOPSIS
                Projects one CIM property value to a JSON-friendly value, recursing into an
                embedded reference instance so its own CimClass and CimSystemProperties never
                reach the output.
            #>
            param(
                $Value
            )

            if ($null -eq $Value) { return $null }

            if ($Value -is [Microsoft.Management.Infrastructure.CimInstance]) {
                return ConvertTo-RsopInventoryPlainObject -Instance $Value
            }

            if ($Value -is [byte[]]) {
                # Comma-return preserves a single-element or empty array across the function boundary
                return , $Value
            }

            if ($Value -is [DateTime]) {
                return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            }

            if ($Value -is [array]) {
                $items = @()
                foreach ($item in $Value) { $items += ConvertTo-RsopInventoryPlainValue -Value $item }
                return , $items
            }

            return $Value
        }

        function ConvertTo-RsopInventoryPlainObject {
            <#
            .SYNOPSIS
                Projects a CIM instance to a PSCustomObject built only from its CIM properties, in
                the class's own property order.
            #>
            param(
                $Instance
            )

            $properties = [ordered]@{}
            foreach ($property in $Instance.CimInstanceProperties) {
                $properties[$property.Name] = ConvertTo-RsopInventoryPlainValue -Value $property.Value
            }
            return [pscustomobject]$properties
        }

        function Get-RsopInventoryNamespaceDump {
            <#
            .SYNOPSIS
                Enumerates and projects every exportable class of one RSOP namespace.

            .DESCRIPTION
                Applies the step 2 class filter, projects every instance of every remaining
                populated class, and reports per-class errors without ever throwing itself. A
                Get-CimClass failure for the whole namespace comes back as a null ClassCount with
                the message in NamespaceError, leaving the throw to the caller to log.
            #>
            param(
                [string]$Namespace,
                [string]$Label
            )

            try {
                $cimClasses = Get-CimClass -Namespace $Namespace -ErrorAction Stop
            } catch {
                return [pscustomobject]@{
                    Namespace      = $Label
                    Path           = $Namespace
                    Classes        = @()
                    ClassErrors    = @()
                    ClassCount     = $null
                    InstanceCount  = $null
                    NamespaceError = $_.Exception.Message
                }
            }

            $classes = @()
            $classErrors = @()
            $instanceCount = 0

            foreach ($class in $cimClasses) {
                if (Test-RsopInventorySkippableClass -Class $class) { continue }

                $className = $class.CimClassName
                try {
                    # Shallow, so a non-abstract parent does not repeat the instances of its subclasses
                    $instances = @(Get-CimInstance -Namespace $Namespace -ClassName $className -Shallow -ErrorAction Stop)
                } catch {
                    $classErrors += [pscustomobject]@{ ClassName = $className; Error = $_.Exception.Message }
                    continue
                }

                if ($instances.Count -eq 0) { continue }

                $projected = @()
                foreach ($instance in $instances) { $projected += ConvertTo-RsopInventoryPlainObject -Instance $instance }

                $classes += [pscustomobject]@{
                    ClassName     = $className
                    InstanceCount = $instances.Count
                    Instances     = @($projected)
                }
                $instanceCount += $instances.Count
            }

            return [pscustomobject]@{
                Namespace      = $Label
                Path           = $Namespace
                Classes        = @($classes)
                ClassErrors    = @($classErrors)
                ClassCount     = $classes.Count
                InstanceCount  = $instanceCount
                NamespaceError = ''
            }
        }

        #region Step 1: identity
        $identityStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

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
            if ($null -ne $cv.UBR) { $ubr = $cv.UBR.ToString() }
            $displayVersion = $cv.DisplayVersion
            $editionId = $cv.EditionID
            $installationType = $cv.InstallationType
        } catch {
            $errors += "CurrentVersion key: $($_.Exception.Message)"
        }

        $os = $null
        $cs = $null
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop -Verbose:$false
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop -Verbose:$false
        } catch {
            $errors += "Get-CimInstance failed: $($_.Exception.Message)"
        }

        if ($null -ne $os) {
            $osCaption = $os.Caption
            $osVersion = $os.Version
        }
        if ($null -ne $cs) {
            $dnsHostName = $cs.DNSHostName
            $domain = $cs.Domain
            $partOfDomain = [bool]$cs.PartOfDomain
            if ($null -ne $cs.DomainRole) { $domainRole = [int]$cs.DomainRole }
        }

        try {
            $culture = [System.Globalization.CultureInfo]::CurrentCulture.Name
        } catch {
            $errors += "culture: $($_.Exception.Message)"
        }

        try {
            $timeZoneId = [System.TimeZoneInfo]::Local.Id
        } catch {
            $errors += "time zone: $($_.Exception.Message)"
        }

        try {
            $winIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $collectedBy = $winIdentity.Name
            $winPrincipal = New-Object System.Security.Principal.WindowsPrincipal($winIdentity)
            $isElevated = $winPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch {
            $errors += "elevation check: $($_.Exception.Message)"
            $isElevated = $false
        }

        #region Computer identity
        $computerId = $null
        $machineGuid = $null
        try {
            $product = $null
            $product = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop -Verbose:$false
            if ($null -ne $product -and $null -ne $product.PSObject.Properties['UUID'] -and -not [string]::IsNullOrWhiteSpace([string]$product.UUID)) {
                $computerId = ([string]$product.UUID).Trim().ToUpperInvariant()
            }
        }
        catch { $errors += "identity: ComputerId: $($_.Exception.Message)" }
        try {
            $machineGuid = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        }
        catch { $errors += "identity: MachineGuid: $($_.Exception.Message)" }
        #endregion

        #region SID reference
        # Four reference values that say whose an S-1-5-21 SID is; none is used as identity. MachineSid is the SID of the computer's own account database: the built-in Administrator (RID 500, whatever its name or state) without the RID. The filter names the computer as the domain, so only the local accounts are read; a domain controller has no such row and keeps null with no error. The domain values come from the computer's own account and are read only on a domain-joined computer. -SkipSidReference leaves all four null with no error.
        $machineSid = $null
        $domainSid = $null
        $computerAccountSid = $null
        $domainNetbiosName = $null
        if (-not $SkipSidReference) {
            try {
                $localAccounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter ('Domain = "{0}"' -f $env:COMPUTERNAME) -ErrorAction Stop -Verbose:$false)
                foreach ($localAccount in $localAccounts) {
                    if ([string]$localAccount.SID -match '^(S-1-5-21-\d+-\d+-\d+)-500$') {
                        $machineSid = $matches[1]
                        break
                    }
                }
            }
            catch { $errors += "identity: MachineSid: $($_.Exception.Message)" }

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
                        if ($separatorIndex -gt 0) { $domainNetbiosName = $computerAccountName.Substring(0, $separatorIndex) }
                    }
                    catch { $errors += "identity: DomainNetbiosName: $($_.Exception.GetBaseException().Message)" }
                }
            }
        }
        #endregion

        $identityStopwatch.Stop()
        $identityDurationMs = [int]$identityStopwatch.ElapsedMilliseconds
        #endregion

        #region Step 2: computer namespace
        $namespaceDumps = @()

        $computerStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $computerDump = Get-RsopInventoryNamespaceDump -Namespace $ComputerNamespace -Label 'Computer'
        if ($null -eq $computerDump.ClassCount) {
            $errors += "class Computer: $($computerDump.NamespaceError)"
        } else {
            foreach ($classError in $computerDump.ClassErrors) {
                $errors += "class Computer $($classError.ClassName): $($classError.Error)"
            }
        }
        $namespaceDumps += $computerDump
        $computerStopwatch.Stop()
        $computerDurationMs = [int]$computerStopwatch.ElapsedMilliseconds

        $computerClassCount = $computerDump.ClassCount
        $computerInstanceCount = $computerDump.InstanceCount

        $gpoCount = 0
        if ($null -ne $computerDump.ClassCount) {
            foreach ($classEntry in $computerDump.Classes) {
                if ($classEntry.ClassName -eq 'RSOP_GPO') { $gpoCount = $classEntry.InstanceCount }
            }
        }
        #endregion

        #region Step 3: user namespaces
        $userStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $userNamespaceCount = 0
        $userInstanceCount = 0

        try {
            $childNamespaces = @(Get-CimInstance -Namespace $UserNamespaceRoot -ClassName __NAMESPACE -ErrorAction Stop)
        } catch {
            $errors += "user namespace enumeration: $($_.Exception.Message)"
            $childNamespaces = @()
        }

        foreach ($child in $childNamespaces) {
            $childName = [string]$child.Name
            if (-not $childName.StartsWith('S_1_', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            $userNamespaceCount++
            # Join-Path resolves its parent through the caller's current provider and drops the parent from a non-filesystem location (a session whose current location is Env: or HKLM:), which would send a bare child name to Get-CimClass. A WMI namespace is not a path, so it is joined as a string.
            $childNamespacePath = $UserNamespaceRoot + '\' + $childName
            $userDump = Get-RsopInventoryNamespaceDump -Namespace $childNamespacePath -Label $childName

            if ($null -eq $userDump.ClassCount) {
                $errors += "class $childName : $($userDump.NamespaceError)"
            } else {
                foreach ($classError in $userDump.ClassErrors) {
                    $errors += "class $childName $($classError.ClassName): $($classError.Error)"
                }
                $userInstanceCount += $userDump.InstanceCount
            }
            $namespaceDumps += $userDump
        }

        $userStopwatch.Stop()
        $userDurationMs = [int]$userStopwatch.ElapsedMilliseconds
        #endregion

        #region Step 4: extension health and class error total, every namespace
        $extensionErrorCount = 0
        $classErrorCount = 0
        foreach ($dump in $namespaceDumps) {
            $classErrorCount += @($dump.ClassErrors).Count
            if ($null -eq $dump.ClassCount) { continue }
            foreach ($classEntry in $dump.Classes) {
                if ($classEntry.ClassName -ne 'RSOP_ExtensionStatus') { continue }
                foreach ($instance in $classEntry.Instances) {
                    $errorValue = $instance.error
                    # RSOP_ExtensionStatus.error is a uint32 and can carry HRESULT-sized values, so Int32 would overflow.
                    if ($null -ne $errorValue -and [int64]$errorValue -ne 0) { $extensionErrorCount++ }
                }
            }
        }
        #endregion

        #region Step 5: accounts
        $accounts = @()
        $accountCount = 0
        $accountUnresolvedCount = 0
        $accountsDurationMs = 0

        $accountsStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Extraction, grouping and every lookup sit inside one try/catch, so a failure anywhere in this step never stops the worker from returning
        try {
            $tokenReferences = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $tokenOrder = New-Object System.Collections.Generic.List[string]

            foreach ($dump in $namespaceDumps) {
                if ($null -eq $dump.ClassCount) { continue }
                foreach ($classEntry in $dump.Classes) {
                    $sourcePairs = @()
                    if ($classEntry.ClassName -eq 'RSOP_UserPrivilegeRight') {
                        foreach ($instance in $classEntry.Instances) {
                            $sourcePairs += [pscustomobject]@{ Name = $instance.UserRight; Tokens = @($instance.AccountList) }
                        }
                    } elseif ($classEntry.ClassName -eq 'RSOP_RestrictedGroup' -or $classEntry.ClassName -eq 'RSOP_RestrictedGroupEx') {
                        foreach ($instance in $classEntry.Instances) {
                            $sourcePairs += [pscustomobject]@{ Name = $instance.GroupName; Tokens = (@($instance.Members) + @($instance.MembersOf)) }
                        }
                    } else {
                        continue
                    }

                    foreach ($sourcePair in $sourcePairs) {
                        $referenceId = "$($dump.Namespace):$($classEntry.ClassName):$($sourcePair.Name)"

                        # A HashSet per source instance, not per token overall, so a token repeated within one instance still counts as one reference
                        $lineTokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($token in $sourcePair.Tokens) {
                            if ($null -eq $token) { continue }
                            $tokenText = [string]$token
                            if ($tokenText.Length -eq 0) { continue }
                            if (-not $lineTokens.Add($tokenText)) { continue }

                            if (-not $tokenReferences.ContainsKey($tokenText)) {
                                $tokenReferences[$tokenText] = New-Object System.Collections.Generic.List[string]
                                [void]$tokenOrder.Add($tokenText)
                            }
                            [void]$tokenReferences[$tokenText].Add($referenceId)
                        }
                    }
                }
            }

            $tokenOrder.Sort( [Comparison[string]] { param($a, $b) [string]::Compare($a, $b, [System.StringComparison]::Ordinal) } )

            foreach ($token in $tokenOrder) {
                # A leading * is ignored for the Kind check and stripped for the lookup, the same rewrite the other Remote collectors use for a secedit-style token
                $sidCandidate = $token
                if ($sidCandidate.StartsWith('*', [System.StringComparison]::Ordinal)) { $sidCandidate = $sidCandidate.Substring(1) }

                $kind = 'Name'
                if ($sidCandidate -match '^S-1-\d+(-\d+)+$') { $kind = 'Sid' }

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
                    } catch {
                        $status = 'NotFound'
                        $accountName = $null
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $acctError = ([string]$rawMessage).Trim() -replace '\s+', ' '
                    }
                } else {
                    $lookupName = $token
                    try {
                        if ($token -ieq 'LocalSystem') {
                            # The Service Control Manager's own alias, not a real account, so it never goes through a lookup
                            $sid = 'S-1-5-18'
                        } else {
                            if ($token.StartsWith('.\', [System.StringComparison]::Ordinal)) {
                                $lookupName = $env:COMPUTERNAME + $token.Substring(1)
                            }
                            $ntAccount = New-Object System.Security.Principal.NTAccount($lookupName)
                            $translated = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
                            $sid = $translated.Value
                        }
                    } catch {
                        $status = 'NotFound'
                        $sid = $null
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $acctError = ([string]$rawMessage).Trim() -replace '\s+', ' '
                    }
                    $accountName = $lookupName
                }

                $tokenSettingsList = $tokenReferences[$token]

                $accounts += [pscustomobject]@{
                    Token          = $token
                    Kind           = $kind
                    Sid            = $sid
                    Name           = $accountName
                    Status         = $status
                    ReferenceCount = $tokenSettingsList.Count
                    References     = @($tokenSettingsList.ToArray())
                    Error          = $acctError
                }

                if ($status -eq 'NotFound') { $accountUnresolvedCount++ }
            }

            $accountCount = $accounts.Count
        } catch {
            $errors += "accounts: $($_.Exception.Message)"
            $accounts = @()
            $accountCount = 0
            $accountUnresolvedCount = 0
        } finally {
            $accountsStopwatch.Stop()
            $accountsDurationMs = [int]$accountsStopwatch.ElapsedMilliseconds
        }
        #endregion

        #region Step 6: return the flat result
        $rawNamespaces = @()
        foreach ($dump in $namespaceDumps) {
            $rawNamespaces += [pscustomobject]@{
                Namespace   = $dump.Namespace
                Path        = $dump.Path
                Classes     = @($dump.Classes)
                ClassErrors = @($dump.ClassErrors)
            }
        }

        $raw = [pscustomobject]@{
            ComputerNamespace = $ComputerNamespace
            Namespaces        = @($rawNamespaces)
        }

        $rawJson = '{}'
        try {
            $rawJson = ConvertTo-Json -InputObject $raw -Depth 12 -Compress
        } catch {
            $errors += "RawJson serialization: $($_.Exception.Message)"
        }

        $collectedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

        [pscustomobject]@{
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
            PartOfDomain           = [bool]$partOfDomain
            IsElevated             = [bool]$isElevated
            DomainRole             = [int]$domainRole
            CollectedUtc           = $collectedUtc
            ComputerId             = $computerId
            MachineGuid            = $machineGuid
            MachineSid             = $machineSid
            DomainSid              = $domainSid
            ComputerAccountSid     = $computerAccountSid
            DomainNetbiosName      = $domainNetbiosName
            ComputerNamespace      = $ComputerNamespace
            UserNamespaceRoot      = $UserNamespaceRoot
            ComputerClassCount     = $computerClassCount
            ComputerInstanceCount  = $computerInstanceCount
            UserNamespaceCount     = $userNamespaceCount
            UserInstanceCount      = $userInstanceCount
            GpoCount               = $gpoCount
            ExtensionErrorCount    = $extensionErrorCount
            ClassErrorCount        = $classErrorCount
            AccountCount           = [int]$accountCount
            AccountUnresolvedCount = [int]$accountUnresolvedCount
            RawJson                = $rawJson
            Accounts               = @($accounts)
            IdentityDurationMs     = $identityDurationMs
            ComputerDurationMs     = $computerDurationMs
            UserDurationMs         = $userDurationMs
            AccountsDurationMs     = $accountsDurationMs
            Errors                 = @($errors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' })
        }
        #endregion
    }
}
