<#PSScriptInfo

.DESCRIPTION Runs one bundled collector into the staging folder and renames its run folder to the module name

.VERSION 1.0.0

.GUID 098345b5-b4b3-425b-9423-f690d25bef09

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Invoke-RemoteBaselineCollector {

    <#
    .SYNOPSIS
        Runs one bundled collector into the staging folder and renames its run folder to the module name.

    .DESCRIPTION
        Calls the collector's public function, resolved by Get-RemoteBaselineCollectorCommand from
        this module's nested modules (never by name through the caller's session, where an alias
        or function of the same name would win), with -OutputPath set to the staging folder (the
        collectors folder of the run), the de-duplicated names, -ThrottleLimit, and
        -WarningAction SilentlyContinue (the collector's own warnings reach the caller through the
        rows). -Credential and -UseSSL are passed only when given. The rows are captured and the
        call is timed. Version comes from the same resolution, so it is the version that ran.

        A throw from the collector, or from the resolver ("collector <Module> not bundled"), which
        is not expected, is caught: every requested name gets a synthetic Failed row with the error
        line "host: <message>" and an empty OutputFolder. A requested name the collector returned
        no row for gets the same kind of row ("host: no result row returned"), so Rows always
        holds exactly one row per requested name.

        The collector's run folder is the parent of the first non-empty OutputFolder. When no row
        has one (every row Failed), it is the newest folder named <Module>-*Z* under the staging
        folder that was created when this call started or later (two seconds of tolerance for
        file system clock granularity). Before the rename that folder's parent must be the staging
        folder (full resolved paths, ordinal, ignoring case): a row can name any folder, and the
        module renames only what sits where the collector was told to write. It is then renamed
        to <staging>\<Module>; one run per collector per umbrella run, so the name is free, and a
        name that is taken is refused. The rename is tried three times, 500 ms apart, sleeping
        only after a failure, because an indexer or EDR handle under a freshly written folder
        makes NTFS refuse a rename for a moment. On a successful rename the OutputFolder of every
        row that pointed into the old folder is rewritten to the new location, on a copy of the
        row, so the caller's objects are not changed. A refused or failed rename is returned in
        ArrangeError as "arrange: <Module>: <message>" ("path outside the staging folder: <path>"
        for a folder outside), the folder stays where it is and the rows keep their OutputFolder.

        Returns a hashtable: Type, Module, Version (the nested module's version), RunId (the
        collector's original run folder name, $null when no folder was found), Rows,
        DurationMs, Error (the host throw message, one line, or $null) and ArrangeError
        (the arrange line or $null).

    .PARAMETER Type
        One of Firewall, RSOP, ScheduledTask, SecEdit, Service.

    .PARAMETER ComputerName
        The de-duplicated requested names.

    .PARAMETER StagingPath
        The folder the collector writes its run folder into: <run>\collectors.

    .PARAMETER Credential
        Passed to the collector only when given.

    .PARAMETER UseSSL
        Passed to the collector only when set.

    .PARAMETER ThrottleLimit
        Passed to the collector. Always passed explicitly by the caller.

    .NOTES
        FUNCTION: Invoke-RemoteBaselineCollector
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Collections.Hashtable
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$StagingPath,

        [System.Management.Automation.PSCredential]
        $Credential,

        [switch]$UseSSL,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 256)]
        [int]$ThrottleLimit
    )

    $info = @(Get-RemoteBaselineCollectorInfo -Type $Type) | Select-Object -First 1
    if ($null -eq $info) {
        throw "Unknown collector type: $Type"
    }

    $callParams = @{
        ComputerName  = @($ComputerName)
        OutputPath    = $StagingPath
        ThrottleLimit = $ThrottleLimit
        WarningAction = 'SilentlyContinue'
    }
    if ($null -ne $Credential) { $callParams['Credential'] = $Credential }
    if ($UseSSL) { $callParams['UseSSL'] = $true }

    # Taken before the call so the folder search below can tell this call's run folder from anything older.
    $callStart = (Get-Date).ToUniversalTime()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $hostError = $null
    $version = $null
    $rows = @()
    try {
        # The FunctionInfo from the nested module is called, not a name: an alias or function of the same name in the caller's session must not run in its place. A module that is not bundled throws here and becomes the synthetic rows below.
        $resolved = Get-RemoteBaselineCollectorCommand -Module $info.Module -Function $info.Function
        $version = $resolved.Version
        $collectorCommand = $resolved.Command
        $rows = @(& $collectorCommand @callParams | Where-Object { $null -ne $_ })
    } catch {
        $hostError = ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message
        $rows = @()
    }
    $stopwatch.Stop()
    $durationMs = [int]$stopwatch.ElapsedMilliseconds

    # One row per requested name, always: a throw gives a synthetic row for every name, and a name the collector left out gets one too. The column set matches a collector's own Failed row for a computer that was never reached.
    $byName = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $rows) {
        $rowName = Get-RemoteBaselineSafeProperty -InputObject $row -Name 'ComputerName' -Default $null
        if (-not [string]::IsNullOrEmpty($rowName) -and -not $byName.ContainsKey([string]$rowName)) { $byName[[string]$rowName] = $row }
    }
    $completeRows = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @($ComputerName)) {
        if ($byName.ContainsKey($name)) {
            [void]$completeRows.Add($byName[$name])
            continue
        }
        $message = if ($null -ne $hostError) { "host: $hostError" } else { 'host: no result row returned' }
        [void]$completeRows.Add([pscustomobject]@{
                ComputerName = $name
                ComputerId   = $null
                Status       = 'Failed'
                Transport    = $null
                OutputFolder = ''
                IsElevated   = $null
                Error        = $message
                ErrorCount   = 1
                Errors       = [string[]]@($message)
            })
    }
    $resultRows = $completeRows.ToArray()

    $runId = $null
    $arrangeError = $null
    try {
        $collectorRunFolder = $null
        foreach ($row in $resultRows) {
            $outputFolder = Get-RemoteBaselineSafeProperty -InputObject $row -Name 'OutputFolder' -Default $null
            if (-not [string]::IsNullOrWhiteSpace($outputFolder)) {
                $collectorRunFolder = Split-Path -Path ([string]$outputFolder) -Parent
                break
            }
        }
        if ([string]::IsNullOrEmpty($collectorRunFolder) -and (Test-Path -LiteralPath $StagingPath)) {
            $newest = Get-ChildItem -LiteralPath $StagingPath -Directory -Filter ($info.Module + '-*Z*') -ErrorAction Stop |
                Where-Object { $_.CreationTimeUtc -ge $callStart.AddSeconds(-2) } |
                Sort-Object -Property CreationTimeUtc -Descending |
                Select-Object -First 1
            if ($null -ne $newest) { $collectorRunFolder = $newest.FullName }
        }

        if (-not [string]::IsNullOrEmpty($collectorRunFolder)) {
            $runId = Split-Path -Path $collectorRunFolder -Leaf
            # Containment first: a row names any folder it likes, and nothing outside the staging folder is renamed.
            if (-not (Test-RemoteBaselineChildPath -Path $collectorRunFolder -Folder $StagingPath)) {
                throw "path outside the staging folder: $collectorRunFolder"
            }
            $newFolder = Join-Path -Path (Split-Path -Path $collectorRunFolder -Parent) -ChildPath $info.Module
            # A taken name will not free itself, so it is refused before the retry loop and costs no sleep.
            if (Test-Path -LiteralPath $newFolder) {
                throw "the target $newFolder exists"
            }
            # Three attempts 500 ms apart, sleeping only after a failure: an indexer or EDR handle under a freshly written folder makes NTFS refuse the rename for a moment.
            $attempt = 0
            while ($true) {
                $attempt++
                try {
                    Rename-Item -LiteralPath $collectorRunFolder -NewName $info.Module -ErrorAction Stop -WhatIf:$false -Confirm:$false
                    break
                } catch {
                    if ($attempt -ge 3) { throw }
                    Start-Sleep -Milliseconds 500
                }
            }

            # Rows are rewritten on copies, and only those that pointed into the old folder: the OutputFolder of a collector row names the folder that no longer exists after the rename.
            $rebased = [System.Collections.Generic.List[object]]::new()
            foreach ($row in $resultRows) {
                $outputFolder = Get-RemoteBaselineSafeProperty -InputObject $row -Name 'OutputFolder' -Default $null
                if (-not [string]::IsNullOrWhiteSpace($outputFolder) -and (Split-Path -Path ([string]$outputFolder) -Parent) -ieq $collectorRunFolder) {
                    $copy = $row.PSObject.Copy()
                    $copy.OutputFolder = Join-Path -Path $newFolder -ChildPath (Split-Path -Path ([string]$outputFolder) -Leaf)
                    [void]$rebased.Add($copy)
                } else {
                    [void]$rebased.Add($row)
                }
            }
            $resultRows = $rebased.ToArray()
        }
    } catch {
        $arrangeError = 'arrange: ' + $info.Module + ': ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message)
    }

    return @{
        Type         = $info.Type
        Module       = $info.Module
        Version      = $version
        RunId        = $runId
        Rows         = @($resultRows)
        DurationMs   = $durationMs
        Error        = $hostError
        ArrangeError = $arrangeError
    }
}
