<#PSScriptInfo

.DESCRIPTION Collects every Windows service, its account, its security descriptor and its binary identity from local or remote computers

.VERSION 1.3.0

.GUID ad4b067f-a48b-4edd-ae97-cc8e8f83c0e6

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function Get-ServiceInventory {

    <#
    .SYNOPSIS
        Collects every Windows service, its account, its security descriptor and its binary
        identity from local or remote computers.

    .DESCRIPTION
        Collects every Windows service on the local computer in-process or on remote computers
        over WinRM (one Invoke-Command call for every remote target): the service configuration
        as the Service Control Manager reports it, the account each service runs as, the security
        descriptor of each service (sc sdshow), and the identity and signature of every distinct
        service binary. Nothing is interpreted. Each distinct account a service runs as is looked
        up once and resolved to its SID. The raw files are written to a per-computer folder under
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

        Writes <OutputPath>\RemoteService-<yyyyMMdd-HHmmss>Z\ containing run.json, results.csv,
        and one folder per computer that was actually reached. Every failure short of a bad
        -OutputPath or an empty -ComputerName list becomes a result row plus one Write-Warning.
        It is never a terminating error.

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
        PS C:\ServicesTest> '.', 'localhost', 'SRV020', 'DC01', 'dc01.contoso.com', 'DC02', 'SRV050', 'WS01', 'NOSUCHHOST01' |
            Get-ServiceInventory -OutputPath 'out' |
            Format-Table -Property ComputerName, ComputerId, Status, Transport, ServiceCount, SddlFailedCount, BinaryCount, BinaryMissingCount, AccountCount, AccountUnresolvedCount, ErrorCount, Error

        ComputerName        ComputerId                           Status  Transport ServiceCount SddlFailedCount BinaryCount BinaryMissingCount AccountCount AccountUnresolvedCount ErrorCount Error
        ------------        ----------                           ------  --------- ------------ --------------- ----------- ------------------ ------------ ---------------------- ---------- -----
        .                   11111111-2222-3333-4444-555555555502 Success Local              208               0          46                  0           17                      0          0
        localhost           11111111-2222-3333-4444-555555555502 Success Local              208               0          46                  0           17                      0          0
        SRV020              11111111-2222-3333-4444-555555555502 Success Local              208               0          46                  0           17                      0          0
        DC01                11111111-2222-3333-4444-555555555503 Success WinRM              219               0          40                  0            3                      0          0
        dc01.contoso.com    11111111-2222-3333-4444-555555555503 Success WinRM              219               0          40                  0            3                      0          0
        DC02                11111111-2222-3333-4444-555555555504 Success WinRM              243               0          42                  0            3                      0          0
        SRV050              11111111-2222-3333-4444-555555555505 Success WinRM              255               0          55                  0           15                      0          0
        WS01                11111111-2222-3333-4444-555555555506 Success WinRM              271               0          38                  0            4                      0          0
        WARNING: NOSUCHHOST01: Connecting to remote server NOSUCHHOST01 failed with the following error message : WinRM cannot process the request. The following error occurred while using Kerberos authentication: Cannot find the computer NOSUCHHOST01. Verify that the computer exists on the network and that the name provided is spelled correctly. For more information, see the about_Remote_Troubleshooting Help topic.
        NOSUCHHOST01                                             Failed  WinRM                                                                                                              1 Connecting to remote server NOSUCHHOST01 failed with the following error me...

        Run from a Windows Server 2016 domain member against local aliases, a NetBIOS and FQDN
        pair, three more domain computers over WinRM, and one name that does not resolve. That
        row comes back as a Failed result row, not a terminating error.

    .EXAMPLE
        PS C:\UseSSLTest> Get-ServiceInventory -ComputerName 'SRV099.contoso.com' -UseSSL -OutputPath 'out' | Format-Table -Property ComputerName, ComputerId, Status, Transport, ServiceCount, ErrorCount

        ComputerName          ComputerId                           Status  Transport ServiceCount ErrorCount
        ------------          ----------                           ------  --------- ------------ ----------
        SRV099.contoso.com    11111111-2222-3333-4444-555555555507 Success WinRM              194          0

        Collects from one domain member over WinRM HTTPS (port 5986). The name is the FQDN, which
        matches the subject of the member's listener certificate. The short name SRV099 would fail the
        certificate name check with WinRM error 12175.

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
        https://github.com/tomstryhn/RemoteService
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
        [int]$ThrottleLimit = 32
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

        $resolvedNames = @(Resolve-ServiceInventoryComputerList -ComputerName $collectedNames)
        if ($resolvedNames.Count -eq 0) {
            throw 'ComputerName is empty after removing blanks and duplicates.'
        }

        $localNames = @()
        $remoteNames = @()
        foreach ($name in $resolvedNames) {
            if (Test-ServiceInventoryLocalName -Name $name) {
                $localNames += $name
            } else {
                $remoteNames += $name
            }
        }

        $runFolder = Initialize-ServiceInventoryRunFolder -OutputPath $resolvedOutputPath

        $startUtc = (Get-Date).ToUniversalTime()

        $rowMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $unattributedNames = [System.Collections.Generic.List[string]]::new()
        # Messages of remote errors that matched no requested computer and no unresolved name. Recorded here and warned about at the end of the function, for the same reason as the unattributed results: a warning is a terminating error under a caller's -WarningAction Stop, and it must not end the run before the files exist.
        $unattributedErrorMessages = [System.Collections.Generic.List[string]]::new()

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
                $localWorkerObject = Invoke-ServiceInventoryLocal
            } catch {
                $localExtraErrors += $_.Exception.Message
            }

            # The first alias completes the computer and writes the folder. Every later alias copies that row and changes only ComputerName, so no two rows for one folder can ever disagree on Status, a count or Errors.
            $firstLocalRow = $null
            foreach ($name in $localNames) {
                if ($null -eq $firstLocalRow) {
                    $firstLocalRow = Complete-ServiceInventoryComputer -RequestedComputerName $name -Transport 'Local' -RunFolder $runFolder -WorkerObject $localWorkerObject -ExtraErrors $localExtraErrors
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

            # The callback never throws. It runs inside the Invoke-Command pipeline, so an exception here would end the whole run and discard every other computer's result. A failure while one result is completed becomes a Failed row for that computer instead, and the run goes on.
            $onRemoteResult = {
                param($res)

                $pcName = $null
                $requested = $null
                try {
                    $pcName = Get-ServiceInventorySafeProperty -InputObject $res -Name 'PSComputerName' -Default $null
                    foreach ($rn in $remoteNames) {
                        if ($rn -ieq $pcName) { $requested = $rn; break }
                    }
                    if (-not $requested) {
                        # A result whose PSComputerName matches no requested name gets no folder and no row: it would never be emitted, because rows are built from the requested names only. The warning is written as the last statement of the function (see the end), not here, so a caller's -WarningAction Stop cannot end the pipeline halfway through.
                        [void]$unattributedNames.Add([string]$pcName)
                        return
                    }

                    $row = Complete-ServiceInventoryComputer -RequestedComputerName $requested -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $res -ExtraErrors @()
                    $rowMap[$requested] = $row
                    [void]$matchedResultNames.Add($requested)
                } catch {
                    $callbackMessage = $_.Exception.Message
                    if ($requested) {
                        $rowMap[$requested] = ConvertTo-ServiceInventoryResultRow -ComputerName $requested -Status 'Failed' -Transport 'WinRM' -Errors @("host: $callbackMessage")
                        [void]$matchedResultNames.Add($requested)
                    } else {
                        # No requested name could be found for this result, so no row can carry the error; it is recorded as unattributed, which is reported at the end of the function.
                        [void]$unattributedNames.Add([string]$pcName)
                    }
                }
            }

            $remoteResult = $null
            $remoteCallError = $null
            try {
                $remoteResult = Invoke-ServiceInventoryRemote -ComputerName $remoteNames -Credential $Credential -ThrottleLimit $ThrottleLimit -OnResult $onRemoteResult -UseSSL:$UseSSL
            } catch {
                $remoteCallError = $_.Exception.Message
            }

            $pendingErrors = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($rn in $remoteNames) { $pendingErrors[$rn] = New-Object 'System.Collections.Generic.List[string]' }

            if ($null -ne $remoteResult) {
                foreach ($err in @($remoteResult.Errors)) {
                    $message = Get-ServiceInventorySafeProperty -InputObject $err -Name 'Exception' -Default $null
                    $messageText = if ($message) { Get-ServiceInventorySafeProperty -InputObject $message -Name 'Message' -Default "$err" } else { "$err" }

                    $matchedName = Resolve-ServiceInventoryRemoteErrorName -ErrorRecord $err -RemoteNames $remoteNames

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
                        # Collapsed here as well: a late message is appended after ConvertTo-ServiceInventoryResultRow has already built the row, so that function's collapse never sees it, and a remote connection error is several lines.
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
                    $row = Complete-ServiceInventoryComputer -RequestedComputerName $rn -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $null -ExtraErrors $extraErrors
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
            Collector          = 'RemoteService'
            CollectorVersion   = $MyInvocation.MyCommand.Module.Version.ToString()
            SchemaVersion      = '1.2'
            HostComputer       = $env:COMPUTERNAME
            HostComputerId     = Get-ServiceInventoryHostComputerId
            HostUser           = "$env:USERDOMAIN\$env:USERNAME"
            PSVersion          = $PSVersionTable.PSVersion.ToString()
            StartUtc           = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            EndUtc             = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
            RequestedComputers = @($resolvedNames)
            ThrottleLimit      = $ThrottleLimit
            UseSSL             = [bool]$UseSSL
            Results            = @($rows)
        }

        try {
            $runJson = $runInfo | ConvertTo-Json -Depth 8
            Write-ServiceInventoryTextFile -Path (Join-Path $runFolder 'run.json') -Content $runJson
        } catch {
            Write-Warning "Failed to write run.json: $($_.Exception.Message)"
        }

        try {
            $csvRows = @()
            foreach ($row in $rows) {
                $csvRows += $row | Select-Object -Property * -ExcludeProperty Errors
            }
            $csvPath = Join-Path $runFolder 'results.csv'
            Write-ServiceInventoryCsvFile -Row $csvRows -Path $csvPath
        } catch {
            Write-Warning "Failed to write results.csv: $($_.Exception.Message)"
        }

        foreach ($row in $rows) {
            if ($row.Status -ne 'Success') {
                Write-Warning "$($row.ComputerName): $($row.Error)"
            }
            $row
        }

        # The last statements of the function, after run.json and results.csv are written and every row is emitted: a caller's -WarningAction Stop then ends a finished run and can no longer lose the run files.
        foreach ($unattributedName in $unattributedNames) {
            Write-Warning "Unattributed remote result, matched no requested computer name: $unattributedName"
        }
        foreach ($unattributedMessage in $unattributedErrorMessages) {
            Write-Warning "Unattributed remote error, matched no requested computer name: $unattributedMessage"
        }
    }
}
