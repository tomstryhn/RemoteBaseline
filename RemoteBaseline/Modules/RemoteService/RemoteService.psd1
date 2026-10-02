@{
    RootModule           = 'RemoteService.psm1'
    ModuleVersion        = '1.4.0'
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
            ProjectUri   = 'https://github.com/tomstryhn/RemoteService'
            ReleaseNotes = '1.4.0: new -SkipSidReference switch; system.json gains MachineSid, DomainSid, ComputerAccountSid and DomainNetbiosName after MachineGuid, read on each target from the local account with RID 500 and from the computer''s own domain account, and run.json gains SkipSidReference after UseSSL; output convention 1.3 (run.json SchemaVersion 1.3). RemoteService 1.3.0: unelevated runs report the shortfall and come back Partial (RemoteScheduledTask, RemoteService); every error message and csv cell is one line; the per-computer folder name is sanitised; the result callback never ends the run; loader hardened against wildcard paths; the Win32_Service read failure carries a services: prefix, the sc path test reports its own failures, direct property reads, one column list per csv file; README Known limits, Automation, File formats, Support and versioning, workgroup prerequisites; SECURITY.md; examples anonymised; output convention 1.2. RemoteService 1.2.1. Local aliases in one call get identical rows apart from ComputerName, also when writing a file fails, the csv writer skips null rows, and a binary path with characters that are illegal in a path is reported as not found the same way locally and over WinRM, without an extra error entry on the remote row. The Get-WmiObject fallback is removed and internal code is simplified. No output or data format change. RemoteService 1.2.0. New -UseSSL switch: remote targets are reached over WinRM HTTPS (port 5986) instead of HTTP, and run.json gains UseSSL after ThrottleLimit; the output convention moves to version 1.1 (SchemaVersion 1.1). RemoteService 1.1.1. List[object] construction in the worker uses the typed constructor instead of New-Object. No output or data format change. RemoteService 1.1.0. Adopts the shared output convention for the Remote collectors: run.json, results.csv and system.json carry a computer identity (ComputerId, MachineGuid) and an error count alongside the existing fields, and accounts.json, accounts.csv and summary.json carry the shared both-direction account table (Token, Kind, Sid, Name, Status, ReferenceCount, References) in place of the one-direction StartName table.'
        }
    }
}
