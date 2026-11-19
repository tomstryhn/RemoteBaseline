<#PSScriptInfo

.DESCRIPTION Writes rows to a csv file with a UTF-8 byte order mark on both engines

.VERSION 1.6.0

.GUID c280a8a2-9939-4ba1-aa77-65f5e3bcdb19

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Write-ScheduledTaskInventoryCsvFile
function Write-ScheduledTaskInventoryCsvFile {

    <#
    .SYNOPSIS
        Writes rows to a csv file with a UTF-8 byte order mark on both engines.

    .DESCRIPTION
        Used for every csv file the module writes (results.csv, tasks.csv, accounts.csv,
        appcontainers.csv, binaries.csv), so all of them are built the same way: ConvertTo-Csv turns the rows into
        lines, with -NoTypeInformation on Windows PowerShell, where it drops the type line, and
        without it on PowerShell 7, where it is obsolete, warns and changes nothing. The lines
        are the same on both engines. [System.IO.File]::WriteAllLines writes them with a
        UTF8Encoding whose byte order mark is on, which is what Export-Csv -Encoding UTF8 does
        not give consistently across Windows PowerShell 5.1 and PowerShell 7. Export-Csv is never
        used here: a $null entry in Row would throw it, so every $null row is filtered out before
        ConvertTo-Csv ever sees it. An empty Row collection writes no lines at all unless Column is
        supplied, in which case a header-only file is built from Column instead, since
        ConvertTo-Csv produces nothing at all, not even a header, for zero input objects. Every
        string value is trimmed and has its whitespace collapsed to one space before it is
        written, so a cell is always one line. Null, empty string, numbers and booleans are not
        changed, and the objects the caller passed in are not modified.

        A string cell whose first character, after the trim, is = + - or @ is written with one
        apostrophe in front, so a spreadsheet shows it as text and does not run it as a formula.
        Only string values are guarded. Null, numbers and booleans are written as they are, and the
        header row is not touched. The json files are written from the source objects and carry
        the exact value.

    .PARAMETER Row
        The rows to write. May be empty, and may contain $null entries, which are dropped.

    .PARAMETER Path
        The file to write, as a literal path.

    .PARAMETER Column
        The column names, in order, used to build a header-only file when Row is empty. Ignored
        when Row is not empty, since ConvertTo-Csv derives the header from the rows themselves.

    .NOTES
        FUNCTION: Write-ScheduledTaskInventoryCsvFile
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        None.
    #>

    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [PSObject[]]$Row,

        [Parameter(Mandatory = $true)]
        [String]$Path,

        [AllowNull()]
        [String[]]$Column
    )

    $rows = @($Row | Where-Object { $null -ne $_ })

    $convertParameters = @{}
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $convertParameters['NoTypeInformation'] = $true
    }

    if ($rows.Count -gt 0) {
        # One line per csv cell: a string value is trimmed and its whitespace, line breaks included, collapsed
        # to one space, so a line break inside a value can never split a csv row. Each row's strings are
        # scanned once. A row with no string that needs a change goes in as the caller's own object, because
        # copying every row cost most of the time on a 20,000-row file. Only a row that needs a change is
        # rebuilt as a new ordered object with the same property names, so the caller's objects, and the json
        # files written from them, keep the source form. The test is any whitespace other than single inner
        # spaces, which is exactly the set the collapse would alter. Null, an empty string, numbers and
        # booleans pass through untouched, which keeps a null a bare cell and an empty string a quoted empty
        # cell. A string that then starts with = + - or @ gets one apostrophe in front, because a spreadsheet
        # takes such a cell as a formula and the values here come from the assessed computer. The guard
        # runs after the trim, so leading whitespace cannot hide the character. A row with such a cell is
        # rebuilt like any other row that needs a change.
        $outputRows = [System.Collections.Generic.List[Object]]::new()
        foreach ($sourceRow in $rows) {
            $needsChange = $false
            foreach ($property in $sourceRow.PSObject.Properties) {
                $cellValue = $property.Value
                if ($cellValue -is [String] -and ($cellValue -ne $cellValue.Trim() -or $cellValue -match '\s{2,}|[^\S ]' -or $cellValue -match '^[=+\-@]')) {
                    $needsChange = $true
                    break
                }
            }
            if (-not $needsChange) {
                [Void]$outputRows.Add($sourceRow)
                continue
            }
            $cleanRow = [ordered]@{}
            foreach ($property in $sourceRow.PSObject.Properties) {
                $cellValue = $property.Value
                if ($cellValue -is [String]) {
                    $cellValue = $cellValue.Trim() -replace '\s+', ' '
                    if ($cellValue -match '^[=+\-@]') {
                        $cellValue = "'" + $cellValue
                    }
                }
                $cleanRow[$property.Name] = $cellValue
            }
            [Void]$outputRows.Add([PSCustomObject]$cleanRow)
        }
        $lines = @($outputRows.ToArray() | ConvertTo-Csv @convertParameters)
    }
    elseif ($Column -and @($Column).Count -gt 0) {
        # A single placeholder object with every Column property set to $null, so the header line
        # ConvertTo-Csv builds for it matches tasks.csv or binaries.csv exactly, without hand-quoting column
        # names here too.
        $placeholder = [ordered]@{}
        foreach ($name in @($Column)) {
            $placeholder[$name] = $null
        }
        $headerLines = @([PSCustomObject]$placeholder | ConvertTo-Csv @convertParameters)
        $lines = @($headerLines | Select-Object -First 1)
    }
    else {
        $lines = @()
    }

    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, $lines, $encoding)
}
#endregion
