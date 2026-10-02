<#PSScriptInfo

.DESCRIPTION Returns the self-contained scriptblock that collects the service inventory on a target

.VERSION 1.4.0

.GUID a5357d75-4038-4214-8138-e8d692726de0

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function Get-ServiceInventoryWorker {

    <#
    .SYNOPSIS
        Returns the self-contained scriptblock that collects the service inventory on a target.

    .DESCRIPTION
        The scriptblock this function returns is what actually runs on the target, local or
        remote, so it uses no module function, no module variable and no using: expression. It
        takes -SkipSidReference and -ScPath and depends on nothing else from the caller's
        session. It reads every Win32_Service instance, the security descriptor of every
        service, the SID of every distinct account a service runs as, and the identity and
        signature of every distinct service binary, and returns one flat object describing the
        target and all four. It also reads four SID reference values: MachineSid from the local
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
        reads runs: the four values are null with no error. Defaults to false, for tests only;
        every real caller passes it.

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
            [bool]$SkipSidReference = $false,

            [string]$ScPath = (Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath 'sc.exe')
        )

        # Off here, not only in the public function, so the worker behaves the same in-process as on a remote target, where strict mode is off by default.
        Set-StrictMode -Off

        function Get-ServiceInventoryExecutablePath {
            <#
            .SYNOPSIS
                Computes ExecutablePath from a raw Win32_Service PathName value.
            #>
            param(
                [AllowNull()]
                [string]$PathName
            )

            if ([string]::IsNullOrWhiteSpace($PathName)) { return $null }

            $trimmed = $PathName.Trim()
            $candidate = $null

            if ($trimmed.StartsWith('"')) {
                $closeIndex = $trimmed.IndexOf('"', 1)
                if ($closeIndex -gt 0) {
                    $candidate = $trimmed.Substring(1, $closeIndex - 1)
                } else {
                    $candidate = $trimmed.Substring(1)
                }
            } elseif ($trimmed -match '^(.*?\.(exe|sys|dll|cmd|bat))(\s|$)') {
                $candidate = $matches[1]
            } else {
                $candidate = ($trimmed -split '\s+')[0]
            }

            if ($candidate.StartsWith('\??\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidate = $candidate.Substring(4)
            } elseif ($candidate.StartsWith('\SystemRoot\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidate = $env:SystemRoot + '\' + $candidate.Substring('\SystemRoot\'.Length)
            }

            return [Environment]::ExpandEnvironmentVariables($candidate)
        }

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

        # An unelevated caller sees only the items it may open. Without this line the row would be Success with a shorter inventory and IsElevated as the only signal; convention 1.2 asks for the shortfall to be named, which makes the row Partial.
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

        #region Services
        $services = [System.Collections.Generic.List[object]]::new()
        $serviceCount = 0
        $servicesDurationMs = 0
        $instances = @()

        $stopwatchServices = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $instances = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop -Verbose:$false)
        } catch {
            $errors += "services: Get-CimInstance failed: $($_.Exception.Message)"
            $instances = @()
        }
        $stopwatchServices.Stop()
        $servicesDurationMs = [int]$stopwatchServices.ElapsedMilliseconds

        $serviceProperties = @('AcceptPause', 'AcceptStop', 'Caption', 'CheckPoint', 'CreationClassName',
            'DelayedAutoStart', 'Description', 'DesktopInteract', 'DisplayName', 'ErrorControl', 'ExitCode',
            'InstallDate', 'Name', 'PathName', 'ProcessId', 'ServiceSpecificExitCode', 'ServiceType', 'Started',
            'StartMode', 'StartName', 'State', 'Status', 'SystemCreationClassName', 'SystemName', 'TagId', 'WaitHint')

        foreach ($instance in $instances) {
            $svc = [ordered]@{}
            foreach ($propName in $serviceProperties) {
                # A direct read: strict mode is off here, so a property the instance lacks reads as $null, which is what the column wants.
                $value = $instance.$propName
                if ($propName -eq 'InstallDate' -and $null -ne $value) {
                    # InstallDate arrives from CIM as a [datetime]. A value that does not convert or format nulls out rather than throwing.
                    try {
                        $svc[$propName] = ([datetime]$value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
                    } catch {
                        $svc[$propName] = $null
                    }
                } else {
                    $svc[$propName] = $value
                }
            }

            $execPath = Get-ServiceInventoryExecutablePath -PathName $svc['PathName']
            $svc['ExecutablePath'] = $execPath
            $svc['Sddl'] = $null
            $svc['SddlExitCode'] = $null
            $svc['SddlStdOut'] = $null
            $svc['StartNameSid'] = $null

            [void]$services.Add([pscustomobject]$svc)
        }

        $services.Sort( [Comparison[object]] { param($a, $b) [string]::Compare($a.Name, $b.Name, [System.StringComparison]::OrdinalIgnoreCase) } )
        # .ToArray(), not @(...): wrapping a generic List[object] with the array subexpression operator here hits a PowerShell dynamic-binder mismatch ("Argument types do not match") once enough CIM types have been loaded in the session.
        $services = $services.ToArray()

        $serviceCount = $services.Count
        #endregion

        #region Security descriptors
        $sddlFailedCount = 0
        $sddlDurationMs = 0

        $scExists = $false
        try {
            # -ErrorAction Stop so a failing read of the path lands in the catch and is named, rather than being swallowed as a plain "not found" when the worker runs at Continue in a remote session.
            $scExists = Test-Path -LiteralPath $ScPath -ErrorAction Stop
        } catch {
            $errors += "test sc path: $($_.Exception.Message)"
        }

        if (-not $scExists) {
            $errors += "sc path not found: $ScPath"
            $sddlFailedCount = $services.Count
        } else {
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
                } catch {
                    $errors += "sc sdshow $($svc.Name) invocation failed: $($_.Exception.Message)"
                    $invocationFailed = $true
                } finally {
                    $ErrorActionPreference = $prevEap
                }

                $trimmedOut = $stdOut.Trim()
                # The error text embeds native stdout, so every run of whitespace, line breaks included, collapses to one space, while SddlStdOut keeps the original text.
                $collapsedOut = $trimmedOut -replace '\s+', ' '
                if ($exitCode -eq 0) {
                    foreach ($line in ($stdOut -split "`r`n|`n|`r")) {
                        if ($line.TrimStart().StartsWith('D:')) { $sddlLine = $line.TrimStart(); break }
                    }
                }

                if ($invocationFailed) {
                    $sddlFailedCount++
                } elseif ($exitCode -ne 0 -or -not $sddlLine) {
                    $errors += "sc sdshow $($svc.Name) exit ${exitCode}: $collapsedOut"
                    $sddlFailedCount++
                }

                $svc.Sddl = $sddlLine
                $svc.SddlExitCode = $exitCode
                $svc.SddlStdOut = $trimmedOut
            }
            $stopwatchSddl.Stop()
            $sddlDurationMs = [int]$stopwatchSddl.ElapsedMilliseconds
        }
        #endregion

        #region Accounts
        $accounts = @()
        $accountCount = 0
        $accountUnresolvedCount = 0
        $accountsDurationMs = 0

        $stopwatchAccounts = [System.Diagnostics.Stopwatch]::StartNew()

        # The grouping, every lookup and the fill-back all sit inside one try/catch, so a failure anywhere in this step (an exotic StartName value included) never stops the binaries step that follows: the account data for this run is simply empty, with the reason in $errors.
        try {
            # First spelling seen per case-insensitive StartName is kept as the account's Token, so two services differing only by StartName casing still resolve to one account row.
            $tokenServiceNames = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $tokenOrder = New-Object System.Collections.Generic.List[string]
            foreach ($svc in $services) {
                $startName = $svc.StartName
                if ([string]::IsNullOrEmpty($startName)) { continue }
                if (-not $tokenServiceNames.ContainsKey($startName)) {
                    $tokenServiceNames[$startName] = New-Object System.Collections.Generic.List[string]
                    [void]$tokenOrder.Add($startName)
                }
                $tokenServiceNames[$startName].Add($svc.Name)
            }

            $tokenOrder.Sort( [Comparison[string]] { param($a, $b) [string]::Compare($a, $b, [System.StringComparison]::Ordinal) } )

            $accountByToken = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($token in $tokenOrder) {
                # A leading * (the secedit export form) is ignored for the Kind test only, never for the token itself.
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
                        # The innermost exception's own message, not the method-invocation wrapper, trimmed and with every run of whitespace, line breaks included, collapsed to one space, so a NotFound account's Error is always a single line.
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $acctError = ([string]$rawMessage).Trim() -replace '\s+', ' '
                    }
                } else {
                    $lookupName = $token
                    try {
                        if ($token -ieq 'LocalSystem') {
                            # The Service Control Manager's own alias, not a real account, so it never goes through a lookup.
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

                # The list was built in this step and is read nowhere else after this point, so it is sorted in place rather than copied first.
                $serviceNamesForToken = $tokenServiceNames[$token]
                # Sorted with the same comparer the Services array itself uses, ordinal case-insensitive.
                $serviceNamesForToken.Sort( [Comparison[string]] { param($a, $b) [string]::Compare($a, $b, [System.StringComparison]::OrdinalIgnoreCase) } )

                $accountObject = [pscustomobject]@{
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

                if ($status -eq 'NotFound') { $accountUnresolvedCount++ }
            }

            $accountCount = $accounts.Count

            foreach ($svc in $services) {
                $startName = $svc.StartName
                if ([string]::IsNullOrEmpty($startName)) {
                    $svc.StartNameSid = $null
                    continue
                }
                $matchedAccount = $accountByToken[$startName]
                if (($null -ne $matchedAccount) -and ($matchedAccount.Status -eq 'Resolved')) {
                    $svc.StartNameSid = $matchedAccount.Sid
                } else {
                    $svc.StartNameSid = $null
                }
            }
        } catch {
            $errors += "accounts: $($_.Exception.Message)"
            $accounts = @()
            $accountCount = 0
            $accountUnresolvedCount = 0
            foreach ($svc in $services) { $svc.StartNameSid = $null }
        } finally {
            $stopwatchAccounts.Stop()
            $accountsDurationMs = [int]$stopwatchAccounts.ElapsedMilliseconds
        }
        #endregion

        #region Binaries
        $binaries = @()
        $binaryCount = 0
        $binaryMissingCount = 0
        $binariesDurationMs = 0

        $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $execPathList = New-Object System.Collections.Generic.List[string]
        foreach ($svc in $services) {
            $ep = $svc.ExecutablePath
            if ($ep -and $seenPaths.Add($ep)) { [void]$execPathList.Add($ep) }
        }
        $execPathList.Sort( [Comparison[string]] { param($a, $b) [string]::Compare($a, $b, [System.StringComparison]::Ordinal) } )

        $stopwatchBinaries = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($path in $execPathList) {
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

            try {
                $exists = Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop
            } catch {
                $exists = $false
            }

            if (-not $exists) {
                $binError = 'not found'
                $errors += "binary ${path}: not found"
                $binaryMissingCount++
            } else {
                try {
                    $fileInfo = Get-Item -LiteralPath $path -ErrorAction Stop
                    $length = [int64]$fileInfo.Length
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
                } catch {
                    $binError = "binary ${path}: $($_.Exception.Message)"
                    $errors += $binError
                    $binaryMissingCount++
                }
            }

            $binaries += [pscustomobject]@{
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
        $binariesDurationMs = [int]$stopwatchBinaries.ElapsedMilliseconds
        $binaryCount = $binaries.Count
        #endregion

        #region Return
        $collectedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

        [pscustomobject]@{
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
            PartOfDomain        = [bool]$partOfDomain
            IsElevated          = [bool]$isElevated
            DomainRole          = [int]$domainRole
            CollectedUtc        = $collectedUtc
            ComputerId          = $computerId
            MachineGuid         = $machineGuid
            MachineSid          = $machineSid
            DomainSid           = $domainSid
            ComputerAccountSid  = $computerAccountSid
            DomainNetbiosName   = $domainNetbiosName
            ScPath              = $ScPath
            ServiceCount        = [int]$serviceCount
            SddlFailedCount     = [int]$sddlFailedCount
            BinaryCount         = [int]$binaryCount
            BinaryMissingCount  = [int]$binaryMissingCount
            AccountCount        = [int]$accountCount
            AccountUnresolvedCount = [int]$accountUnresolvedCount
            ServicesDurationMs  = [int]$servicesDurationMs
            SddlDurationMs      = [int]$sddlDurationMs
            AccountsDurationMs  = [int]$accountsDurationMs
            BinariesDurationMs  = [int]$binariesDurationMs
            Services            = @($services)
            Accounts            = @($accounts)
            Binaries            = @($binaries)
            Errors              = @($errors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' })
        }
        #endregion
    }
}
