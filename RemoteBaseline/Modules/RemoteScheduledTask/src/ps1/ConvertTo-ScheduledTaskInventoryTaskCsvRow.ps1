<#PSScriptInfo

.DESCRIPTION Builds the tasks.csv rows for one computer, with the Binary columns looked up by ExecutablePath

.VERSION 1.4.1

.GUID 10c93fda-9ac4-4dd1-b0e1-d27e18510086

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function ConvertTo-ScheduledTaskInventoryTaskCsvRow {

    <#
    .SYNOPSIS
        Builds the tasks.csv rows for one computer, with the Binary columns looked up by
        ExecutablePath.

    .DESCRIPTION
        Produces one flat row per task, in the exact column order tasks.csv requires. Command,
        Arguments, WorkingDirectory and ExecutablePath come from the first Exec action in document
        order, ClassId from the first ComHandler action, each empty when there is none. The
        Binary* columns are a lookup, not an interpretation: for each task row, the binary object
        whose Path equals the task's ExecutablePath (case-insensitive) supplies them, and they are
        empty when no binary matches. This is what lets an operator open one file in Excel and see
        each task with its account, its command and its binary's publisher side by side.

    .PARAMETER Tasks
        The Tasks array from the worker object. May be empty.

    .PARAMETER Binaries
        The Binaries array from the worker object. May be empty.

    .NOTES
        FUNCTION: ConvertTo-ScheduledTaskInventoryTaskCsvRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [psobject[]]$Tasks,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [psobject[]]$Binaries
    )

    # The tasks.csv columns in file order: the same list Complete-ScheduledTaskInventoryComputer passes to the writer.
    $columnNames = @('TaskPath', 'TaskName', 'FolderPath', 'State', 'Enabled', 'Hidden', 'Author', 'Date', 'Source', 'TaskVersion', 'PrincipalId', 'PrincipalToken', 'PrincipalSid', 'PrincipalName', 'LogonType', 'RunLevel', 'LastRunTime', 'LastTaskResultHex', 'NextRunTime', 'NumberOfMissedRuns', 'ActionCount', 'ExecActionCount', 'ComHandlerActionCount', 'Command', 'Arguments', 'WorkingDirectory', 'ExecutablePath', 'ClassId', 'TriggerCount', 'TriggerTypes', 'ExecutionTimeLimit', 'MultipleInstancesPolicy', 'StartWhenAvailable', 'RunOnlyIfIdle', 'RunOnlyIfNetworkAvailable', 'Sddl', 'RegistrationSecurityDescriptor', 'BinaryExists', 'BinaryCompanyName', 'BinaryProductName', 'BinaryFileVersion', 'BinarySignatureStatus', 'BinarySignerSubject', 'Description')

    $binaryMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($bin in @($Binaries)) {
        $binPath = Get-ScheduledTaskInventorySafeProperty -InputObject $bin -Name 'Path' -Default $null
        if ($binPath) { $binaryMap[$binPath] = $bin }
    }

    $rows = @()
    foreach ($task in @($Tasks)) {
        $actions = @(Get-ScheduledTaskInventorySafeProperty -InputObject $task -Name 'Actions' -Default @())

        $firstExec = $null
        $firstComHandler = $null
        foreach ($action in $actions) {
            $actionType = Get-ScheduledTaskInventorySafeProperty -InputObject $action -Name 'Type' -Default $null
            if ((-not $firstExec) -and ($actionType -eq 'Exec')) { $firstExec = $action }
            if ((-not $firstComHandler) -and ($actionType -eq 'ComHandler')) { $firstComHandler = $action }
        }

        $command = ''
        $arguments = ''
        $workingDirectory = ''
        $execPath = ''
        if ($firstExec) {
            $command = Get-ScheduledTaskInventorySafeProperty -InputObject $firstExec -Name 'Command' -Default ''
            $arguments = Get-ScheduledTaskInventorySafeProperty -InputObject $firstExec -Name 'Arguments' -Default ''
            $workingDirectory = Get-ScheduledTaskInventorySafeProperty -InputObject $firstExec -Name 'WorkingDirectory' -Default ''
            $execPath = Get-ScheduledTaskInventorySafeProperty -InputObject $firstExec -Name 'ExecutablePath' -Default ''
        }

        $classId = ''
        if ($firstComHandler) {
            $classId = Get-ScheduledTaskInventorySafeProperty -InputObject $firstComHandler -Name 'ClassId' -Default ''
        }

        $matchedBinary = $null
        if ($execPath -and $binaryMap.ContainsKey($execPath)) { $matchedBinary = $binaryMap[$execPath] }

        # The columns built from the first Exec or ComHandler action or from the matched binary. Every other column is a plain read of the property of the same name from the task.
        $builtColumns = @{
            Command               = $command
            Arguments             = $arguments
            WorkingDirectory      = $workingDirectory
            ExecutablePath        = $execPath
            ClassId               = $classId
            BinaryExists          = $(if ($matchedBinary) { Get-ScheduledTaskInventorySafeProperty -InputObject $matchedBinary -Name 'Exists' -Default $null } else { '' })
            BinaryCompanyName     = $(if ($matchedBinary) { Get-ScheduledTaskInventorySafeProperty -InputObject $matchedBinary -Name 'CompanyName' -Default $null } else { '' })
            BinaryProductName     = $(if ($matchedBinary) { Get-ScheduledTaskInventorySafeProperty -InputObject $matchedBinary -Name 'ProductName' -Default $null } else { '' })
            BinaryFileVersion     = $(if ($matchedBinary) { Get-ScheduledTaskInventorySafeProperty -InputObject $matchedBinary -Name 'FileVersion' -Default $null } else { '' })
            BinarySignatureStatus = $(if ($matchedBinary) { Get-ScheduledTaskInventorySafeProperty -InputObject $matchedBinary -Name 'SignatureStatus' -Default $null } else { '' })
            BinarySignerSubject   = $(if ($matchedBinary) { Get-ScheduledTaskInventorySafeProperty -InputObject $matchedBinary -Name 'SignerSubject' -Default $null } else { '' })
        }

        $rowProperties = [ordered]@{}
        foreach ($column in $columnNames) {
            if ($builtColumns.ContainsKey($column)) {
                $rowProperties[$column] = $builtColumns[$column]
            } else {
                $rowProperties[$column] = Get-ScheduledTaskInventorySafeProperty -InputObject $task -Name $column -Default $null
            }
        }
        $rows += [pscustomobject]$rowProperties
    }

    return @($rows)
}
