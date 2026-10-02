<#PSScriptInfo

.DESCRIPTION Moves a collector's computer folders under the host folders of the run

.VERSION 1.1.0

.GUID 35b62a6a-9ade-41fb-8524-12f18d4a5fcc

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Move-RemoteBaselineComputerFolder {

    <#
    .SYNOPSIS
        Moves a collector's computer folders under the host folders of the run.

    .DESCRIPTION
        Takes the rows of one collector, in run order of the collectors, and moves every computer
        folder a row names (a non-empty OutputFolder) to <host folder>\<Module>. The host folder
        is <run>\<REPORTED>_<build>_<umbrellaStamp>Z, where REPORTED and build are parsed from the
        right of the computer folder leaf <REPORTED>_<build>_<stamp>Z[_n] (stamp and suffix, then
        build, then the rest is the reported name) and umbrellaStamp is the run folder's own stamp.

        Rows that name the same computer folder (local aliases) are one group: one move, one host
        folder, and every requested name of the group is mapped to it. A requested name that is
        already in HostMap (an earlier collector reached it) keeps its host folder and the group
        joins it, so one host ends in one folder per requested name. A group with no mapped name
        gets a new host folder through the unique folder rule, which adds _2, _3 when the name is
        taken: that is what separates two requested names of one host (a short name and a
        fully qualified name) in the first collector that reaches them. The host folder is created
        just before its first move and removed again when that move fails and it is still empty, so
        a failure leaves no empty host folder.

        Before anything is created or moved, the computer folder's parent must be the collector's
        run folder (CollectorFolder, full resolved paths, ordinal, ignoring case): a row can name
        any folder, and the module moves only what sits where the collector was told to write.
        The move is tried three times, 500 ms apart, sleeping only after a failure, because an
        indexer or EDR handle under a freshly written folder makes NTFS refuse it for a moment.

        The target must not exist. A failure (a folder outside the collector's run folder, an
        unparsable folder name, an existing target, a move error) gives the rows of the group the
        error "arrange: <Module>: <message>" ("path outside the staging folder: <path>" for a
        folder outside) and leaves the computer folder where it is. HostMap, a dictionary from requested name to host
        folder path (case-insensitive keys), is shared by every call of one run and updated here;
        a name is added only after its folder moved.

        Returns one outcome object per row that had a non-empty OutputFolder: ComputerName,
        HostFolder (the host folder the name maps to after this call, $null when none) and Error
        ($null or the arrange line).

    .PARAMETER Module
        The collector module name, which is also the subfolder name inside the host folder.

    .PARAMETER Row
        The collector's rows, with OutputFolder naming the computer folder where it is now.

    .PARAMETER RunFolder
        The umbrella run folder. Its leaf carries the umbrella stamp.

    .PARAMETER CollectorFolder
        The collector's run folder as the rows see it now: <run>\collectors\<Module> after a
        successful rename, the original <run>\collectors\<Module>-<stamp>Z folder when the rename
        was refused or failed. A computer folder whose parent is another folder is not moved.

    .PARAMETER HostMap
        A [System.Collections.Generic.Dictionary[string,string]] with an OrdinalIgnoreCase
        comparer, requested name to host folder path. Updated in place.

    .NOTES
        FUNCTION: Move-RemoteBaselineComputerFolder
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$Module,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [Parameter(Mandatory = $true)]
        [string]$RunFolder,

        [Parameter(Mandatory = $true)]
        [string]$CollectorFolder,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.Dictionary[string, string]]$HostMap
    )

    $outcomes = [System.Collections.Generic.List[object]]::new()

    $stampMatch = [regex]::Match((Split-Path -Path $RunFolder -Leaf), '^RemoteBaseline-(?<stamp>\d{8}-\d{6})Z(?:_\d+)?$')

    # Rows that name the same computer folder are one group, keyed case-insensitively by the folder path, in first-seen order.
    $groups = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $groupOrder = [System.Collections.Generic.List[string]]::new()
    foreach ($sourceRow in @($Row | Where-Object { $null -ne $_ })) {
        $source = Get-RemoteBaselineSafeProperty -InputObject $sourceRow -Name 'OutputFolder' -Default $null
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        $name = [string](Get-RemoteBaselineSafeProperty -InputObject $sourceRow -Name 'ComputerName' -Default '')
        if (-not $groups.ContainsKey([string]$source)) {
            $groups[[string]$source] = [pscustomobject]@{ Source = [string]$source; Names = [System.Collections.Generic.List[string]]::new() }
            [void]$groupOrder.Add([string]$source)
        }
        [void]$groups[[string]$source].Names.Add($name)
    }

    foreach ($key in $groupOrder) {
        $group = $groups[$key]
        $errorLine = $null
        $hostFolder = $null
        $createdHere = $false
        try {
            # Containment first, before a host folder is created for it: nothing outside the collector's run folder is moved.
            if (-not (Test-RemoteBaselineChildPath -Path $group.Source -Folder $CollectorFolder)) {
                throw "path outside the staging folder: $($group.Source)"
            }

            foreach ($name in $group.Names) {
                if ($HostMap.ContainsKey($name)) { $hostFolder = $HostMap[$name]; break }
            }

            if ($null -eq $hostFolder) {
                if (-not $stampMatch.Success) {
                    throw 'the run folder name carries no stamp'
                }
                $leaf = Split-Path -Path $group.Source -Leaf
                $leafMatch = [regex]::Match($leaf, '^(?<name>.+)_(?<build>[^_]+)_(?<stamp>\d{8}-\d{6})Z(?:_\d+)?$')
                if (-not $leafMatch.Success) {
                    throw "the computer folder name '$leaf' is not <NAME>_<build>_<stamp>Z"
                }
                $candidate = Join-Path -Path $RunFolder -ChildPath ('{0}_{1}_{2}Z' -f $leafMatch.Groups['name'].Value, $leafMatch.Groups['build'].Value, $stampMatch.Groups['stamp'].Value)
                $hostFolder = Resolve-RemoteBaselineUniqueFolder -Path $candidate
                $createdHere = $true
            }

            $target = Join-Path -Path $hostFolder -ChildPath $Module
            if (Test-Path -LiteralPath $target) {
                throw "the target $target exists"
            }
            # Three attempts 500 ms apart, sleeping only after a failure: an indexer or EDR handle under a freshly written folder makes NTFS refuse the move for a moment.
            $attempt = 0
            while ($true) {
                $attempt++
                try {
                    Move-Item -LiteralPath $group.Source -Destination $target -ErrorAction Stop -WhatIf:$false -Confirm:$false
                    break
                } catch {
                    if ($attempt -ge 3) { throw }
                    Start-Sleep -Milliseconds 500
                }
            }
            foreach ($name in $group.Names) { $HostMap[$name] = $hostFolder }
        } catch {
            $errorLine = 'arrange: ' + $Module + ': ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message)
            # Partial state: a host folder created for this move and left empty would read as a host that was reached. A folder that holds anything is left alone.
            if ($createdHere -and $null -ne $hostFolder -and (Test-Path -LiteralPath $hostFolder) -and @(Get-ChildItem -LiteralPath $hostFolder -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                Remove-Item -LiteralPath $hostFolder -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
            }
        }

        foreach ($name in $group.Names) {
            $mapped = $null
            if ($HostMap.ContainsKey($name)) { $mapped = $HostMap[$name] }
            [void]$outcomes.Add([pscustomobject]@{ ComputerName = $name; HostFolder = $mapped; Error = $errorLine })
        }
    }

    return $outcomes.ToArray()
}
