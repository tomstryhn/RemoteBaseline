<#PSScriptInfo

.DESCRIPTION Collects every Windows event log, its configuration, size, time frame, policy values, archive files and security descriptor from local or remote computers

.VERSION 1.0.0

.GUID 2ada1409-3dbc-4982-9a82-4ae978deac28

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-EventLogInventory
function Get-EventLogInventory {

    <#
    .SYNOPSIS
        Collects every Windows event log, its configuration, size, time frame, policy values,
        archive files and security descriptor from local or remote computers.

    .DESCRIPTION
        Collects every event log of the local computer in-process or of remote computers over
        WinRM (one Invoke-Command call for every remote target): the configuration of each log
        (type, mode, isolation, maximum size, file path, whether it is enabled and its
        security descriptor), the state of its file (size, record count, the three
        file times), the id and time of its oldest and newest record, the values the event log
        policy key holds for it, its archive files beside the log file, and the security
        identifiers its security descriptor names. The Analytical and Debug logs are listed too.
        No event is exported and no event content is read: the collector describes the logs, not
        what they hold. Nothing is interpreted. Each distinct security identifier of an account
        is looked up once and resolved to a name. An application package SID or a capability SID
        names an application and not an account, so it is not looked up: it is classed from its
        text and listed in appcontainers.json with a null Name. The raw files are written to a
        per-computer folder under -OutputPath together with the identity of the computer and
        every error seen on the way.

        Prerequisites, and nothing beyond them: Windows PowerShell 5.1 on the target. Run
        elevated for a complete collection. Without administrative rights the worker adds the
        error line 'not elevated: event logs the caller cannot open are not listed', so that
        computer's row comes back Partial with IsElevated False. Every log still gets its row,
        and a log whose file information the caller may not read has its file columns empty and
        its reason in ReadError. Remote targets additionally need WinRM reachable from the
        caller. Local targets never use WinRM. Remote targets called without -Credential use the
        caller's own identity, exactly like any other Invoke-Command call. Nothing in this
        module is specific to any domain, server name, or account. It works unchanged on a
        domain-joined computer or on a workgroup computer.

        Each computer's system.json also carries a SID reference of four values: MachineSid, the
        SID of the computer's own account database (the local account with RID 500, read through
        CIM, without the RID), and DomainSid, ComputerAccountSid and DomainNetbiosName, read from
        the computer's own domain account through the same account lookup the module uses for
        the security identifiers in the descriptors, only on a domain-joined computer. No Active
        Directory module and no LDAP is used. A domain controller has no MachineSid, and a
        workgroup computer has no domain values. Those stay null. -SkipSidReference leaves all
        four null.

        Writes <OutputPath>\RemoteEventLog-<yyyyMMdd-HHmmss>Z\ containing run.json and one
        folder per computer that was actually reached. Without -OutputPath the run folder is
        created in the current location. Each computer folder holds system.json, summary.json
        and, by default, logs.json, accounts.json and appcontainers.json. logs.json holds one row
        per log, sorted by name. -OutputFormat Csv writes logs.csv, accounts.csv and
        appcontainers.csv instead, and Both writes all six. The same choice decides whether
        results.csv is written to the run folder. run.json always holds the results, whatever
        the format. Every failure short of a bad -OutputPath or an empty -ComputerName list
        becomes a result row plus one Write-Warning. It is never a terminating error.

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
        logs, accounts and appcontainers in every computer folder, and results.csv in the run
        folder. Json writes the json files, Csv the csv files, Both both. run.json, system.json
        and summary.json have no csv twin and are written whatever the format. Recorded as
        OutputFormat in run.json.

    .PARAMETER ThrottleLimit
        Passed to Invoke-Command for remote targets. From 1 to 256. Defaults to 32.

    .PARAMETER SkipSidReference
        Leaves the SID reference unread: MachineSid, DomainSid, ComputerAccountSid and
        DomainNetbiosName are null in system.json, and run.json records SkipSidReference true.
        Meant for a caller that runs several collectors against the same computers and needs the
        reference from one of them only, as RemoteBaseline does. Without the switch every run
        reads it.

    .EXAMPLE
        PS C:\EventLogRuns> Get-EventLogInventory -ComputerName 'srv01.contoso.com' -Credential (Get-Credential) -OutputPath C:\EventLogRuns |
            Format-Table -Property ComputerName, Status, Transport, IsElevated, LogCount, LogReadFailedCount, SddlFailedCount, AccountCount, AccountUnresolvedCount, ErrorCount

        ComputerName      Status  Transport IsElevated LogCount LogReadFailedCount SddlFailedCount AccountCount AccountUnresolvedCount ErrorCount
        ------------      ------  --------- ---------- -------- ------------------ --------------- ------------ ---------------------- ----------
        srv01.contoso.com Success WinRM           True     1079                  0               0           21                      1          0

        Collects from a Windows Server 2022 server over WinRM, run elevated, in 3 s. All 1079 logs
        were read, the Analytical and Debug logs included. One of the 21 accounts the log
        descriptors name does not resolve to a name. That is data and does not change Status.

    .EXAMPLE
        PS C:\EventLogRuns> Get-EventLogInventory -OutputPath C:\EventLogRuns | Select-Object -Property * -ExcludeProperty Errors | Format-List

        ComputerName           : WS01
        ComputerId             : 11111111-2222-3333-4444-555555555501
        Status                 : Partial
        Transport              : Local
        OutputFolder           : C:\EventLogRuns\RemoteEventLog-20261118-172406Z\WS01_26200_20261118-172409Z
        IsElevated             : False
        LogCount               : 1250
        LogReadFailedCount     : 94
        SddlFailedCount        : 0
        AccountCount           : 21
        AccountUnresolvedCount : 1
        Error                  : not elevated: event logs the caller cannot open are not listed
        ErrorCount             : 95

        Collects from the local Windows 11 computer without administrative rights. Every one of
        the 1250 logs has a row, but 94 of them, the Security log among them, refuse the read of
        their file information. Their file and record columns are empty, their reason is in
        ReadError, and each adds one line to Errors (95 with the unelevated line). The row is
        Partial. An elevated run of a Windows 11 host read all of its logs with no refused one.

    .EXAMPLE
        PS C:\EventLogRuns> '.', 'NOSUCHHOST01' |
            Get-EventLogInventory -OutputPath 'out' |
            Format-Table -Property ComputerName, ComputerId, Status, Transport, LogCount, LogReadFailedCount, SddlFailedCount, AccountCount, ErrorCount

        ComputerName ComputerId                           Status  Transport LogCount LogReadFailedCount SddlFailedCount AccountCount ErrorCount
        ------------ ----------                           ------  --------- -------- ------------------ --------------- ------------ ----------
        .            11111111-2222-3333-4444-555555555501 Partial Local         1250                 94               0           21         95
        NOSUCHHOST01                                      Failed  WinRM                                                                       1
        WARNING: .: not elevated: event logs the caller cannot open are not listed
        WARNING: NOSUCHHOST01: Connecting to remote server NOSUCHHOST01 failed with the following error message : The WinRM client cannot process the request. If the authentication scheme is different from Kerberos, or if the client computer is not joined to a domain, then HTTPS transport must be used or the destination machine must be added to the TrustedHosts configuration setting. Use winrm.cmd to configure TrustedHosts. Note that computers in the TrustedHosts list might not be authenticated. You can get more information about that by running the following command: winrm help config. For more information, see the about_Remote_Troubleshooting Help topic.

        Collects from the local computer and one name that does not resolve. That name comes
        back as a Failed result row and a warning, not a terminating error, and the local
        computer is collected as in the example above.

    .EXAMPLE
        PS C:\EventLogRuns> Get-EventLogInventory -ComputerName 'srv01.contoso.com' -UseSSL -OutputPath 'out'

        Collects from one server over WinRM HTTPS (port 5986). The name is the FQDN, which
        matches the subject of the server's listener certificate. The short name srv01 would
        fail the certificate name check with WinRM error 12175.

    .EXAMPLE
        PS C:\EventLogRuns> Get-EventLogInventory | Select-Object -Property ComputerName, Status, OutputFolder

        ComputerName Status  OutputFolder
        ------------ ------  ------------
        WS01         Partial C:\EventLogRuns\RemoteEventLog-20261118-172403Z\WS01_26200_20261118-172406Z

        Without -OutputPath the run folder is created in the current location. The default
        -OutputFormat Json writes logs.json, accounts.json and appcontainers.json, and no csv
        file.

    .EXAMPLE
        PS C:\EventLogRuns> Get-EventLogInventory -OutputPath C:\EventLogRuns -OutputFormat Both | Select-Object -Property ComputerName, Status, LogCount

        ComputerName Status  LogCount
        ------------ ------  --------
        WS01         Partial     1250

        Writes the json and the csv file of every pair, so results.csv, logs.csv, accounts.csv and
        appcontainers.csv are written next to their json files.

    .EXAMPLE
        PS C:\EventLogRuns> $logs = Get-Content .\RemoteEventLog-20261118-143840Z\DC02_20348_20261118-143845Z\logs.json -Raw | ConvertFrom-Json
        PS C:\EventLogRuns> $logs | Where-Object { $null -ne $_.PolicyMaxSize } |
            Format-Table -Property LogName, MaximumSizeInBytes, PolicyMaxSize, PolicyRetention

        LogName     MaximumSizeInBytes PolicyMaxSize PolicyRetention
        -------     ------------------ ------------- ---------------
        Application          134217728        131072 0
        Security            4194304000       4096000 0
        Setup                 67108864         65536 0
        System               134217728        131072 0

        Reads logs.json of an earlier run against a domain controller whose Group Policy sets the
        event log sizes. PolicyMaxSize is the value of the policy key in kilobytes, as stored,
        and MaximumSizeInBytes is the size the log has in effect. PolicyRetention is text
        because the policy stores it as a string.

    .NOTES
        FUNCTION: Get-EventLogInventory
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        System.String[]. ComputerName is accepted from the pipeline, by value and by property
        name.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteEventLog.Result

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

        [Switch]$SkipSidReference
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

        $resolvedNames = @(Resolve-EventLogInventoryComputerList -ComputerName $collectedNames)
        if ($resolvedNames.Count -eq 0) {
            throw 'ComputerName is empty after removing blanks and duplicates.'
        }

        $localNames = @()
        $remoteNames = @()
        foreach ($name in $resolvedNames) {
            if (Test-EventLogInventoryLocalName -Name $name) {
                $localNames += $name
            }
            else {
                $remoteNames += $name
            }
        }

        $runFolder = Initialize-EventLogInventoryRunFolder -OutputPath $resolvedOutputPath

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
                $localWorkerObject = Invoke-EventLogInventoryLocal -SkipSidReference:$SkipSidReference
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
                    $firstLocalRow = Complete-EventLogInventoryComputer -RequestedComputerName $name -Transport 'Local' -RunFolder $runFolder -WorkerObject $localWorkerObject -ExtraErrors $localExtraErrors -OutputFormat $OutputFormat
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
                    $pcName = Get-EventLogInventorySafeProperty -InputObject $Res -Name 'PSComputerName' -Default $null
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

                    $row = Complete-EventLogInventoryComputer -RequestedComputerName $requested -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $Res -ExtraErrors @() -OutputFormat $OutputFormat
                    $rowMap[$requested] = $row
                    [Void]$matchedResultNames.Add($requested)
                }
                catch {
                    $callbackMessage = $_.Exception.Message
                    if ($requested) {
                        $rowMap[$requested] = ConvertTo-EventLogInventoryResultRow -ComputerName $requested -Status 'Failed' -Transport 'WinRM' -Errors @("host: $callbackMessage")
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
                $remoteResult = Invoke-EventLogInventoryRemote -ComputerName $remoteNames -Credential $Credential -ThrottleLimit $ThrottleLimit -OnResult $onRemoteResult -UseSSL:$UseSSL -SkipSidReference:$SkipSidReference
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
                    $message = Get-EventLogInventorySafeProperty -InputObject $err -Name 'Exception' -Default $null
                    $messageText = if ($message) { Get-EventLogInventorySafeProperty -InputObject $message -Name 'Message' -Default "$err" } else { "$err" }

                    $matchedName = Resolve-EventLogInventoryRemoteErrorName -ErrorRecord $err -RemoteNames $remoteNames

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
                        # ConvertTo-EventLogInventoryResultRow has already built the row, so that function's
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
                    $row = Complete-EventLogInventoryComputer -RequestedComputerName $rn -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $null -ExtraErrors $extraErrors -OutputFormat $OutputFormat
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
            Collector          = 'RemoteEventLog'
            CollectorVersion   = $MyInvocation.MyCommand.Module.Version.ToString()
            SchemaVersion      = '1.5'
            HostComputer       = $env:COMPUTERNAME
            HostComputerId     = Get-EventLogInventoryHostComputerId
            HostUser           = "$env:USERDOMAIN\$env:USERNAME"
            PSVersion          = $PSVersionTable.PSVersion.ToString()
            StartUtc           = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            EndUtc             = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            RequestedComputers = @($resolvedNames)
            ThrottleLimit      = $ThrottleLimit
            UseSSL             = [Bool]$UseSSL
            SkipSidReference   = [Bool]$SkipSidReference
            OutputFormat       = $OutputFormat
            Results            = @($rows)
        }

        try {
            $runJson = $runInfo | ConvertTo-Json -Depth 8
            Write-EventLogInventoryTextFile -Path (Join-Path $runFolder 'run.json') -Content $runJson
        }
        catch {
            Write-Warning "Failed to write run.json: $($_.Exception.Message)"
        }

        # results.csv is the csv twin of the Results array in run.json, so it follows the format.
        if ($OutputFormat -ne 'Json') {
            try {
                $csvRows = @($rows | Select-Object -Property * -ExcludeProperty Errors)
                $csvPath = Join-Path $runFolder 'results.csv'
                Write-EventLogInventoryCsvFile -Row $csvRows -Path $csvPath
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
