<#PSScriptInfo

.DESCRIPTION Builds one RemoteBaseline.Result row from the collectors' rows for one requested name

.VERSION 1.4.0

.GUID a26b8d89-58c5-4cb3-a5b0-e80249d67712

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region ConvertTo-RemoteBaselineResultRow
function ConvertTo-RemoteBaselineResultRow {

    <#
    .SYNOPSIS
        Builds one RemoteBaseline.Result row from the collectors' rows for one requested name.

    .DESCRIPTION
        A pure function: the same input gives the same row, so the caller builds the row again
        when a later step (the manifest, the archive) adds a run-level line. Reads each selected
        collector's row for the name and derives:

        ComputerId, the first non-empty value among the rows in run order. Transport, the first
        non-empty value (an empty string when no row has one). IsElevated, the first non-null
        value as a bool. The per-type status and error count columns (null for a type that was
        not selected or has no row). Errors, every collector row's Errors entries prefixed
        "<Type>: " in run order, then ExtraError (the umbrella's own lines: arrange, host.json,
        manifest, zip), each one trimmed single line. Error, the first entry or an empty string.
        ErrorCount, the number of entries.

        Status: Failed when no selected collector has a row for the name or every row present is
        Failed. Success when every selected collector has a row, every row is Success and
        ExtraError is empty. Partial in every other case, so a run-level line makes a Success row
        Partial and never changes a Failed one.

        Types is a string[] here, and results.csv joins it with ", " when it is written.

    .PARAMETER ComputerName
        The name as requested.

    .PARAMETER Type
        The selected types in run order.

    .PARAMETER CollectorRow
        A hashtable from type name to that collector's row for this name. A type with no entry
        has no row.

    .PARAMETER OutputFolder
        The host folder, or an empty string or $null when no collector's folder reached one.

    .PARAMETER ExtraError
        The umbrella's own lines for this name, already prefixed. May be empty or $null.

    .NOTES
        FUNCTION: ConvertTo-RemoteBaselineResultRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteBaseline.Result
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String]$ComputerName,

        [Parameter(Mandatory = $true)]
        [String[]]$Type,

        [AllowNull()]
        [Hashtable]$CollectorRow,

        [AllowNull()]
        [AllowEmptyString()]
        [String]$OutputFolder,

        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [String[]]$ExtraError
    )

    # Run order, which is also the order of the per-type columns in the row.
    $allTypes = @('System', 'RSOP', 'ScheduledTask', 'SecEdit', 'Service', 'Firewall', 'EventLog')

    $statusByType = @{}
    $countByType = @{}
    $errorLines = [System.Collections.Generic.List[String]]::new()
    $computerId = $null
    $transport = ''
    $isElevated = $null
    $presentCount = 0
    $successCount = 0
    $failedCount = 0

    foreach ($typeName in @($Type)) {
        $collectorRowValue = $null
        if ($null -ne $CollectorRow -and $CollectorRow.ContainsKey($typeName)) {
            $collectorRowValue = $CollectorRow[$typeName]
        }
        if ($null -eq $collectorRowValue) {
            continue
        }

        $presentCount++
        $rowStatus = [String](Get-RemoteBaselineSafeProperty -InputObject $collectorRowValue -Name 'Status' -Default '')
        if ($rowStatus -eq 'Success') {
            $successCount++
        }
        if ($rowStatus -eq 'Failed') {
            $failedCount++
        }
        $statusByType[$typeName] = $rowStatus

        $rowErrors = @(Get-RemoteBaselineSafeProperty -InputObject $collectorRowValue -Name 'Errors' -Default @() | Where-Object { -not [String]::IsNullOrWhiteSpace([String]$_) })
        if ($rowErrors.Count -eq 0) {
            # A row without an Errors list but with an Error text still names its problem.
            $singleError = Get-RemoteBaselineSafeProperty -InputObject $collectorRowValue -Name 'Error' -Default $null
            if (-not [String]::IsNullOrWhiteSpace([String]$singleError)) {
                $rowErrors = @($singleError)
            }
        }
        foreach ($rowError in $rowErrors) {
            [Void]$errorLines.Add($typeName + ': ' + (ConvertTo-RemoteBaselineOneLine -Text $rowError))
        }
        $rowErrorCount = Get-RemoteBaselineSafeProperty -InputObject $collectorRowValue -Name 'ErrorCount' -Default $null
        if ($null -ne $rowErrorCount -and "$rowErrorCount" -match '^\d+$') {
            $countByType[$typeName] = [Int]$rowErrorCount
        }
        else {
            $countByType[$typeName] = $rowErrors.Count
        }

        if ($null -eq $computerId) {
            $rowComputerId = Get-RemoteBaselineSafeProperty -InputObject $collectorRowValue -Name 'ComputerId' -Default $null
            if (-not [String]::IsNullOrEmpty([String]$rowComputerId)) {
                $computerId = [String]$rowComputerId
            }
        }
        if ($transport -eq '') {
            $rowTransport = Get-RemoteBaselineSafeProperty -InputObject $collectorRowValue -Name 'Transport' -Default $null
            if (-not [String]::IsNullOrEmpty([String]$rowTransport)) {
                $transport = [String]$rowTransport
            }
        }
        if ($null -eq $isElevated) {
            $rowElevated = Get-RemoteBaselineSafeProperty -InputObject $collectorRowValue -Name 'IsElevated' -Default $null
            if ($null -ne $rowElevated) {
                $isElevated = [Bool]$rowElevated
            }
        }
    }

    $extraLines = @($ExtraError | Where-Object { -not [String]::IsNullOrWhiteSpace($_) } | ForEach-Object { ConvertTo-RemoteBaselineOneLine -Text $_ })
    foreach ($line in $extraLines) {
        [Void]$errorLines.Add($line)
    }

    if ($presentCount -eq 0 -or $failedCount -eq $presentCount) {
        $status = 'Failed'
    }
    elseif ($successCount -eq @($Type).Count -and $extraLines.Count -eq 0) {
        $status = 'Success'
    }
    else {
        $status = 'Partial'
    }

    $errorArray = [String[]]$errorLines.ToArray()
    $folderValue = ''
    if (-not [String]::IsNullOrEmpty($OutputFolder)) {
        $folderValue = $OutputFolder
    }

    $result = [ordered]@{
        PSTypeName   = 'RemoteBaseline.Result'
        ComputerName = $ComputerName
        ComputerId   = $computerId
        Status       = $status
        Transport    = $transport
        OutputFolder = $folderValue
        IsElevated   = $isElevated
        Types        = [String[]]@($Type)
    }
    foreach ($typeName in $allTypes) {
        $value = $null
        if ($statusByType.ContainsKey($typeName)) {
            $value = $statusByType[$typeName]
        }
        $result[$typeName + 'Status'] = $value
    }
    foreach ($typeName in $allTypes) {
        $value = $null
        if ($countByType.ContainsKey($typeName)) {
            $value = $countByType[$typeName]
        }
        $result[$typeName + 'ErrorCount'] = $value
    }
    $result['Error'] = $(if ($errorArray.Count -gt 0) { $errorArray[0] } else { '' })
    $result['ErrorCount'] = $errorArray.Count
    $result['Errors'] = $errorArray

    return [PSCustomObject]$result
}
#endregion
