<#PSScriptInfo

.DESCRIPTION Runs the bundled Remote collectors against local or remote computers and arranges the output per host

.VERSION 1.0.0

.GUID 328237d5-01c6-4bcd-aa0b-731e41f30259

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Get-RemoteBaseline {

    <#
    .SYNOPSIS
        Runs the bundled Remote collectors against local or remote computers and arranges the
        output per host.

    .DESCRIPTION
        Collects with any combination of five collectors that ship inside this module as unchanged
        copies, so nothing else needs to be installed on the collecting computer or on the
        targets: Firewall (RemoteFirewall), RSOP (RemoteRSOP), ScheduledTask (RemoteScheduledTask),
        SecEdit (RemoteSecEdit) and Service (RemoteService). Each collector runs once for the
        whole list of computers, in the fixed order Firewall, RSOP, ScheduledTask, SecEdit,
        Service, with the parameters of this call, and keeps its own WinRM fan-out. Targets are
        only read, never changed; this module adds no action on a target.

        Writes <OutputPath>\RemoteBaseline-<yyyyMMdd-HHmmss>Z\ (a _2, _3 suffix on collision)
        containing run.json, results.csv, manifest.sha256, a collectors folder with the run.json
        and results.csv of each collector run, and one host folder per reached computer
        (<REPORTED>_<CurrentBuild>_<stamp>Z) with host.json and one subfolder per collector, named
        after the module, holding that collector's computer folder with its files intact. Names of
        one local computer share one host folder. A computer that no selected collector reached
        has no host folder and a Failed row; one that only some reached has the subfolders of
        those collectors. host.json is deliberately not named system.json, so a reader looking for
        computer folders never mistakes a host folder for one.

        manifest.sha256 holds the SHA-256 of every other file in the run folder, one line each, so
        the run can be checked after it has been copied or sent. With -Compress the run folder is
        also written as <run folder>.zip beside it.

        Returns one result row per requested name after the last collector has returned and the
        arrangement is done. Status is Success when every selected collector's row is Success and
        the arrangement added nothing, Failed when every collector's row is Failed (or the name
        has none), and Partial otherwise. The per-type status and error count columns say which
        collector was not clean. The function never throws: every failure is a row value, an
        Errors line or a warning, one warning per row that is not Success, written after the files
        are and after the rows have been returned. A failure to write run.json or results.csv, or
        to write the manifest or the zip, cannot be recorded in the files it concerns, so the lines
        run.json:, results.csv:, manifest: and zip: appear in the returned rows only and make
        every Success row Partial; the manifest and the zip are still written over what exists.
        A rename or move of a collector's folder that NTFS refuses is tried three times, 500 ms
        apart, before an arrange: line is written.

    .PARAMETER ComputerName
        Targets, as in the collectors: '.', 'localhost', '127.0.0.1', '::1', the local NetBIOS name
        and the local FQDN run in-process without WinRM, everything else goes through WinRM.
        Accepts pipeline input by value and by property name. Duplicates are removed
        case-insensitively and the first-seen order is kept. Defaults to the local computer name.

    .PARAMETER Type
        The collectors to run: Firewall, RSOP, ScheduledTask, SecEdit, Service. Defaults to all
        five. Duplicates and case differences collapse, and the run order is fixed whatever the
        order given.

    .PARAMETER Credential
        Passed to every collector, only when given. The collectors use it for remote targets only.

    .PARAMETER UseSSL
        Passed to every collector, only when set: remote targets are contacted over WinRM HTTPS
        (port 5986). Certificate checks are never skipped.

    .PARAMETER OutputPath
        Root folder for the run. May be relative. Resolved once against the current location,
        created if missing, and tested for writing before any target is contacted. In Windows
        PowerShell 5.1 the resolved path may be at most 105 characters, because a collection writes
        about 150 characters below it and 5.1 limits a path to 260; a longer path gives a Failed
        row per computer and writes nothing. PowerShell 7 has no such check.

    .PARAMETER ThrottleLimit
        Passed to every collector. From 1 to 256. Defaults to 32.

    .PARAMETER Compress
        Writes <run folder>.zip beside the run folder after the manifest, one entry per file with
        forward-slash entry names that every unzip tool reads as folders (Compress-Archive in
        Windows PowerShell 5.1 writes backslashes, so it is not used). Optional because the raw
        dumps of many hosts make the zip large and slow to write. An existing zip of the same name
        is never replaced: the row gets a zip: line instead.

    .EXAMPLE
        PS C:\> Get-RemoteBaseline -OutputPath C:\BaselineRuns -Type Firewall, Service | Format-Table -Property ComputerName, Status, FirewallStatus, ServiceStatus, ErrorCount

        ComputerName Status  FirewallStatus ServiceStatus ErrorCount
        ------------ ------  -------------- ------------- ----------
        WS01         Partial Partial        Partial               10

        Collects the firewall and the services of the local computer from a session that is not
        elevated. Two collectors run, in the order Firewall then Service, and the row carries a
        status for each of them. Both came back Partial because they could not open every item
        without administrative rights, so the umbrella row is Partial too, with the ten error
        lines of the two collectors prefixed Firewall: and Service:.

    .EXAMPLE
        PS C:\> 'WS01', 'SRV01.contoso.com' | Get-RemoteBaseline -OutputPath C:\BaselineRuns -UseSSL -Compress

        Runs all five collectors against two computers over WinRM HTTPS and writes the run folder
        and a zip of it. The names must match the listener certificates, as for any collector.

    .NOTES
        FUNCTION: Get-RemoteBaseline
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        System.String[]. ComputerName is accepted from the pipeline, by value and by property
        name.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteBaseline.Result

    .LINK
        https://github.com/tomstryhn/RemoteBaseline
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [ValidateSet('Firewall', 'RSOP', 'ScheduledTask', 'SecEdit', 'Service')]
        [string[]]$Type = @('Firewall', 'RSOP', 'ScheduledTask', 'SecEdit', 'Service'),

        [System.Management.Automation.PSCredential]
        $Credential,

        [switch]$UseSSL,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [ValidateRange(1, 256)]
        [int]$ThrottleLimit = 32,

        [switch]$Compress
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
        $resolvedNames = @(Resolve-RemoteBaselineComputerList -ComputerName $collectedNames)
        if ($resolvedNames.Count -eq 0) {
            # The function never throws, and with no name there is no row to carry the problem, so it is a warning.
            Write-Warning 'ComputerName is empty after removing blanks and duplicates.'
            return
        }

        $selectedCollectors = @(Get-RemoteBaselineCollectorInfo -Type $Type)
        $typeNames = @($selectedCollectors | ForEach-Object { $_.Type })
        $moduleNames = @($selectedCollectors | ForEach-Object { $_.Module })

        # Every column of a result row except Errors, in order: the header of results.csv, also used when there are no rows.
        $csvColumns = @('ComputerName', 'ComputerId', 'Status', 'Transport', 'OutputFolder', 'IsElevated', 'Types',
            'FirewallStatus', 'RSOPStatus', 'ScheduledTaskStatus', 'SecEditStatus', 'ServiceStatus',
            'FirewallErrorCount', 'RSOPErrorCount', 'ScheduledTaskErrorCount', 'SecEditErrorCount', 'ServiceErrorCount',
            'Error', 'ErrorCount')

        # The rows of the two fatal paths (output path, last-resort catch). No collector reported, so every selected type is Failed with 0 errors of its own; null stays reserved for a type that was not selected. The one line is the whole of the row's Errors.
        $buildFatalRows = {
            param([string]$Line)
            $failedByType = @{}
            foreach ($typeName in $typeNames) { $failedByType[$typeName] = [pscustomobject]@{ Status = 'Failed'; ErrorCount = 0 } }
            $fatalRows = [System.Collections.Generic.List[object]]::new()
            foreach ($name in $resolvedNames) {
                [void]$fatalRows.Add((ConvertTo-RemoteBaselineResultRow -ComputerName $name -Type $typeNames -CollectorRow $failedByType -OutputFolder '' -ExtraError @($Line)))
            }
            return $fatalRows.ToArray()
        }

        $rows = @()
        $runFolder = $null
        $outputPathError = $null
        try {
            # Resolved once here, against the caller's current location, and used everywhere after.
            $resolvedOutputPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
            $runFolder = Initialize-RemoteBaselineRunFolder -OutputPath $resolvedOutputPath
        } catch {
            # The innermost message: a .NET call through PowerShell wraps the real reason ('Cannot find drive...') in 'Exception calling ... with ... argument(s)'.
            $outputPathError = ConvertTo-RemoteBaselineOneLine -Text $_.Exception.GetBaseException().Message
        }

        if ($null -ne $outputPathError) {
            # No folder, no files, no collector was called: one Failed row per requested name.
            $rows = @(& $buildFatalRows -Line ('output path: ' + $outputPathError))
        } else {
            try {
                $runId = Split-Path -Path $runFolder -Leaf
                $collectorVersion = $MyInvocation.MyCommand.Module.Version.ToString()
                $hostIdentity = Get-RemoteBaselineHostIdentity
                $stagingPath = Join-Path -Path $runFolder -ChildPath 'collectors'

                # The umbrella's own lines per requested name (arrange, host.json). Run-level lines (manifest, zip) are added at the end.
                $extraByName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($name in $resolvedNames) { $extraByName[$name] = [System.Collections.Generic.List[string]]::new() }

                # Step 3: every selected collector, in run order, one call each for the whole list.
                $collectorResults = [System.Collections.Generic.List[object]]::new()
                foreach ($collector in $selectedCollectors) {
                    $callParams = @{
                        Type          = $collector.Type
                        ComputerName  = $resolvedNames
                        StagingPath   = $stagingPath
                        ThrottleLimit = $ThrottleLimit
                    }
                    if ($null -ne $Credential) { $callParams['Credential'] = $Credential }
                    if ($UseSSL) { $callParams['UseSSL'] = $true }
                    Write-Verbose "Collecting $($collector.Type) with $($collector.Module)."
                    [void]$collectorResults.Add((Invoke-RemoteBaselineCollector @callParams))
                }

                # Step 4: per collector in run order, the computer folders move under the host folders.
                $hostMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($result in $collectorResults) {
                    if ($null -ne $result['ArrangeError']) {
                        foreach ($collectorRow in @($result['Rows'])) {
                            $rowName = [string](Get-RemoteBaselineSafeProperty -InputObject $collectorRow -Name 'ComputerName' -Default '')
                            if ($extraByName.ContainsKey($rowName)) { [void]$extraByName[$rowName].Add([string]$result['ArrangeError']) }
                        }
                    }
                    # Where the collector's run folder is now: renamed to the module name, or still under its own name when the rename was refused or failed. The move accepts only computer folders directly inside it.
                    $collectorFolder = Join-Path -Path $stagingPath -ChildPath $result['Module']
                    if ($null -ne $result['ArrangeError'] -and $null -ne $result['RunId']) {
                        $collectorFolder = Join-Path -Path $stagingPath -ChildPath $result['RunId']
                    }
                    $outcomes = @(Move-RemoteBaselineComputerFolder -Module $result['Module'] -Row @($result['Rows']) -RunFolder $runFolder -CollectorFolder $collectorFolder -HostMap $hostMap)
                    foreach ($outcome in $outcomes) {
                        if ($null -ne $outcome.Error -and $extraByName.ContainsKey($outcome.ComputerName)) {
                            [void]$extraByName[$outcome.ComputerName].Add([string]$outcome.Error)
                        }
                    }
                }

                # Each collector's rows by requested name, once, so building a result row is a lookup and not a scan.
                $rowIndex = @{}
                foreach ($result in $collectorResults) {
                    $byName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($collectorRow in @($result['Rows'])) {
                        $rowName = [string](Get-RemoteBaselineSafeProperty -InputObject $collectorRow -Name 'ComputerName' -Default '')
                        if (-not $byName.ContainsKey($rowName)) { $byName[$rowName] = $collectorRow }
                    }
                    $rowIndex[[string]$result['Type']] = $byName
                }

                # The result rows for every requested name from what is known now. Built again after each step that adds a line, because the row is a pure function of its inputs and a Success row turns Partial when a line is added.
                $buildRows = {
                    param([string[]]$RunLines)
                    $built = [System.Collections.Generic.List[object]]::new()
                    foreach ($name in $resolvedNames) {
                        $perType = @{}
                        foreach ($typeName in $typeNames) {
                            if ($rowIndex[$typeName].ContainsKey($name)) { $perType[$typeName] = $rowIndex[$typeName][$name] }
                        }
                        $folder = ''
                        if ($hostMap.ContainsKey($name)) { $folder = $hostMap[$name] }
                        $extra = @($extraByName[$name]) + @($RunLines)
                        [void]$built.Add((ConvertTo-RemoteBaselineResultRow -ComputerName $name -Type $typeNames -CollectorRow $perType -OutputFolder $folder -ExtraError $extra))
                    }
                    return $built.ToArray()
                }

                # The requested names per host folder, in requested order.
                $namesByHost = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($name in $resolvedNames) {
                    if ($hostMap.ContainsKey($name)) {
                        if (-not $namesByHost.ContainsKey($hostMap[$name])) { $namesByHost[$hostMap[$name]] = [System.Collections.Generic.List[string]]::new() }
                        [void]$namesByHost[$hostMap[$name]].Add($name)
                    }
                }

                # Step 5: host.json in every host folder. system.json is read first because a read problem is a line on every name of the host, and the Status in host.json must already include it.
                $systemByHost = @{}
                foreach ($hostFolder in $namesByHost.Keys) {
                    $systemRead = Read-RemoteBaselineHostSystem -HostFolder $hostFolder -Module $moduleNames
                    $systemByHost[$hostFolder] = $systemRead.System
                    foreach ($problem in $systemRead.Problems) {
                        foreach ($name in $namesByHost[$hostFolder]) { [void]$extraByName[$name].Add($problem) }
                    }
                }
                $preRows = @(& $buildRows -RunLines @())
                $preRowByName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($preRow in $preRows) { $preRowByName[$preRow.ComputerName] = $preRow }
                foreach ($hostFolder in $namesByHost.Keys) {
                    $hostNames = @($namesByHost[$hostFolder])
                    try {
                        Write-RemoteBaselineHostFile -HostFolder $hostFolder -RequestedName $hostNames -Type $typeNames -CollectorResult @($collectorResults) -Row $preRowByName[$hostNames[0]] -SystemInfo $systemByHost[$hostFolder] -CollectorVersion $collectorVersion -RunId $runId
                    } catch {
                        $hostFileLine = 'host.json: ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message)
                        foreach ($name in $hostNames) { [void]$extraByName[$name].Add($hostFileLine) }
                    }
                }

                # Run-level lines: a failure to write run.json, results.csv, the manifest or the zip cannot be recorded in the files it concerns (the first two are inside the manifest and the zip), and a warning in the middle of the run would let a caller's -WarningAction Stop turn every row into a host: failure. They are lines on the returned rows only.
                $runLines = [System.Collections.Generic.List[string]]::new()

                # Step 6: run.json and results.csv from the rows as they stand.
                $rows = @(& $buildRows -RunLines @())
                $endUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

                $collectorSummaries = [System.Collections.Generic.List[object]]::new()
                foreach ($result in $collectorResults) {
                    $resultRows = @($result['Rows'])
                    $successCount = @($resultRows | Where-Object { (Get-RemoteBaselineSafeProperty -InputObject $_ -Name 'Status' -Default '') -eq 'Success' }).Count
                    $partialCount = @($resultRows | Where-Object { (Get-RemoteBaselineSafeProperty -InputObject $_ -Name 'Status' -Default '') -eq 'Partial' }).Count
                    $failedCount = @($resultRows | Where-Object { (Get-RemoteBaselineSafeProperty -InputObject $_ -Name 'Status' -Default '') -eq 'Failed' }).Count
                    [void]$collectorSummaries.Add([pscustomobject]([ordered]@{
                                Type         = $result['Type']
                                Module       = $result['Module']
                                Version      = $result['Version']
                                RunId        = $result['RunId']
                                DurationMs   = [int]$result['DurationMs']
                                RowCount     = $resultRows.Count
                                SuccessCount = $successCount
                                PartialCount = $partialCount
                                FailedCount  = $failedCount
                                Error        = $result['Error']
                            }))
                }

                $archiveName = $null
                if ($Compress) { $archiveName = $runId + '.zip' }

                $runInfo = [pscustomobject]([ordered]@{
                        RunId              = $runId
                        Collector          = 'RemoteBaseline'
                        CollectorVersion   = $collectorVersion
                        SchemaVersion      = '1.2'
                        HostComputer       = $hostIdentity.HostComputer
                        HostComputerId     = $hostIdentity.HostComputerId
                        HostUser           = $hostIdentity.HostUser
                        PSVersion          = $hostIdentity.PSVersion
                        StartUtc           = $hostIdentity.StartUtc
                        EndUtc             = $endUtc
                        RequestedComputers = [string[]]@($resolvedNames)
                        Types              = [string[]]@($typeNames)
                        ThrottleLimit      = $ThrottleLimit
                        UseSSL             = [bool]$UseSSL
                        Compress           = [bool]$Compress
                        Archive            = $archiveName
                        Collectors         = $collectorSummaries.ToArray()
                        Results            = @($rows)
                    })

                try {
                    $runJson = $runInfo | ConvertTo-Json -Depth 8
                    Write-RemoteBaselineTextFile -Path (Join-Path -Path $runFolder -ChildPath 'run.json') -Content $runJson
                } catch {
                    [void]$runLines.Add('run.json: ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message))
                }

                try {
                    # Types is a string[] in the row and in run.json, and one text cell in the csv.
                    $csvRowList = [System.Collections.Generic.List[object]]::new()
                    foreach ($row in $rows) {
                        $csvRow = [ordered]@{}
                        foreach ($column in $csvColumns) {
                            $cell = $row.$column
                            if ($column -eq 'Types') { $cell = (@($cell) -join ', ') }
                            $csvRow[$column] = $cell
                        }
                        [void]$csvRowList.Add([pscustomobject]$csvRow)
                    }
                    Write-RemoteBaselineCsvFile -Row $csvRowList.ToArray() -Path (Join-Path -Path $runFolder -ChildPath 'results.csv') -Column $csvColumns
                } catch {
                    [void]$runLines.Add('results.csv: ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message))
                }

                # Step 7: the manifest, then the archive, over whatever exists on disk.
                try {
                    Write-RemoteBaselineManifest -RunFolder $runFolder
                } catch {
                    [void]$runLines.Add('manifest: ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message))
                }

                if ($Compress) {
                    # Not Compress-Archive: Windows PowerShell 5.1 writes backslashes in its entry names. The helper refuses an existing zip and removes a partial one itself, so a throw here is only turned into the line.
                    try {
                        Compress-RemoteBaselineRunFolder -RunFolder $runFolder
                    } catch {
                        [void]$runLines.Add('zip: ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message))
                    }
                }

                if ($runLines.Count -gt 0) {
                    $rows = @(& $buildRows -RunLines $runLines.ToArray())
                }
            } catch {
                # Nothing above is expected to throw; if it does, the run does not stop the caller. Every name gets a Failed row that carries the message.
                $fatalLine = 'host: ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message)
                $rows = @(& $buildFatalRows -Line $fatalLine)
            }
        }

        # Step 8: the rows first, then the warnings. A caller's -WarningAction Stop turns a warning into a terminating error, so the rows are already with the caller and run.json, results.csv, the manifest and the zip already exist when the first warning can stop the call.
        $rows
        foreach ($row in $rows) {
            if ($row.Status -ne 'Success') {
                Write-Warning "$($row.ComputerName): $($row.Status), $($row.ErrorCount) error(s): $($row.Error)"
            }
        }
    }
}
