<#PSScriptInfo

.DESCRIPTION Collects the description of the computer, its hardware, its installed updates and its Windows features from local or remote computers

.VERSION 1.0.0

.GUID b496bb44-5da6-4c35-9fa5-dce7acf1d88d

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-SystemInventory
function Get-SystemInventory {

    <#
    .SYNOPSIS
        Collects the description of the computer, its hardware, its installed updates and its
        Windows features from local or remote computers.

    .DESCRIPTION
        Collects the description of the local computer in-process or of remote computers over
        WinRM (one Invoke-Command call for every remote target): the computer system, the
        operating system, the firmware and its security state (BIOS, Secure Boot, TPM, Device
        Guard), the page files, the domain membership with its SIDs, and one table each for the
        processors, the memory modules, the disks, the volumes, the network adapters, the
        installed updates and the Windows features. Every value is read through CIM, the
        registry or a cmdlet and nothing is interpreted: a status or type code stays the number
        the class reports. The features come from two sources, the Win32_OptionalFeature class
        and the DISM feature list (Get-WindowsOptionalFeature -Online), and a feature row holds
        the state of both, because each source folds two of the four states Windows keeps into
        one and not the same two. The DISM list needs elevation, adds a few seconds on a
        server and 12 to 14 seconds on Windows 11, and makes Windows write a trace to dism.log
        on the target. -SkipDismFeatures leaves it out. Each distinct account that installed
        an update is looked up once and resolved to its SID. An application package SID or a
        capability SID is no account: it is not looked up and is written to appcontainers.json
        instead of accounts.json. The raw files are written to a per-computer folder under
        -OutputPath together with the identity of the computer and every error seen on the
        way. The analysis is done by a separate tool. This module only collects.

        Prerequisites, and nothing beyond them: Windows PowerShell 5.1 on the target. Run
        elevated for a complete collection. Without administrative rights the worker adds the
        error line 'not elevated: the TPM, the Secure Boot state and the DISM feature list are
        not read' (with -SkipDismFeatures: 'not elevated: the TPM and the Secure Boot state are
        not read'), so that computer's row comes back Partial with IsElevated False and holds
        everything the caller could read. Remote targets additionally need WinRM reachable
        from the caller. Local targets never use WinRM. Remote targets called without
        -Credential use the caller's own identity, exactly like any other Invoke-Command call.
        Nothing in this module is specific to any domain, server name, or account. It works
        unchanged on a domain-joined computer or on a workgroup computer.

        Each computer's system.json also carries a SID reference of four values: MachineSid, the
        SID of the computer's own account database (the local account with RID 500, read through
        CIM, without the RID), and DomainSid, ComputerAccountSid and DomainNetbiosName, read from
        the computer's own domain account through the same account lookup the module uses for
        update accounts, only on a domain-joined computer. No Active Directory module and no
        LDAP is used. A domain controller has no MachineSid, and a workgroup computer has no
        domain values. Those stay null. -SkipSidReference leaves all four null in system.json.
        The Domain section of computer.json always holds the same four values.

        Writes <OutputPath>\RemoteSystem-<yyyyMMdd-HHmmss>Z\ containing run.json and one folder
        per computer that was actually reached. Without -OutputPath the run folder is created in
        the current location. Each computer folder holds system.json, summary.json, computer.json
        and, by default, processors.json, memory.json, disks.json, volumes.json, adapters.json,
        hotfixes.json, features.json, accounts.json and appcontainers.json. computer.json is
        one object with the sections ComputerSystem, OperatingSystem, Bios, BaseBoard,
        Enclosure, Product, Firmware, Tpm, DeviceGuard, TimeZone, PageFiles and Domain. A
        section is null when its source does not exist on the computer, returned nothing or
        could not be read. -OutputFormat Csv writes the csv file of each table instead, and
        Both writes both. A value that is a list is written in csv as its elements joined with
        a vertical bar. The same choice decides whether results.csv is written to the run
        folder. run.json always holds the results, whatever the format. Every failure short of
        a bad -OutputPath or an empty -ComputerName list becomes a result row plus one
        Write-Warning. It is never a terminating error.

        Results are completed as they arrive rather than after every target has answered: each
        remote result has its folder written and its row built as soon as it arrives, and the
        reference to it is dropped before the next one is read.

    .PARAMETER ComputerName
        Targets. '.', 'localhost', '127.0.0.1', '::1', the local NetBIOS name and the local FQDN
        (case-insensitive) run in-process without WinRM. Everything else goes through one
        Invoke-Command call. Accepts pipeline input by value and by property name. Duplicates are
        removed case-insensitively. The first-seen order is kept. Defaults to the local computer
        name when nothing is supplied.

    .PARAMETER Credential
        Passed to Invoke-Command for remote targets only. Ignored for local targets (a
        Write-Verbose line records that it was ignored). When omitted, remote targets are
        contacted with the caller's own identity.

    .PARAMETER UseSSL
        Connects to remote targets over WinRM HTTPS (port 5986) instead of HTTP. Each target
        needs an HTTPS listener with a certificate the calling computer trusts, and the name you
        pass must match the certificate's subject or subject alternative name, which is normally
        the computer's fully qualified domain name (FQDN). A short name or an IP address fails
        the certificate name check with WinRM error 12175. Certificate checks are never skipped:
        the module offers no SkipCACheck or SkipCNCheck option, by design. Ignored for local
        targets, which never use WinRM. Recorded as UseSSL in run.json.

    .PARAMETER OutputPath
        Root folder for the run. A value must be given when the parameter is used, and an empty
        value is refused. Leaving the parameter out writes to the current file-system location,
        so a call made from a drive such as HKLM: writes to the last file-system location of the
        session. A given value may be relative. It is resolved once, against the current
        location, before any collection starts. Created if missing. Must be writable. This is
        tested by creating the run folder before any collection starts, so a bad -OutputPath
        fails before any target is contacted, and a run folder that turned out not to be
        writable is removed again.

    .PARAMETER OutputFormat
        Json, Csv or Both. Defaults to Json. Selects which file of each tabular pair is written:
        processors, memory, disks, volumes, adapters, hotfixes, features, accounts and
        appcontainers in every computer folder, and results.csv in the run folder. Json writes
        the json files, Csv the csv files, Both both. run.json, system.json, summary.json and
        computer.json have no csv twin and are written whatever the format. Recorded as
        OutputFormat in run.json.

    .PARAMETER ThrottleLimit
        Passed to Invoke-Command for remote targets. From 1 to 256. Defaults to 32.

    .PARAMETER SkipSidReference
        Leaves the SID reference unread in system.json: MachineSid, DomainSid, ComputerAccountSid
        and DomainNetbiosName are null there, and run.json records SkipSidReference true. Meant
        for a caller that runs several collectors against the same computers and needs the
        reference from one of them only, as RemoteBaseline does. The Domain section of
        computer.json is still filled. Without the switch every run reads the reference once.

    .PARAMETER SkipDismFeatures
        Does not read the DISM feature list (Get-WindowsOptionalFeature -Online). That read is the
        only one of the module that makes Windows write on the target, a trace in dism.log, and the
        slowest one: about 4 s on a server and 12 to 14 s on Windows 11. The read is recorded as
        Skipped, which is no error and does not change Status. DismState is null on every feature
        row, PayloadRemovedFeatureCount and DismOnlyFeatureCount are null, ReadSkippedCount in
        summary.json is 1, and run.json records SkipDismFeatures true. The class feature list is
        still read.

    .EXAMPLE
        PS C:\> Get-SystemInventory -ComputerName 'ws01.contoso.com' -Credential (Get-Credential) -OutputPath C:\SystemRuns | Format-List

        ComputerName           : ws01.contoso.com
        ComputerId             : 11111111-2222-3333-4444-555555555501
        Status                 : Success
        Transport              : WinRM
        OutputFolder           : C:\SystemRuns\RemoteSystem-20261118-200833Z\WS01_26200_20261118-200849Z
        IsElevated             : True
        ReadCount              : 27
        ReadFailedCount        : 0
        HotfixCount            : 7
        AccountCount           : 1
        AccountUnresolvedCount : 0
        Error                  :
        ErrorCount             : 0
        Errors                 : {}

        Collects from one Windows 11 workstation over WinRM with an explicit credential that is
        an administrator on the target. All 27 reads returned, seven installed updates were
        listed, and the row is Success. The DISM feature list adds 12 to 14 s to a collection
        of Windows 11.

    .EXAMPLE
        PS C:\SystemRuns> '.', 'localhost', 'WS02', 'NOSUCHHOST01' |
            Get-SystemInventory -OutputPath 'out' |
            Format-Table -Property ComputerName, ComputerId, Status, Transport, IsElevated, ReadCount, ReadFailedCount, HotfixCount, ErrorCount

        WARNING: .: not elevated: the TPM, the Secure Boot state and the DISM feature list are not read
        WARNING: localhost: not elevated: the TPM, the Secure Boot state and the DISM feature list are not read
        WARNING: WS02: not elevated: the TPM, the Secure Boot state and the DISM feature list are not read
        WARNING: NOSUCHHOST01: Connecting to remote server NOSUCHHOST01 failed with the following error message : The WinRM client cannot process the request. If the authentication scheme is different from Kerberos, or if the client computer is not joined to a domain, then HTTPS transport must be used or the destination machine must be added to the TrustedHosts configuration setting. Use winrm.cmd to configure TrustedHosts. Note that computers in the TrustedHosts list might not be authenticated. You can get more information about that by running the following command: winrm help config. For more information, see the about_Remote_Troubleshooting Help topic.

        ComputerName ComputerId                           Status  Transport IsElevated ReadCount ReadFailedCount HotfixCount ErrorCount
        ------------ ----------                           ------  --------- ---------- --------- --------------- ----------- ----------
        .            11111111-2222-3333-4444-555555555503 Partial Local          False        24               3           5          4
        localhost    11111111-2222-3333-4444-555555555503 Partial Local          False        24               3           5          4
        WS02         11111111-2222-3333-4444-555555555503 Partial Local          False        24               3           5          4
        NOSUCHHOST01                                      Failed  WinRM                                                               1

        Run from a Windows 11 workstation in a session that is not elevated. The three local
        aliases give identical rows. Without elevation the Secure Boot, TPM and DISM feature
        list reads fail, so ReadFailedCount is 3 and each row is Partial, while the other 24
        reads returned. The name that does not resolve comes back as a Failed result row, not
        a terminating error.

    .EXAMPLE
        PS C:\SystemRuns> Get-SystemInventory -ComputerName 'srv01.contoso.com' -UseSSL -OutputPath 'out'

        Collects from one server over WinRM HTTPS (port 5986). The name is the FQDN, which
        matches the subject of the server's listener certificate. The short name SRV01 would
        fail the certificate name check with WinRM error 12175.

    .EXAMPLE
        PS C:\SystemRuns> Get-SystemInventory -ComputerName 'ws01.contoso.com' -SkipDismFeatures -OutputPath 'out'

        Collects from one workstation without the DISM feature list. The collection is shorter
        and Windows writes no trace to dism.log on the target. The DismState column of
        features.json is null on every row, and the unelevated line, when it applies, no longer
        names the DISM feature list.

    .EXAMPLE
        PS C:\SystemRuns> Get-SystemInventory | Select-Object -Property ComputerName, Status, OutputFolder

        ComputerName Status  OutputFolder
        ------------ ------  ------------
        WS02         Partial C:\SystemRuns\RemoteSystem-20261118-172558Z\WS02_26200_20261118-172607Z

        Without -OutputPath the run folder is created in the current location. The default
        -OutputFormat Json writes run.json and, in the computer folder, computer.json, system.json,
        summary.json and the nine json files of the tables, accounts and appcontainers, and no csv file.

    .EXAMPLE
        PS C:\SystemRuns> Get-SystemInventory -OutputPath C:\SystemRuns\both -OutputFormat Both | Select-Object -Property ComputerName, Status, ReadCount, ReadFailedCount, HotfixCount

        ComputerName Status  ReadCount ReadFailedCount HotfixCount
        ------------ ------  --------- --------------- -----------
        WS02         Partial        24               3           5

        Writes the json and the csv file of every pair, so results.csv, accounts.csv,
        adapters.csv, appcontainers.csv, disks.csv, features.csv, hotfixes.csv, memory.csv,
        processors.csv and volumes.csv are written next to their json files.

    .EXAMPLE
        PS C:\SystemRuns\RemoteSystem-20261118-200833Z> (Get-Content .\WS01_26200_20261118-200849Z\computer.json -Raw | ConvertFrom-Json).Firmware | Format-Table

        SecureBoot SecureBootSupported UEFISecureBootEnabled BootDiskPartitionStyle
        ---------- ------------------- --------------------- ----------------------
              True                True                     1                      2

        Reads the Firmware section of one computer.json. Secure Boot is on, the firmware supports
        it, and the boot disk is GPT (2). The section is an object on every run. A value that
        could not be read is null in it, never absent.

    .NOTES
        FUNCTION: Get-SystemInventory
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        System.String[]. ComputerName is accepted from the pipeline, by value and by property
        name.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteSystem.Result

    .LINK
        https://github.com/tomstryhn/RemoteBaseline
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [String[]]$ComputerName = @($env:COMPUTERNAME),

        [System.Management.Automation.PSCredential]
        $Credential,

        [Switch]$UseSSL,

        [ValidateNotNullOrEmpty()]
        [String]$OutputPath,

        [ValidateSet('Json', 'Csv', 'Both')]
        [String]$OutputFormat = 'Json',

        [ValidateRange(1, 256)]
        [Int]$ThrottleLimit = 32,

        [Switch]$SkipSidReference,

        [Switch]$SkipDismFeatures
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $collectedNames = @()
    }

    process {
        if ($ComputerName) {
            $collectedNames += @($ComputerName)
        }
    }

    end {
        # Resolved once here, against the caller's current location, not $PSScriptRoot or any other implicit
        # base, and used everywhere after. Without -OutputPath the root is the session's file-system
        # location, which is a folder even when the caller stands in a drive such as HKLM:. The parameter
        # refuses an empty value, so a bound OutputPath always holds a path.
        if ($PSBoundParameters.ContainsKey('OutputPath')) {
            $resolvedOutputPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
        }
        else {
            $resolvedOutputPath = $PSCmdlet.SessionState.Path.CurrentFileSystemLocation.ProviderPath
        }

        $resolvedNames = @(Resolve-SystemInventoryComputerList -ComputerName $collectedNames)
        if ($resolvedNames.Count -eq 0) {
            throw 'ComputerName is empty after removing blanks and duplicates.'
        }

        $localNames = @()
        $remoteNames = @()
        foreach ($name in $resolvedNames) {
            if (Test-SystemInventoryLocalName -Name $name) {
                $localNames += $name
            }
            else {
                $remoteNames += $name
            }
        }

        $runFolder = Initialize-SystemInventoryRunFolder -OutputPath $resolvedOutputPath

        $startUtc = (Get-Date).ToUniversalTime()

        $rowMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $unattributedNames = [System.Collections.Generic.List[String]]::new()
        # Messages of remote errors that matched no requested computer and no unresolved name. Recorded here
        # and warned about at the end of the function, for the same reason as the unattributed results: a
        # warning is a terminating error under a caller's -WarningAction Stop, and it must not end the run
        # before the files exist.
        $unattributedErrorMessages = [System.Collections.Generic.List[String]]::new()

        if ($localNames.Count -gt 0) {
            # Local aliases share one worker run and one OutputFolder. The worker runs exactly once per call
            # no matter how many aliases were requested, and each alias still gets its own row.
            if ($Credential) {
                Write-Verbose "Credential ignored for local targets: $($localNames -join ', ')."
            }
            if ($UseSSL) {
                Write-Verbose "UseSSL ignored for local targets: $($localNames -join ', ')."
            }
            Write-Verbose "Collecting locally: $($localNames -join ', ')"

            $localWorkerObject = $null
            $localExtraErrors = @()
            try {
                $localWorkerObject = Invoke-SystemInventoryLocal -SkipSidReference:$SkipSidReference -SkipDismFeatures:$SkipDismFeatures
            }
            catch {
                $localExtraErrors += $_.Exception.Message
            }

            # The first alias completes the computer and writes the folder. Every later alias copies that row
            # and changes only ComputerName, so no two rows for one folder can ever disagree on Status, a
            # count or Errors.
            $firstLocalRow = $null
            foreach ($name in $localNames) {
                if ($null -eq $firstLocalRow) {
                    $firstLocalRow = Complete-SystemInventoryComputer -RequestedComputerName $name -Transport 'Local' -RunFolder $runFolder -WorkerObject $localWorkerObject -ExtraErrors $localExtraErrors -OutputFormat $OutputFormat
                    $rowMap[$name] = $firstLocalRow
                }
                else {
                    $aliasRow = $firstLocalRow.PSObject.Copy()
                    $aliasRow.ComputerName = $name
                    $rowMap[$name] = $aliasRow
                }
            }
        }

        if ($remoteNames.Count -gt 0) {
            Write-Verbose "Collecting remotely over WinRM: $($remoteNames -join ', ')"

            # Rows are built from the worker results as they stream in, then errors are mapped onto those rows
            # afterward, never the reverse, so an error never overwrites a row a worker result already
            # produced. Results are completed as they arrive rather than after every target has answered: each
            # one is completed and released inside -OnResult, before the next one is read from the pipeline.
            $matchedResultNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

            # The callback never throws. It runs inside the Invoke-Command pipeline, so an exception here
            # would end the whole run and discard every other computer's result. A failure while one result is
            # completed becomes a Failed row for that computer instead, and the run goes on.
            $onRemoteResult = {
                param($Res)

                $pcName = $null
                $requested = $null
                try {
                    $pcName = Get-SystemInventorySafeProperty -InputObject $Res -Name 'PSComputerName' -Default $null
                    foreach ($rn in $remoteNames) {
                        if ($rn -ieq $pcName) {
                            $requested = $rn
                            break
                        }
                    }
                    if (-not $requested) {
                        # A result whose PSComputerName matches no requested name gets no folder and no row:
                        # it would never be emitted, because rows are built from the requested names only. The
                        # warning is written as the last statement of the function (see the end), not here, so
                        # a caller's -WarningAction Stop cannot end the pipeline halfway through.
                        [Void]$unattributedNames.Add([String]$pcName)
                        return
                    }

                    $row = Complete-SystemInventoryComputer -RequestedComputerName $requested -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $Res -ExtraErrors @() -OutputFormat $OutputFormat
                    $rowMap[$requested] = $row
                    [Void]$matchedResultNames.Add($requested)
                }
                catch {
                    $callbackMessage = $_.Exception.Message
                    if ($requested) {
                        $rowMap[$requested] = ConvertTo-SystemInventoryResultRow -ComputerName $requested -Status 'Failed' -Transport 'WinRM' -Errors @("host: $callbackMessage")
                        [Void]$matchedResultNames.Add($requested)
                    }
                    else {
                        # No requested name could be found for this result, so no row can carry the error. It
                        # is recorded as unattributed, which is reported at the end of the function.
                        [Void]$unattributedNames.Add([String]$pcName)
                    }
                }
            }

            $remoteResult = $null
            $remoteCallError = $null
            try {
                $remoteResult = Invoke-SystemInventoryRemote -ComputerName $remoteNames -Credential $Credential -ThrottleLimit $ThrottleLimit -OnResult $onRemoteResult -UseSSL:$UseSSL -SkipSidReference:$SkipSidReference -SkipDismFeatures:$SkipDismFeatures
            }
            catch {
                $remoteCallError = $_.Exception.Message
            }

            $pendingErrors = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($rn in $remoteNames) {
                $pendingErrors[$rn] = New-Object 'System.Collections.Generic.List[string]'
            }

            if ($null -ne $remoteResult) {
                foreach ($err in @($remoteResult.Errors)) {
                    $message = Get-SystemInventorySafeProperty -InputObject $err -Name 'Exception' -Default $null
                    $messageText = if ($message) { Get-SystemInventorySafeProperty -InputObject $message -Name 'Message' -Default "$err" } else { "$err" }

                    $matchedName = Resolve-SystemInventoryRemoteErrorName -ErrorRecord $err -RemoteNames $remoteNames

                    if ($matchedName) {
                        $pendingErrors[$matchedName].Add($messageText)
                    }
                    else {
                        $unresolvedNames = @($remoteNames | Where-Object { -not $matchedResultNames.Contains($_) })
                        if ($unresolvedNames.Count -gt 0) {
                            foreach ($rn in $unresolvedNames) {
                                $pendingErrors[$rn].Add($messageText)
                            }
                        }
                        else {
                            [Void]$unattributedErrorMessages.Add($messageText)
                        }
                    }
                }
            }

            foreach ($rn in $remoteNames) {
                if ($matchedResultNames.Contains($rn)) {
                    $row = $rowMap[$rn]
                    foreach ($msg in $pendingErrors[$rn]) {
                        # Collapsed here as well: a late message is appended after
                        # ConvertTo-SystemInventoryResultRow has already built the row, so that function's
                        # collapse never sees it, and a remote connection error is several lines.
                        $row.Errors += (([String]$msg).Trim() -replace '\s+', ' ')
                    }
                    # A late host-side error appended here after the row was already built from the worker
                    # object, so ErrorCount and Error are recomputed from Errors rather than left at the
                    # counts the worker object alone produced.
                    $row.ErrorCount = @($row.Errors).Count
                    if ([String]::IsNullOrEmpty($row.Error) -and $row.ErrorCount -gt 0) {
                        $row.Error = $row.Errors[0]
                    }
                }
                else {
                    $extraErrors = @($pendingErrors[$rn])
                    if ($extraErrors.Count -eq 0) {
                        $extraErrors = @( $(if ($remoteCallError) { $remoteCallError } else { 'no result and no error returned' }) )
                    }
                    $row = Complete-SystemInventoryComputer -RequestedComputerName $rn -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $null -ExtraErrors $extraErrors -OutputFormat $OutputFormat
                    $rowMap[$rn] = $row
                }
            }
        }

        $rows = @()
        foreach ($name in $resolvedNames) {
            $rows += $rowMap[$name]
        }

        $endUtc = (Get-Date).ToUniversalTime()

        $runInfo = [PSCustomObject]@{
            RunId              = Split-Path -Path $runFolder -Leaf
            Collector          = 'RemoteSystem'
            CollectorVersion   = $MyInvocation.MyCommand.Module.Version.ToString()
            SchemaVersion      = '1.5'
            HostComputer       = $env:COMPUTERNAME
            HostComputerId     = Get-SystemInventoryHostComputerId
            HostUser           = "$env:USERDOMAIN\$env:USERNAME"
            PSVersion          = $PSVersionTable.PSVersion.ToString()
            StartUtc           = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            EndUtc             = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            RequestedComputers = @($resolvedNames)
            ThrottleLimit      = $ThrottleLimit
            UseSSL             = [Bool]$UseSSL
            SkipSidReference   = [Bool]$SkipSidReference
            SkipDismFeatures   = [Bool]$SkipDismFeatures
            OutputFormat       = $OutputFormat
            Results            = @($rows)
        }

        try {
            $runJson = $runInfo | ConvertTo-Json -Depth 8
            Write-SystemInventoryTextFile -Path (Join-Path $runFolder 'run.json') -Content $runJson
        }
        catch {
            Write-Warning "Failed to write run.json: $($_.Exception.Message)"
        }

        # results.csv is the csv twin of the Results array in run.json, so it follows the format.
        if ($OutputFormat -ne 'Json') {
            try {
                $csvRows = @($rows | Select-Object -Property * -ExcludeProperty Errors)
                $csvPath = Join-Path $runFolder 'results.csv'
                Write-SystemInventoryCsvFile -Row $csvRows -Path $csvPath
            }
            catch {
                Write-Warning "Failed to write results.csv: $($_.Exception.Message)"
            }
        }

        foreach ($row in $rows) {
            if ($row.Status -ne 'Success') {
                Write-Warning "$($row.ComputerName): $($row.Error)"
            }
            $row
        }

        # The last statements of the function, after the run files are written and every row is emitted: a
        # caller's -WarningAction Stop then ends a finished run and can no longer lose the run files.
        foreach ($unattributedName in $unattributedNames) {
            Write-Warning "Unattributed remote result, matched no requested computer name: $unattributedName"
        }
        foreach ($unattributedMessage in $unattributedErrorMessages) {
            Write-Warning "Unattributed remote error, matched no requested computer name: $unattributedMessage"
        }
    }
}
#endregion
