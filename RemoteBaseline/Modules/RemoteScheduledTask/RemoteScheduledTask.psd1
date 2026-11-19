@{
    RootModule           = 'RemoteScheduledTask.psm1'
    ModuleVersion        = '1.6.0'
    GUID                 = 'e10d3738-5b99-4e50-82c4-db85aa420f15'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2026 Tom Stryhn'
    Description          = 'PowerShell Module to collect every scheduled task with the fields of its definition, principal and its SID, security descriptor, run-time state and action binary identity from local and remote computers'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Get-ScheduledTaskInventory')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteScheduledTask.psd1',
        'RemoteScheduledTask.psm1',
        'LICENSE',
        'src\ps1\Complete-ScheduledTaskInventoryComputer.ps1',
        'src\ps1\ConvertTo-ScheduledTaskInventoryResultRow.ps1',
        'src\ps1\ConvertTo-ScheduledTaskInventoryTaskCsvRow.ps1',
        'src\ps1\Get-ScheduledTaskInventory.ps1',
        'src\ps1\Get-ScheduledTaskInventoryHostComputerId.ps1',
        'src\ps1\Get-ScheduledTaskInventorySafeProperty.ps1',
        'src\ps1\Get-ScheduledTaskInventoryWorker.ps1',
        'src\ps1\Initialize-ScheduledTaskInventoryRunFolder.ps1',
        'src\ps1\Invoke-ScheduledTaskInventoryLocal.ps1',
        'src\ps1\Invoke-ScheduledTaskInventoryRemote.ps1',
        'src\ps1\Resolve-ScheduledTaskInventoryComputerList.ps1',
        'src\ps1\Resolve-ScheduledTaskInventoryRemoteErrorName.ps1',
        'src\ps1\Resolve-ScheduledTaskInventoryUniqueFolder.ps1',
        'src\ps1\Test-ScheduledTaskInventoryLocalName.ps1',
        'src\ps1\Write-ScheduledTaskInventoryCsvFile.ps1',
        'src\ps1\Write-ScheduledTaskInventoryTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Security', 'ScheduledTasks', 'TaskScheduler', 'WinRM')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteBaseline'
            ReleaseNotes = 'RemoteScheduledTask 1.6.0. Csv guard: a text cell that starts with =, +, - or @ is written with one apostrophe in front in every csv file, so a spreadsheet shows it as text and does not run it as a formula. The json files are not changed and hold the exact value. The test suite runs from any folder, also one with square brackets in its name. Application package SIDs and capability SIDs are no longer rows in accounts.json and accounts.csv. They are classed from the SID text without an account lookup and written to appcontainers.json and appcontainers.csv beside them, and summary.json and system.json gain AppContainerCount. Output convention 1.5 (run.json SchemaVersion 1.5). RemoteScheduledTask 1.5.0. Json is the default output: tasks, accounts and binaries are written as json files, and the new -OutputFormat parameter (Json, Csv or Both) selects the json files, the csv files or both. results.csv is written only with Csv or Both, and run.json always holds the results. -OutputPath is optional and defaults to the current file-system location. No warning on PowerShell 7.7, where ConvertTo-Csv -NoTypeInformation is obsolete. The run folder is removed again when the output path is not writable. Output convention 1.4 (run.json gains OutputFormat after SkipSidReference, SchemaVersion 1.4). RemoteScheduledTask 1.4.1. A missing failover.exe or MusNotification.exe in System32, named only by tasks under \Microsoft\Windows\UpdateOrchestrator\ (the two programs Windows does not ship), no longer adds an error line or turns the row Partial. It still counts in BinaryMissingCount and shows in binaries.json and summary.json, and Get-ScheduledTaskInventory writes one warning per path. No file format change. RemoteScheduledTask 1.4.0. The worker reads four SID reference values (MachineSid, DomainSid, ComputerAccountSid, DomainNetbiosName) once per computer and system.json carries them. A new -SkipSidReference switch leaves them unread for a caller that gets them from another collector, and run.json records SkipSidReference. Output convention 1.3 (run.json SchemaVersion 1.3). RemoteScheduledTask 1.3.0. Unelevated runs report the shortfall and come back Partial (RemoteScheduledTask, RemoteService). Every error message and csv cell is one line. The per-computer folder name is sanitised. The result callback never ends the run. The loader is hardened against wildcard paths. Per-task guard on the run-time fields, direct property reads, in-place sort, late-error recompute outside the loop, ComputerId pre-set before the try, one column variable per csv select, help-example test over a tests fixture. README gains Known limits, Automation, File formats, Support and versioning and workgroup prerequisites. New SECURITY.md. Examples anonymised. Output convention 1.2. RemoteScheduledTask 1.2.1. system.json is built from a fixed property list, so its key order and the Collector, CollectorVersion and RunId keys no longer depend on the shape of the worker result, and a binary path with characters that are illegal in a path is reported as not found the same way locally and over WinRM, without an extra error entry on the remote row. The Get-WmiObject fallback is removed and internal code is simplified. No output or data format change. RemoteScheduledTask 1.2.0. New -UseSSL switch: remote targets are reached over WinRM HTTPS (port 5986) instead of HTTP, and run.json gains UseSSL after ThrottleLimit. The output convention moves to version 1.1 (SchemaVersion 1.1). RemoteScheduledTask 1.1.1. The help-example verification test skips itself when the local live run capture is absent, so the published test suite passes on a fresh clone, and List[object] construction in the worker uses the typed constructor instead of New-Object. No output or data format change. RemoteScheduledTask 1.1.0. Adopts the shared Remote collector output convention: run.json and system.json carry Collector, CollectorVersion, SchemaVersion, ComputerId and MachineGuid so a run and a computer join across RemoteSecEdit, RemoteService and RemoteScheduledTask on one key, results.csv gains ComputerId and ErrorCount, and accounts.csv renames TaskCount and Tasks to ReferenceCount and References.'
        }
    }
}
