<#PSScriptInfo

.DESCRIPTION Collects every Windows service, its account, its security descriptor and its binary identity from local or remote computers

.VERSION 1.7.0

.GUID ad4b067f-a48b-4edd-ae97-cc8e8f83c0e6

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Get-ServiceInventory
function Get-ServiceInventory {

    <#
    .SYNOPSIS
        Collects every Windows service, its account, its security descriptor and its binary
        identity from local or remote computers.

    .DESCRIPTION
        Collects every Windows service on the local computer in-process or on remote computers
        over WinRM (one Invoke-Command call for every remote target): the service configuration
        as the Service Control Manager reports it, the account each service runs as, the security
        descriptor of each service (sc sdshow), the services and groups it depends on and its
        ServiceDll, and the identity and signature of every distinct service binary and ServiceDll
        file. Nothing is interpreted. Each distinct account a service runs as is looked up once
        and resolved to its SID. The dependencies and the ServiceDll are read once per service
        from its registry key under HKLM\SYSTEM\CurrentControlSet\Services. Get-Service is not
        used. A per-user service instance (Name_<suffix>) that holds none of these values is read
        from the key Name. The raw files are written to a per-computer folder under
        -OutputPath together with the identity of the computer and every error seen on the way. A
        separate project analyses the files and decides which service accounts and which
        services need attention.

        Prerequisites, and nothing beyond them: sc.exe present on the target (it ships with
        Windows), Windows PowerShell 5.1 on the target. Run elevated for a complete collection.
        Without administrative rights the worker adds the error line 'not elevated: services and
        security descriptors the caller cannot open are not listed', so that computer's row
        comes back Partial with IsElevated False and holds the services and security
        descriptors the caller could open. Remote targets additionally need WinRM reachable
        from the caller. Local targets never use WinRM. Remote targets called without -Credential use
        the caller's own identity, exactly like any other Invoke-Command call. Nothing in this
        module is specific to any domain, server name, or account. It works unchanged on a
        domain-joined computer or on a workgroup computer.

        Each computer's system.json also carries a SID reference of four values: MachineSid, the
        SID of the computer's own account database (the local account with RID 500, read through
        CIM, without the RID), and DomainSid, ComputerAccountSid and DomainNetbiosName, read from
        the computer's own domain account through the same account lookup the module uses for
        service accounts, only on a domain-joined computer. No Active Directory module and no
        LDAP is used. A domain controller has no MachineSid, and a workgroup computer has no
        domain values. Those stay null. -SkipSidReference leaves all four null.

        Writes <OutputPath>\RemoteService-<yyyyMMdd-HHmmss>Z\ containing run.json and one folder
        per computer that was actually reached. Without -OutputPath the run folder is created in
        the current location. Each computer folder holds system.json, summary.json and, by
        default, services.json, accounts.json, appcontainers.json and binaries.json. services.json
        also holds DependOnService, DependOnGroup, DependentServices, ServiceDll and ServiceDllPath
        for each service, and services.csv the last two. An application package SID or a capability
        SID is not an account: it is written to appcontainers.json and kept out of accounts.json,
        and no account lookup is made for it. -OutputFormat Csv writes services.csv, accounts.csv,
        appcontainers.csv and binaries.csv instead, and Both writes all eight. The same
        choice decides whether results.csv is written to the run folder. run.json always holds the
        results, whatever the format. Every failure short of a bad -OutputPath or an empty
        -ComputerName list becomes a result row plus one Write-Warning. It is never a terminating
        error.

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
        services, accounts, appcontainers and binaries in every computer folder, and results.csv in the run
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
        PS C:\> Get-ServiceInventory -OutputPath C:\ServiceRuns | Format-List

        ComputerName           : WS01
        ComputerId             : 11111111-2222-3333-4444-555555555501
        Status                 : Success
        Transport              : Local
        OutputFolder           : C:\ServiceRuns\RemoteService-20260927-111811Z\WS01_26200_20260927-111824Z
        IsElevated             : True
        ServiceCount           : 308
        SddlFailedCount        : 0
        BinaryCount            : 71
        BinaryMissingCount     : 0
        AccountCount           : 4
        AccountUnresolvedCount : 0
        Error                  :
        ErrorCount             : 0
        Errors                 : {}

        Collects from the local computer only, run elevated on a workgroup Windows 11 laptop.

    .EXAMPLE
        PS C:\ServiceRuns> '.', 'localhost', 'SRV200', 'DC11', 'dc11.contoso.com', 'DC02', 'SRV050', 'WS01', 'NOSUCHHOST01' |
            Get-ServiceInventory -OutputPath 'out' |
            Format-Table -Property ComputerName, ComputerId, Status, Transport, ServiceCount, SddlFailedCount, BinaryCount, BinaryMissingCount, AccountCount, AccountUnresolvedCount, ErrorCount, Error

        ComputerName        ComputerId                           Status  Transport ServiceCount SddlFailedCount BinaryCount BinaryMissingCount AccountCount AccountUnresolvedCount ErrorCount Error
        ------------        ----------                           ------  --------- ------------ --------------- ----------- ------------------ ------------ ---------------------- ---------- -----
        .                   11111111-2222-3333-4444-555555555502 Success Local              208               0          46                  0           17                      0          0
        localhost           11111111-2222-3333-4444-555555555502 Success Local              208               0          46                  0           17                      0          0
        SRV200              11111111-2222-3333-4444-555555555502 Success Local              208               0          46                  0           17                      0          0
        DC11                11111111-2222-3333-4444-555555555503 Success WinRM              219               0          40                  0            3                      0          0
        dc11.contoso.com    11111111-2222-3333-4444-555555555503 Success WinRM              219               0          40                  0            3                      0          0
        DC02                11111111-2222-3333-4444-555555555504 Success WinRM              243               0          42                  0            3                      0          0
        SRV050              11111111-2222-3333-4444-555555555505 Success WinRM              255               0          55                  0           15                      0          0
        WS01                11111111-2222-3333-4444-555555555506 Success WinRM              271               0          38                  0            4                      0          0
        WARNING: NOSUCHHOST01: Connecting to remote server NOSUCHHOST01 failed with the following error message : WinRM cannot process the request. The following error occurred while using Kerberos authentication: Cannot find the computer NOSUCHHOST01. Verify that the computer exists on the network and that the name provided is spelled correctly. For more information, see the about_Remote_Troubleshooting Help topic.
        NOSUCHHOST01                                             Failed  WinRM                                                                                                              1 Connecting to remote server NOSUCHHOST01 failed with the following error me...

        Run from a Windows Server 2016 domain member against local aliases, a NetBIOS and FQDN
        pair, three more domain computers over WinRM, and one name that does not resolve. That
        row comes back as a Failed result row, not a terminating error.

    .EXAMPLE
        PS C:\ServiceRuns> Get-ServiceInventory -ComputerName 'SRV099.contoso.com' -UseSSL -OutputPath 'out' | Format-Table -Property ComputerName, ComputerId, Status, Transport, ServiceCount, ErrorCount

        ComputerName          ComputerId                           Status  Transport ServiceCount ErrorCount
        ------------          ----------                           ------  --------- ------------ ----------
        SRV099.contoso.com    11111111-2222-3333-4444-555555555507 Success WinRM              194          0

        Collects from one domain member over WinRM HTTPS (port 5986). The name is the FQDN, which
        matches the subject of the member's listener certificate. The short name SRV099 would fail the
        certificate name check with WinRM error 12175.

    .EXAMPLE
        PS C:\ServiceRuns> Get-ServiceInventory | Select-Object -Property ComputerName, Status, OutputFolder

        ComputerName Status  OutputFolder
        ------------ ------  ------------
        WS01         Success C:\ServiceRuns\RemoteService-20261116-091502Z\WS01_26200_20261116-091514Z

        Without -OutputPath the run folder is created in the current location. The default
        -OutputFormat Json writes services.json, accounts.json, appcontainers.json and
        binaries.json, and no csv file.

    .EXAMPLE
        PS C:\> Get-ServiceInventory -OutputPath C:\ServiceRuns -OutputFormat Both | Select-Object -Property ComputerName, Status, ServiceCount

        ComputerName Status  ServiceCount
        ------------ ------  ------------
        WS01         Success          308

        Writes the json and the csv file of every pair, so results.csv, services.csv,
        accounts.csv, appcontainers.csv and binaries.csv are written next to their json files.

    .NOTES
        FUNCTION: Get-ServiceInventory
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        System.String[]. ComputerName is accepted from the pipeline, by value and by property
        name.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteService.Result

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

        $resolvedNames = @(Resolve-ServiceInventoryComputerList -ComputerName $collectedNames)
        if ($resolvedNames.Count -eq 0) {
            throw 'ComputerName is empty after removing blanks and duplicates.'
        }

        $localNames = @()
        $remoteNames = @()
        foreach ($name in $resolvedNames) {
            if (Test-ServiceInventoryLocalName -Name $name) {
                $localNames += $name
            }
            else {
                $remoteNames += $name
            }
        }

        $runFolder = Initialize-ServiceInventoryRunFolder -OutputPath $resolvedOutputPath

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
                $localWorkerObject = Invoke-ServiceInventoryLocal -SkipSidReference:$SkipSidReference
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
                    $firstLocalRow = Complete-ServiceInventoryComputer -RequestedComputerName $name -Transport 'Local' -RunFolder $runFolder -WorkerObject $localWorkerObject -ExtraErrors $localExtraErrors -OutputFormat $OutputFormat
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
                    $pcName = Get-ServiceInventorySafeProperty -InputObject $Res -Name 'PSComputerName' -Default $null
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

                    $row = Complete-ServiceInventoryComputer -RequestedComputerName $requested -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $Res -ExtraErrors @() -OutputFormat $OutputFormat
                    $rowMap[$requested] = $row
                    [Void]$matchedResultNames.Add($requested)
                }
                catch {
                    $callbackMessage = $_.Exception.Message
                    if ($requested) {
                        $rowMap[$requested] = ConvertTo-ServiceInventoryResultRow -ComputerName $requested -Status 'Failed' -Transport 'WinRM' -Errors @("host: $callbackMessage")
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
                $remoteResult = Invoke-ServiceInventoryRemote -ComputerName $remoteNames -Credential $Credential -ThrottleLimit $ThrottleLimit -OnResult $onRemoteResult -UseSSL:$UseSSL -SkipSidReference:$SkipSidReference
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
                    $message = Get-ServiceInventorySafeProperty -InputObject $err -Name 'Exception' -Default $null
                    $messageText = if ($message) { Get-ServiceInventorySafeProperty -InputObject $message -Name 'Message' -Default "$err" } else { "$err" }

                    $matchedName = Resolve-ServiceInventoryRemoteErrorName -ErrorRecord $err -RemoteNames $remoteNames

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
                        # ConvertTo-ServiceInventoryResultRow has already built the row, so that function's
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
                    $row = Complete-ServiceInventoryComputer -RequestedComputerName $rn -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $null -ExtraErrors $extraErrors -OutputFormat $OutputFormat
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
            Collector          = 'RemoteService'
            CollectorVersion   = $MyInvocation.MyCommand.Module.Version.ToString()
            SchemaVersion      = '1.5'
            HostComputer       = $env:COMPUTERNAME
            HostComputerId     = Get-ServiceInventoryHostComputerId
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
            Write-ServiceInventoryTextFile -Path (Join-Path $runFolder 'run.json') -Content $runJson
        }
        catch {
            Write-Warning "Failed to write run.json: $($_.Exception.Message)"
        }

        # results.csv is the csv twin of the Results array in run.json, so it follows the format.
        if ($OutputFormat -ne 'Json') {
            try {
                $csvRows = @($rows | Select-Object -Property * -ExcludeProperty Errors)
                $csvPath = Join-Path $runFolder 'results.csv'
                Write-ServiceInventoryCsvFile -Row $csvRows -Path $csvPath
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
