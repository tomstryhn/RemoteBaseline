<#PSScriptInfo

.DESCRIPTION Collects every scheduled task with the fields of its definition, its account and its SID, its security descriptor, its run-time state and its action binary identity from local or remote computers

.VERSION 1.4.1

.GUID 40533d97-35b1-4617-99ce-9b78add027f4

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function Get-ScheduledTaskInventory {

    <#
    .SYNOPSIS
        Collects every scheduled task, the fields of its definition, its account, its security
        descriptor, its run-time state and its action binary identity from local or remote
        computers.

    .DESCRIPTION
        Collects every scheduled task on the local computer in-process or on remote computers over
        WinRM (one Invoke-Command call for every remote target), the same set the Task Scheduler
        console shows with hidden tasks turned on: the fields of each task's definition as the
        Task Scheduler service holds it (principal, actions, triggers, settings), the run-time
        state of each task, the account each task runs as and that account's SID, the security
        descriptor of each task, and the identity and signature of each binary an Exec action
        starts. Nothing is interpreted. Each distinct principal a task runs as is looked up once
        and resolved to its SID. The definition is read on the target and flattened into these
        fields, not kept as a file. The raw files are written to a per-computer folder under
        -OutputPath together with the identity of the computer and every error seen on the way. A
        separate project analyses the files and decides which tasks and which accounts need
        attention.

        The task list, the task definition and the run-time state come from the ScheduledTasks
        module, because its provider runs as SYSTEM and reads every task on the computer,
        including one whose access control list excludes the caller. The security descriptor the
        service actually enforces comes from the Task Scheduler COM interface instead, because no
        cmdlet returns it, and a task the COM interface refuses (the same access control list
        case) keeps every other field and is named in the errors, giving that computer's row
        Partial rather than Failed.

        Prerequisites, and nothing beyond them: the ScheduledTasks module present on the target
        (it ships with Windows 8 and Server 2012 and later), Windows PowerShell 5.1 on the target.
        Administrative rights are recommended but not required: without them the service withholds
        the tasks other users registered, and the worker adds the error line "not elevated: tasks
        the caller cannot open are not listed", so the row comes back Partial with IsElevated
        false and a shorter task list rather than Success. Remote targets additionally need WinRM
        reachable from the caller. Local targets never use WinRM. Remote targets called without
        -Credential use the caller's own identity, exactly like any other Invoke-Command call. Nothing in this module is specific to any domain, server name, or
        account. It works unchanged on a domain-joined computer or on a workgroup computer. The
        module runs in FullLanguage mode only, so a target in ConstrainedLanguage mode comes back
        Failed; the README's Known limits paragraph says why.

        Also reads four SID reference values on each target and writes them to system.json:
        MachineSid (the SID of the computer's own account database, no RID), and on a
        domain-joined computer DomainSid, ComputerAccountSid and DomainNetbiosName. MachineSid
        is read from the local account with RID 500 through CIM (Win32_UserAccount filtered on
        the computer's own name). The domain values are read from the computer's own domain
        account through the same account lookup the module uses for task accounts, only on a
        domain-joined computer. No Active Directory module and no LDAP is used.
        Win32_UserAccount lists no local account on a domain controller, so MachineSid is null
        there, and a workgroup computer has no domain values: they stay null.
        -SkipSidReference leaves all four unread.

        A missing binary is data, not an error, in one case. Windows ships two scheduled tasks
        whose program is not on the disk: \Microsoft\Windows\UpdateOrchestrator\UUS Failover Task
        on Server 2022 (%SystemRoot%\System32\failover.exe) and
        \Microsoft\Windows\UpdateOrchestrator\USO_UxBroker on Server 2025 and Windows 11
        (%SystemRoot%\System32\MusNotification.exe). When a missing binary is one of those two
        files in the target's own System32 and every task that names it sits under
        \Microsoft\Windows\UpdateOrchestrator\, it still counts in BinaryMissingCount and shows in
        binaries.json, binaries.csv and summary.json, but the worker adds no error line for it,
        so it does not turn the row Partial, and this function writes one warning per path:
        "<ComputerName>: binary <path>: not found (Windows ships no such file; not counted as an
        error)". The same file named by a task anywhere else, and any other missing or unreadable
        binary, is still an error line and gives Partial.

        Writes <OutputPath>\RemoteScheduledTask-<yyyyMMdd-HHmmss>Z\ containing run.json,
        results.csv, and one folder per computer that was actually reached. Every failure short of
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
        Root folder for the run. May be relative. Resolved once, against the current location,
        before any collection starts. Created if missing. Must be writable. This is tested by
        creating the run folder before any collection starts, so a bad -OutputPath fails before
        any target is contacted.

    .PARAMETER ThrottleLimit
        Passed to Invoke-Command for remote targets. From 1 to 256. Defaults to 32.

    .PARAMETER SkipSidReference
        Leaves the SID reference unread: MachineSid, DomainSid, ComputerAccountSid and
        DomainNetbiosName are null in system.json, and run.json records SkipSidReference true.
        Meant for a caller that runs several collectors against the same computers and needs the
        reference from one of them only, as RemoteBaseline does. Without the switch every run
        reads it.

    .EXAMPLE
        PS C:\> Import-Module .\RemoteScheduledTask\RemoteScheduledTask.psd1 -Force
        PS C:\> Get-ScheduledTaskInventory -OutputPath C:\TaskRuns -Verbose

        VERBOSE: Collecting locally: WS01
        WARNING: WS01: not elevated: tasks the caller cannot open are not listed

        ComputerName           : WS01
        ComputerId             : 11111111-2222-3333-4444-555555555501
        Status                 : Partial
        Transport              : Local
        OutputFolder           : C:\TaskRuns\RemoteScheduledTask-20261001-061254Z\WS01_26300_20261001-061304Z
        IsElevated             : False
        TaskCount              : 203
        XmlFailedCount         : 0
        SddlFailedCount        : 0
        BinaryCount            : 53
        BinaryMissingCount     : 0
        AccountCount           : 9
        AccountUnresolvedCount : 0
        Error                  : not elevated: tasks the caller cannot open are not listed
        ErrorCount             : 1
        Errors                 : {not elevated: tasks the caller cannot open are not listed}

        Collects from the local computer only, run without administrative rights on a workgroup
        Windows 11 laptop. The not elevated line in Errors, and Status Partial with IsElevated
        False, mark the count above as the tasks the caller could open, not the complete
        inventory.

    .EXAMPLE
        PS C:\> '.', 'localhost', $env:COMPUTERNAME | Get-ScheduledTaskInventory -OutputPath C:\TaskRuns |
            Format-Table -Property ComputerName, ComputerId, Status, Transport, TaskCount, XmlFailedCount, SddlFailedCount, BinaryCount, BinaryMissingCount, AccountCount, AccountUnresolvedCount, Error, ErrorCount

        ComputerName ComputerId                           Status  Transport TaskCount XmlFailedCount SddlFailedCount BinaryCount BinaryMissingCount AccountCount AccountUnresolvedCount Error                                                     ErrorCount
        ------------ ----------                           ------  --------- --------- -------------- --------------- ----------- ------------------ ------------ ---------------------- -----                                                     ----------
        .            11111111-2222-3333-4444-555555555501 Partial Local           203              0               0          53                  0            9                      0 not elevated: tasks the caller cannot open are not listed          1
        localhost    11111111-2222-3333-4444-555555555501 Partial Local           203              0               0          53                  0            9                      0 not elevated: tasks the caller cannot open are not listed          1
        WS01         11111111-2222-3333-4444-555555555501 Partial Local           203              0               0          53                  0            9                      0 not elevated: tasks the caller cannot open are not listed          1

        Three local aliases in the same call share one worker run and one OutputFolder, and each
        still gets its own row, Partial here because the run was not elevated. Every row carries
        the same ComputerId, since it is read once for the shared worker run and copied onto each
        alias row. A remote name would go through one
        Invoke-Command call instead, with a domain member's Group Policy created task whose
        access control list excludes the caller coming back as a Partial row rather than Failed.

    .EXAMPLE
        PS C:\TaskTest> '.', 'localhost', 'SRV020', 'DC01', 'dc01.contoso.com', 'DC02', 'SRV050', 'WS01', 'NOSUCHHOST01' | Get-ScheduledTaskInventory -OutputPath 'out[1]' | Format-Table ComputerName, ComputerId, Status, Transport, IsElevated, TaskCount, XmlFailedCount, SddlFailedCount, BinaryCount, BinaryMissingCount, AccountCount, AccountUnresolvedCount, ErrorCount, Error -AutoSize
        WARNING: NOSUCHHOST01: Connecting to remote server NOSUCHHOST01 failed with the following error message : WinRM cannot process the request. The following error occurred while using Kerberos authentication: Cannot find the computer NOSUCHHOST01. Verify that the computer exists on the network and that the name provided is spelled correctly. For more information, see the about_Remote_Troubleshooting Help topic.
        WARNING: DC01: binary C:\Windows\system32\failover.exe: not found (Windows ships no such file; not counted as an error)
        WARNING: dc01.contoso.com: binary C:\Windows\system32\failover.exe: not found (Windows ships no such file; not counted as an error)
        WARNING: DC02: binary C:\Windows\system32\MusNotification.exe: not found (Windows ships no such file; not counted as an error)
        WARNING: SRV050: binary C:\Windows\system32\MusNotification.exe: not found (Windows ships no such file; not counted as an error)
        WARNING: WS01: binary C:\WINDOWS\system32\MusNotification.exe: not found (Windows ships no such file; not counted as an error)

        ComputerName        ComputerId                           Status  Transport IsElevated TaskCount XmlFailedCount SddlFailedCount BinaryCount BinaryMissingCount AccountCount AccountUnresolvedCount ErrorCount Error
        ------------        ----------                           ------  --------- ---------- --------- -------------- --------------- ----------- ------------------ ------------ ---------------------- ---------- -----
        .                   11111111-2222-3333-4444-555555555503 Success Local           True       128              0               0          37                  0            9                      0          0
        localhost           11111111-2222-3333-4444-555555555503 Success Local           True       128              0               0          37                  0            9                      0          0
        SRV020              11111111-2222-3333-4444-555555555503 Success Local           True       128              0               0          37                  0            9                      0          0
        DC01                11111111-2222-3333-4444-555555555504 Success WinRM           True       157              0               0          41                  1            9                      0          0
        dc01.contoso.com    11111111-2222-3333-4444-555555555504 Success WinRM           True       157              0               0          41                  1            9                      0          0
        DC02                11111111-2222-3333-4444-555555555505 Success WinRM           True       202              0               0          45                  1            9                      0          0
        SRV050              11111111-2222-3333-4444-555555555506 Success WinRM           True       202              0               0          45                  1            9                      0          0
        WS01                11111111-2222-3333-4444-555555555507 Success WinRM           True       255              0               0          58                  1           10                      0          0
        NOSUCHHOST01                                             Failed  WinRM                                                                                                                                     1 Connecting to remote server NOSUCHHOST01 failed with the following error message : WinRM can...

        Nine names in one call on SRV020, a Windows Server 2016 domain member elevated as a domain
        administrator: DC01 and dc01.contoso.com are the same computer requested twice giving two
        folders, DC01, DC02, SRV050 and WS01 each hold one inbox task pointing at a binary Windows
        does not ship, so they report Success with BinaryMissingCount 1 and one warning per row,
        and NOSUCHHOST01 is unreachable and comes back Failed. The function writes the warning of
        a row that is not Success before that row, and every known-absent warning after the last
        row; Format-Table buffers the table, so the console prints all the warnings above it, in
        the order they were written.

    .EXAMPLE
        PS C:\UseSSLTest> Get-ScheduledTaskInventory -ComputerName 'SRV099.contoso.com' -UseSSL -OutputPath 'out' | Format-Table -Property ComputerName, ComputerId, Status, Transport, TaskCount, ErrorCount
        WARNING: SRV099.contoso.com: binary C:\Windows\system32\failover.exe: not found (Windows ships no such file; not counted as an error)

        ComputerName          ComputerId                           Status  Transport TaskCount ErrorCount
        ------------          ----------                           ------  --------- --------- ----------
        SRV099.contoso.com    11111111-2222-3333-4444-555555555502 Success WinRM           158          0

        Collects from one domain member over WinRM HTTPS (port 5986). The name is the FQDN, which
        matches the subject of the member's listener certificate. The short name SRV099 would fail the
        certificate name check with WinRM error 12175.

    .NOTES
        FUNCTION: Get-ScheduledTaskInventory
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        System.String[]. ComputerName is accepted from the pipeline, by value and by property
        name.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteScheduledTask.Result

    .LINK
        https://github.com/tomstryhn/RemoteScheduledTask
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [System.Management.Automation.PSCredential]
        $Credential,

        [switch]$UseSSL,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [ValidateRange(1, 256)]
        [int]$ThrottleLimit = 32,

        [switch]$SkipSidReference
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $collectedNames = @()
    }

    process {
        if ($ComputerName) { $collectedNames += @($ComputerName) }
    }

    end {
        # Resolved once here, against the caller's current location, not $PSScriptRoot or any other implicit base, and used everywhere after.
        $resolvedOutputPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)

        $resolvedNames = @(Resolve-ScheduledTaskInventoryComputerList -ComputerName $collectedNames)
        if ($resolvedNames.Count -eq 0) {
            throw 'ComputerName is empty after removing blanks and duplicates.'
        }

        $localNames = @()
        $remoteNames = @()
        foreach ($name in $resolvedNames) {
            if (Test-ScheduledTaskInventoryLocalName -Name $name) {
                $localNames += $name
            } else {
                $remoteNames += $name
            }
        }

        $runFolder = Initialize-ScheduledTaskInventoryRunFolder -OutputPath $resolvedOutputPath

        $startUtc = (Get-Date).ToUniversalTime()

        $rowMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $unattributedNames = [System.Collections.Generic.List[string]]::new()
        # Messages of remote errors that matched no requested computer and no unresolved name. Recorded here and warned about at the end of the function, for the same reason as the unattributed results: a warning is a terminating error under a caller's -WarningAction Stop, and it must not end the run before the files exist.
        $unattributedErrorMessages = [System.Collections.Generic.List[string]]::new()
        # Per requested name, the paths of the missing binaries the worker named as known-absent Windows binaries. They are kept here, not on the row: no file and no result column carries them. Warned about after the rows are returned, for the same reason as the messages above.
        $knownAbsentByName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

        if ($localNames.Count -gt 0) {
            # Local aliases share one worker run and one OutputFolder. The worker runs exactly once per call no matter how many aliases were requested, and each alias still gets its own row.
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
                $localWorkerObject = Invoke-ScheduledTaskInventoryLocal -SkipSidReference:$SkipSidReference
            } catch {
                $localExtraErrors += $_.Exception.Message
            }

            # The first alias completes the computer and writes the folder. Every later alias copies that row and changes only ComputerName, so no two rows for one folder can ever disagree on Status, a count or Errors.
            $firstLocalRow = $null
            $localKnownAbsentPaths = @(Get-ScheduledTaskInventorySafeProperty -InputObject $localWorkerObject -Name 'BinaryMissingExpectedPaths' -Default @() | Where-Object { -not [string]::IsNullOrEmpty($_) })
            foreach ($name in $localNames) {
                # Every alias has its own row, so every alias gets its own warning lines.
                $knownAbsentByName[$name] = $localKnownAbsentPaths
                if ($null -eq $firstLocalRow) {
                    $firstLocalRow = Complete-ScheduledTaskInventoryComputer -RequestedComputerName $name -Transport 'Local' -RunFolder $runFolder -WorkerObject $localWorkerObject -ExtraErrors $localExtraErrors
                    $rowMap[$name] = $firstLocalRow
                } else {
                    $aliasRow = $firstLocalRow.PSObject.Copy()
                    $aliasRow.ComputerName = $name
                    $rowMap[$name] = $aliasRow
                }
            }
        }

        if ($remoteNames.Count -gt 0) {
            Write-Verbose "Collecting remotely over WinRM: $($remoteNames -join ', ')"

            # Rows are built from the worker results as they stream in, then errors are mapped onto those rows afterward, never the reverse, so an error never overwrites a row a worker result already produced. Results are completed as they arrive rather than after every target has answered: each one is completed and released inside -OnResult, before the next one is read from the pipeline.
            $matchedResultNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

            $onRemoteResult = {
                param($res)

                # Both set before the try, so the catch below knows which requested computer a failure belongs to, if any.
                $pcName = $null
                $requested = $null
                try {
                    $pcName = Get-ScheduledTaskInventorySafeProperty -InputObject $res -Name 'PSComputerName' -Default $null
                    foreach ($rn in $remoteNames) {
                        if ($rn -ieq $pcName) { $requested = $rn; break }
                    }
                    if (-not $requested) {
                        # A result whose PSComputerName matches no requested name gets no folder and no row: it would never be emitted, because rows are built from the requested names only. The name is recorded here and warned about as the last step of the function, after run.json and results.csv are written, because a warning raised inside this callback under a caller's -WarningAction Stop would end the run while results are still streaming in, and one raised before the files are written would lose them.
                        [void]$unattributedNames.Add([string]$pcName)
                        return
                    }

                    $row = Complete-ScheduledTaskInventoryComputer -RequestedComputerName $requested -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $res -ExtraErrors @()
                    $rowMap[$requested] = $row
                    $knownAbsentByName[$requested] = @(Get-ScheduledTaskInventorySafeProperty -InputObject $res -Name 'BinaryMissingExpectedPaths' -Default @() | Where-Object { -not [string]::IsNullOrEmpty($_) })
                    [void]$matchedResultNames.Add($requested)
                } catch {
                    # A throw out of this callback would end the whole run. The computer whose result broke is reported Failed instead, and the run goes on with the others.
                    if ($requested) {
                        $rowMap[$requested] = ConvertTo-ScheduledTaskInventoryResultRow -ComputerName $requested -Status 'Failed' -Transport 'WinRM' -Errors @("host: $($_.Exception.Message)")
                        [void]$matchedResultNames.Add($requested)
                    } else {
                        [void]$unattributedNames.Add([string]$pcName)
                    }
                }
            }

            $remoteResult = $null
            $remoteCallError = $null
            try {
                $remoteResult = Invoke-ScheduledTaskInventoryRemote -ComputerName $remoteNames -Credential $Credential -ThrottleLimit $ThrottleLimit -OnResult $onRemoteResult -UseSSL:$UseSSL -SkipSidReference:$SkipSidReference
            } catch {
                $remoteCallError = $_.Exception.Message
            }

            $pendingErrors = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($rn in $remoteNames) { $pendingErrors[$rn] = New-Object 'System.Collections.Generic.List[string]' }

            if ($null -ne $remoteResult) {
                foreach ($err in @($remoteResult.Errors)) {
                    $message = Get-ScheduledTaskInventorySafeProperty -InputObject $err -Name 'Exception' -Default $null
                    $messageText = if ($message) { Get-ScheduledTaskInventorySafeProperty -InputObject $message -Name 'Message' -Default "$err" } else { "$err" }

                    $matchedName = Resolve-ScheduledTaskInventoryRemoteErrorName -ErrorRecord $err -RemoteNames $remoteNames

                    if ($matchedName) {
                        $pendingErrors[$matchedName].Add($messageText)
                    } else {
                        $unresolvedNames = @($remoteNames | Where-Object { -not $matchedResultNames.Contains($_) })
                        if ($unresolvedNames.Count -gt 0) {
                            foreach ($rn in $unresolvedNames) { $pendingErrors[$rn].Add($messageText) }
                        } else {
                            [void]$unattributedErrorMessages.Add($messageText)
                        }
                    }
                }
            }

            foreach ($rn in $remoteNames) {
                if ($matchedResultNames.Contains($rn)) {
                    $row = $rowMap[$rn]
                    foreach ($msg in $pendingErrors[$rn]) {
                        # Collapsed here as well: a late message is appended after ConvertTo-ScheduledTaskInventoryResultRow has already built the row, so that function's collapse never sees it, and a remote connection error is several lines.
                        $row.Errors += (([string]$msg).Trim() -replace '\s+', ' ')
                    }
                    # A late host-side error appended here after the row was already built from the worker object, so ErrorCount and Error are recomputed from Errors rather than left at the counts the worker object alone produced.
                    $row.ErrorCount = @($row.Errors).Count
                    if ([string]::IsNullOrEmpty($row.Error) -and $row.ErrorCount -gt 0) { $row.Error = $row.Errors[0] }
                } else {
                    $extraErrors = @($pendingErrors[$rn])
                    if ($extraErrors.Count -eq 0) {
                        $extraErrors = @( $(if ($remoteCallError) { $remoteCallError } else { 'no result and no error returned' }) )
                    }
                    $row = Complete-ScheduledTaskInventoryComputer -RequestedComputerName $rn -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $null -ExtraErrors $extraErrors
                    $rowMap[$rn] = $row
                }
            }
        }

        $rows = @()
        foreach ($name in $resolvedNames) {
            $rows += $rowMap[$name]
        }

        $endUtc = (Get-Date).ToUniversalTime()

        $runInfo = [pscustomobject]@{
            RunId              = Split-Path -Path $runFolder -Leaf
            Collector          = 'RemoteScheduledTask'
            CollectorVersion   = $MyInvocation.MyCommand.Module.Version.ToString()
            SchemaVersion      = '1.3'
            HostComputer       = $env:COMPUTERNAME
            HostComputerId     = Get-ScheduledTaskInventoryHostComputerId
            HostUser           = "$env:USERDOMAIN\$env:USERNAME"
            PSVersion          = $PSVersionTable.PSVersion.ToString()
            StartUtc           = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            EndUtc             = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            RequestedComputers = @($resolvedNames)
            ThrottleLimit      = $ThrottleLimit
            UseSSL             = [bool]$UseSSL
            SkipSidReference   = [bool]$SkipSidReference
            Results            = @($rows)
        }

        try {
            $runJson = $runInfo | ConvertTo-Json -Depth 8
            Write-ScheduledTaskInventoryTextFile -Path (Join-Path $runFolder 'run.json') -Content $runJson
        } catch {
            Write-Warning "Failed to write run.json: $($_.Exception.Message)"
        }

        try {
            $csvRows = @()
            foreach ($row in $rows) {
                $csvRows += $row | Select-Object -Property * -ExcludeProperty Errors
            }
            $csvPath = Join-Path $runFolder 'results.csv'
            Write-ScheduledTaskInventoryCsvFile -Row $csvRows -Path $csvPath
        } catch {
            Write-Warning "Failed to write results.csv: $($_.Exception.Message)"
        }

        foreach ($row in $rows) {
            if ($row.Status -ne 'Success') {
                Write-Warning "$($row.ComputerName): $($row.Error)"
            }
            $row
        }

        # One warning per known-absent path of every row, after the files are written and the rows are returned, so under a caller's -WarningAction Stop a caller that streams the output keeps the rows it has received, and the files are already written. A caller that assigns the result ($r = Get-ScheduledTaskInventory ... -WarningAction Stop) gets no rows when a warning stops the call.
        foreach ($row in $rows) {
            if (-not $knownAbsentByName.ContainsKey($row.ComputerName)) { continue }
            foreach ($knownAbsentPath in $knownAbsentByName[$row.ComputerName]) {
                Write-Warning "$($row.ComputerName): binary ${knownAbsentPath}: not found (Windows ships no such file; not counted as an error)"
            }
        }

        foreach ($unattributedName in $unattributedNames) {
            Write-Warning "Unattributed remote result, matched no requested computer name: $unattributedName"
        }
        foreach ($unattributedMessage in $unattributedErrorMessages) {
            Write-Warning "Unattributed remote error, matched no requested computer name: $unattributedMessage"
        }
    }
}
