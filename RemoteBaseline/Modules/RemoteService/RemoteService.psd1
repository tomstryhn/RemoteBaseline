@{
    RootModule           = 'RemoteService.psm1'
    ModuleVersion        = '1.7.0'
    GUID                 = '554beb48-b414-4115-9604-ad3758ecac8a'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2026 Tom Stryhn'
    Description          = 'PowerShell Module to collect every Windows service with its configuration, account and its SID, security descriptor and binary identity from local and remote computers'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Get-ServiceInventory')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteService.psd1',
        'RemoteService.psm1',
        'LICENSE',
        'src\ps1\Complete-ServiceInventoryComputer.ps1',
        'src\ps1\ConvertTo-ServiceInventoryResultRow.ps1',
        'src\ps1\ConvertTo-ServiceInventoryServiceCsvRow.ps1',
        'src\ps1\Get-ServiceInventory.ps1',
        'src\ps1\Get-ServiceInventoryHostComputerId.ps1',
        'src\ps1\Get-ServiceInventorySafeProperty.ps1',
        'src\ps1\Get-ServiceInventoryWorker.ps1',
        'src\ps1\Initialize-ServiceInventoryRunFolder.ps1',
        'src\ps1\Invoke-ServiceInventoryLocal.ps1',
        'src\ps1\Invoke-ServiceInventoryRemote.ps1',
        'src\ps1\Resolve-ServiceInventoryComputerList.ps1',
        'src\ps1\Resolve-ServiceInventoryRemoteErrorName.ps1',
        'src\ps1\Resolve-ServiceInventoryUniqueFolder.ps1',
        'src\ps1\Test-ServiceInventoryLocalName.ps1',
        'src\ps1\Write-ServiceInventoryCsvFile.ps1',
        'src\ps1\Write-ServiceInventoryTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Security', 'Services', 'ServiceAccounts', 'WinRM')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteBaseline'
            ReleaseNotes = 'RemoteService 1.7.0. Csv guard: a text cell that starts with =, +, - or @ is written with one apostrophe in front in every csv file, so a spreadsheet shows it as text and does not run it as a formula. The json files are not changed and hold the exact value. The test suite runs from any folder, also one with square brackets in its name. Application package SIDs and capability SIDs are no longer rows in accounts.json and accounts.csv. They are classed from the SID text without an account lookup and written to appcontainers.json and appcontainers.csv beside them, and summary.json and system.json gain AppContainerCount. Output convention 1.5 (run.json SchemaVersion 1.5). RemoteService 1.6.0. Each service in services.json gains DependOnService, DependOnGroup, DependentServices, ServiceDll and ServiceDllPath after its existing properties, and services.csv gains the columns ServiceDll and ServiceDllPath. DependOnService and DependOnGroup are read from the service key in the registry, DependentServices is worked out from the services of the same computer, and a per-user instance reads its values from the template key. Every ServiceDll file is identified like a service executable, appears in binaries.* and counts in BinaryCount, and a missing one counts in BinaryMissingCount and makes the row Partial. A binary path that is not a file on a local fixed disk is listed and counted as missing and is not opened. summary.json and system.json gain ServiceDllCount and RegistryDurationMs. The output convention stays at 1.4. RemoteService 1.5.0. Json is the default output: services, accounts and binaries are written as json files, and the new -OutputFormat parameter (Json, Csv or Both) selects the json files, the csv files or both. results.csv is written only with Csv or Both, and run.json always holds the results. -OutputPath is optional and defaults to the current file-system location. No warning on PowerShell 7.7, where ConvertTo-Csv -NoTypeInformation is obsolete. The run folder is removed again when the output path is not writable. Output convention 1.4 (run.json gains OutputFormat after SkipSidReference, SchemaVersion 1.4). RemoteService 1.4.0. New -SkipSidReference switch. system.json gains MachineSid, DomainSid, ComputerAccountSid and DomainNetbiosName after MachineGuid, read on each target from the local account with RID 500 and from the computer''s own domain account, and run.json gains SkipSidReference after UseSSL. Output convention 1.3 (run.json SchemaVersion 1.3). RemoteService 1.3.0. Unelevated runs report the shortfall and come back Partial (RemoteScheduledTask, RemoteService). Every error message and csv cell is one line. The per-computer folder name is sanitised. The result callback never ends the run. The loader is hardened against wildcard paths. The Win32_Service read failure carries a services: prefix, the sc path test reports its own failures, properties are read directly and there is one column list per csv file. README gains Known limits, Automation, File formats, Support and versioning and workgroup prerequisites. New SECURITY.md. Examples anonymised. Output convention 1.2. RemoteService 1.2.1. Local aliases in one call get identical rows apart from ComputerName, also when writing a file fails, the csv writer skips null rows, and a binary path with characters that are illegal in a path is reported as not found the same way locally and over WinRM, without an extra error entry on the remote row. The Get-WmiObject fallback is removed and internal code is simplified. No output or data format change. RemoteService 1.2.0. New -UseSSL switch: remote targets are reached over WinRM HTTPS (port 5986) instead of HTTP, and run.json gains UseSSL after ThrottleLimit. The output convention moves to version 1.1 (SchemaVersion 1.1). RemoteService 1.1.1. List[object] construction in the worker uses the typed constructor instead of New-Object. No output or data format change. RemoteService 1.1.0. Adopts the shared output convention for the Remote collectors: run.json, results.csv and system.json carry a computer identity (ComputerId, MachineGuid) and an error count alongside the existing fields, and accounts.json, accounts.csv and summary.json carry the shared both-direction account table (Token, Kind, Sid, Name, Status, ReferenceCount, References) in place of the one-direction StartName table.'
        }
    }
}
