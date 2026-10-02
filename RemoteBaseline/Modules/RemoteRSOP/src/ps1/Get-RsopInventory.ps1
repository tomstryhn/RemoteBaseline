<#PSScriptInfo

.DESCRIPTION Collects the Resultant Set of Policy data from local or remote computers

.VERSION 1.3.0

.GUID b98d75bd-6771-4cfd-91af-2dd1a6de3bd7

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function Get-RsopInventory {

    <#
    .SYNOPSIS
        Collects the Resultant Set of Policy data from local or remote computers.

    .DESCRIPTION
        Reads every populated class of root\RSOP\Computer and every root\RSOP\User\<SID>
        namespace, on the local computer in-process or on remote computers over WinRM (one
        Invoke-Command call for every remote target). The collector reads. It never runs
        gpupdate, never writes anything to the target, never changes a setting, and never starts
        or configures WinRM. Everything it writes lands in its own output folder on the caller.
        What it reads is what Group Policy delivered and logged on the computer, not the
        computer's effective configuration: a setting no GPO manages does not appear, and a
        computer with no user logon since boot has no user namespace.

        Every setting class is flattened into one settings table across the computer and every
        user namespace, alongside the applied GPOs, links, extension status and the accounts
        referenced by user rights and restricted groups. Every computer carries a ComputerId
        (Win32_ComputerSystemProduct.UUID, upper case, $null when the target was never reached)
        alongside its ComputerName, so a computer that was renamed or moved between domains still
        joins across runs. The output layout, key order and types are shared with RemoteSecEdit,
        RemoteService and RemoteScheduledTask.

        Every system.json also carries four SID reference values: MachineSid (the SID of the
        computer's own account database, without the RID), and on a domain-joined computer
        DomainSid, ComputerAccountSid and DomainNetbiosName. MachineSid is read from the local
        account with RID 500 through CIM (Win32_UserAccount, filtered on the computer name as the
        domain). The domain values come from the computer's own domain account, through the same
        account lookup the module uses for the accounts table, and only on a domain-joined
        computer. No Active Directory module and no LDAP is involved. A domain controller has no
        MachineSid, and a workgroup computer has null domain values.

        Prerequisites, and nothing beyond them: Windows PowerShell 5.1 or PowerShell 7 on the
        collecting computer; the targets run Windows PowerShell 5.1. The caller needs
        administrative rights on the target for the computer namespace. An unelevated
        caller gets an access denied error reading the computer namespace and the row for that
        computer comes back Failed, even though the same account can still read its own user
        namespace directly. Remote targets additionally need WinRM reachable from the caller.
        Local targets never use WinRM. Remote targets called without -Credential use the caller's
        own identity, exactly like any other Invoke-Command call. Nothing in this module is
        specific to any domain, server name, or account. It works unchanged on a domain-joined
        computer or on a workgroup computer.

        Writes <OutputPath>\RemoteRSOP-<yyyyMMdd-HHmmss>Z\ containing run.json, results.csv, and
        one folder per computer that was actually reached. Each result row carries ComputerId,
        AccountCount, AccountUnresolvedCount and ErrorCount alongside the RSOP counts, and each
        per-computer folder holds system.json, settings.json, settings.csv, gpos.json, gpos.csv,
        links.json, links.csv, extensions.json, extensions.csv, accounts.json, accounts.csv,
        raw.json and summary.json. On a Failed row where the target was never reached, every
        module column and IsElevated are $null. An account the target could not resolve is data
        for the analysis, not a reason to mark the row anything other than what its classes
        already earned. Every failure short of a bad -OutputPath or an empty -ComputerName list
        becomes a result row plus one Write-Warning. It is never a terminating error.

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
        PS C:\> $rows = Get-RsopInventory -ComputerName 'SRV050', 'WS01', 'DC02', 'NOSUCHHOST01' -Credential $cred -OutputPath C:\Spike\RemoteRSOP\runs
        PS C:\> $rows | Format-Table ComputerName, Status, Transport, ComputerClassCount, ComputerInstanceCount, UserNamespaceCount, SettingCount, GpoCount, ExtensionErrorCount, AccountCount, ErrorCount -AutoSize

        ComputerName Status  Transport ComputerClassCount ComputerInstanceCount UserNamespaceCount SettingCount GpoCount ExtensionErrorCount AccountCount ErrorCount
        ------------ ------  --------- ------------------ --------------------- ------------------ ------------ -------- ------------------- ------------ ----------
        SRV050       Success Local                     18                   843                  1          794       13                   0           14          0
        WS01         Success WinRM                     18                   961                  2          914       14                   0            8          0
        DC02         Success WinRM                     19                   220                  1          169        8                   0           15          0
        NOSUCHHOST01 Failed  WinRM                                                                                                                                 1

        PS C:\> $rows[0] | Format-List

        ComputerName           : SRV050
        ComputerId             : 11111111-2222-3333-4444-555555555503
        Status                 : Success
        Transport              : Local
        OutputFolder           : C:\Spike\RemoteRSOP\runs\RemoteRSOP-20260927-124125Z\SRV050_26100_20260927-124129Z
        IsElevated             : True
        ComputerClassCount     : 18
        ComputerInstanceCount  : 843
        UserNamespaceCount     : 1
        UserInstanceCount      : 37
        SettingCount           : 794
        GpoCount               : 13
        ExtensionErrorCount    : 0
        ClassErrorCount        : 0
        AccountCount           : 14
        AccountUnresolvedCount : 0
        Error                  :
        ErrorCount             : 0
        Errors                 : {}

        Run from SRV050, a Windows Server 2025 domain member, in an elevated session as
        CONTOSO\Administrator, against SRV050, WS01 and DC02 plus one name that does not resolve.
        SRV050 is Local because the command ran on SRV050 itself, WS01 and DC02 went over WinRM,
        and NOSUCHHOST01 still comes back as a Failed result row rather than a terminating error.

    .EXAMPLE
        PS C:\UseSSLTest> Get-RsopInventory -ComputerName 'SRV099.contoso.com' -UseSSL -OutputPath 'out' | Format-Table -Property ComputerName, ComputerId, Status, Transport, SettingCount, ErrorCount

        ComputerName       ComputerId                           Status  Transport SettingCount ErrorCount
        ------------       ----------                           ------  --------- ------------ ----------
        SRV099.contoso.com 11111111-2222-3333-4444-555555555502 Success WinRM              130          0

        Collects from one domain member over WinRM HTTPS (port 5986). The name is the FQDN, which
        matches the subject of the member's listener certificate. The short name SRV099 would fail the
        certificate name check with WinRM error 12175.

    .NOTES
        FUNCTION: Get-RsopInventory
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        System.String[]. ComputerName is accepted from the pipeline, by value and by property
        name.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteRSOP.Result

    .LINK
        https://github.com/tomstryhn/RemoteRSOP
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

        $resolvedNames = @(Resolve-RsopInventoryComputerList -ComputerName $collectedNames)
        if ($resolvedNames.Count -eq 0) {
            throw 'ComputerName is empty after removing blanks and duplicates.'
        }

        $localNames = @()
        $remoteNames = @()
        foreach ($name in $resolvedNames) {
            if (Test-RsopInventoryLocalName -Name $name) {
                $localNames += $name
            } else {
                $remoteNames += $name
            }
        }

        $runFolder = Initialize-RsopInventoryRunFolder -OutputPath $resolvedOutputPath

        $startUtc = (Get-Date).ToUniversalTime()

        $rowMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $unattributedNames = New-Object 'System.Collections.Generic.List[string]'
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
                $localWorkerObject = Invoke-RsopInventoryLocal -SkipSidReference:$SkipSidReference
            } catch {
                $localExtraErrors += $_.Exception.Message
            }

            # The first alias completes the computer and writes the folder. Every later alias copies that row and changes only ComputerName, so no two rows for one folder can ever disagree on Status, a count or Errors.
            $firstLocalRow = $null
            foreach ($name in $localNames) {
                if ($null -eq $firstLocalRow) {
                    $firstLocalRow = Complete-RsopInventoryComputer -RequestedComputerName $name -Transport 'Local' -RunFolder $runFolder -WorkerObject $localWorkerObject -ExtraErrors $localExtraErrors
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

            # The callback never throws: it runs inside the Invoke-Command pipeline, where an exception would end the whole run and lose every computer still to answer. A failure while completing one result becomes a Failed row for that computer, and the run goes on.
            $onRemoteResult = {
                param($res)

                $pcName = $null
                $requested = $null
                try {
                    $pcName = Get-RsopInventorySafeProperty -InputObject $res -Name 'PSComputerName' -Default $null
                    foreach ($rn in $remoteNames) {
                        if ($rn -ieq $pcName) { $requested = $rn; break }
                    }
                    if (-not $requested) {
                        # A result whose PSComputerName matches no requested name gets no folder and no row: it would never be emitted, because rows are built from the requested names only. Only the name is recorded here; the warning is written at the very end of the function, because under -WarningAction Stop a warning in this callback would end the pipeline with rows still unread.
                        [void]$unattributedNames.Add([string]$pcName)
                        return
                    }

                    $row = Complete-RsopInventoryComputer -RequestedComputerName $requested -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $res -ExtraErrors @()
                    $rowMap[$requested] = $row
                    [void]$matchedResultNames.Add($requested)
                } catch {
                    if ($requested) {
                        $rowMap[$requested] = ConvertTo-RsopInventoryResultRow -ComputerName $requested -Status 'Failed' -Transport 'WinRM' -Errors @("host: $($_.Exception.Message)")
                        [void]$matchedResultNames.Add($requested)
                    } else {
                        # The failure came before any requested name was matched, so the result cannot be attributed to a row.
                        [void]$unattributedNames.Add([string]$pcName)
                    }
                }
            }

            $remoteResult = $null
            $remoteCallError = $null
            try {
                $remoteResult = Invoke-RsopInventoryRemote -ComputerName $remoteNames -Credential $Credential -ThrottleLimit $ThrottleLimit -OnResult $onRemoteResult -UseSSL:$UseSSL -SkipSidReference:$SkipSidReference
            } catch {
                $remoteCallError = $_.Exception.Message
            }

            $pendingErrors = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($rn in $remoteNames) { $pendingErrors[$rn] = New-Object 'System.Collections.Generic.List[string]' }

            if ($null -ne $remoteResult) {
                foreach ($err in @($remoteResult.Errors)) {
                    $message = Get-RsopInventorySafeProperty -InputObject $err -Name 'Exception' -Default $null
                    $messageText = if ($message) { Get-RsopInventorySafeProperty -InputObject $message -Name 'Message' -Default "$err" } else { "$err" }

                    $matchedName = Resolve-RsopInventoryRemoteErrorName -ErrorRecord $err -RemoteNames $remoteNames

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
                        # Collapsed to one line here too, because this message reaches the row without passing through ConvertTo-RsopInventoryResultRow.
                        $row.Errors += ([string]$msg).Trim() -replace '\s+', ' '
                    }
                    # ErrorCount and Error are derived properties on the row: a late error appended here after ConvertTo-RsopInventoryResultRow built the row must recompute both, or ErrorCount drifts out of step with Errors.Count.
                    $row.ErrorCount = @($row.Errors).Count
                    if ([string]::IsNullOrEmpty($row.Error) -and $row.ErrorCount -gt 0) { $row.Error = $row.Errors[0] }
                } else {
                    $extraErrors = @($pendingErrors[$rn])
                    if ($extraErrors.Count -eq 0) {
                        $extraErrors = @( $(if ($remoteCallError) { $remoteCallError } else { 'no result and no error returned' }) )
                    }
                    $row = Complete-RsopInventoryComputer -RequestedComputerName $rn -Transport 'WinRM' -RunFolder $runFolder -WorkerObject $null -ExtraErrors $extraErrors
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
            Collector          = 'RemoteRSOP'
            CollectorVersion   = $MyInvocation.MyCommand.Module.Version.ToString()
            SchemaVersion      = '1.3'
            HostComputer       = $env:COMPUTERNAME
            HostComputerId     = Get-RsopInventoryHostComputerId
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
            Write-RsopInventoryTextFile -Path (Join-Path $runFolder 'run.json') -Content $runJson
        } catch {
            Write-Warning "Failed to write run.json: $($_.Exception.Message)"
        }

        try {
            $csvRows = @()
            foreach ($row in $rows) {
                $csvRows += $row | Select-Object -Property * -ExcludeProperty Errors
            }
            Write-RsopInventoryCsvFile -Row $csvRows -Path (Join-Path $runFolder 'results.csv')
        } catch {
            Write-Warning "Failed to write results.csv: $($_.Exception.Message)"
        }

        foreach ($row in $rows) {
            if ($row.Status -ne 'Success') {
                Write-Warning "$($row.ComputerName): $($row.Error)"
            }
            $row
        }

        # One warning per unattributed result, written as the very last step: the rows are in the map, run.json and results.csv are on disk and every row has been emitted, so a caller's -WarningAction Stop can no longer cost the run files. In the callback only the name is recorded.
        foreach ($unattributedName in $unattributedNames) {
            Write-Warning "Unattributed remote result, matched no requested computer name: $unattributedName"
        }
        foreach ($unattributedMessage in $unattributedErrorMessages) {
            Write-Warning "Unattributed remote error, matched no requested computer name: $unattributedMessage"
        }
    }
}
