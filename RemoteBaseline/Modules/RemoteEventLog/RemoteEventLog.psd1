@{
    RootModule           = 'RemoteEventLog.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '6c2e9b14-83d7-4f5a-b0e1-a7d4c31f9528'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2026 Tom Stryhn'
    Description          = 'PowerShell Module to collect every Windows event log with its configuration, size, time frame, policy values, archive files and security descriptor from local and remote computers'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Get-EventLogInventory')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteEventLog.psd1',
        'RemoteEventLog.psm1',
        'LICENSE',
        'src\ps1\Complete-EventLogInventoryComputer.ps1',
        'src\ps1\ConvertTo-EventLogInventoryLogCsvRow.ps1',
        'src\ps1\ConvertTo-EventLogInventoryResultRow.ps1',
        'src\ps1\Get-EventLogInventory.ps1',
        'src\ps1\Get-EventLogInventoryHostComputerId.ps1',
        'src\ps1\Get-EventLogInventorySafeProperty.ps1',
        'src\ps1\Get-EventLogInventoryWorker.ps1',
        'src\ps1\Initialize-EventLogInventoryRunFolder.ps1',
        'src\ps1\Invoke-EventLogInventoryLocal.ps1',
        'src\ps1\Invoke-EventLogInventoryRemote.ps1',
        'src\ps1\Resolve-EventLogInventoryComputerList.ps1',
        'src\ps1\Resolve-EventLogInventoryRemoteErrorName.ps1',
        'src\ps1\Resolve-EventLogInventoryUniqueFolder.ps1',
        'src\ps1\Test-EventLogInventoryLocalName.ps1',
        'src\ps1\Write-EventLogInventoryCsvFile.ps1',
        'src\ps1\Write-EventLogInventoryTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Security', 'EventLog', 'Logging', 'WinRM')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteBaseline'
            ReleaseNotes = 'RemoteEventLog 1.0.0. First release: collects every event log, the Analytical and Debug logs included, with its configuration, file size and record count, the id and time of its oldest and newest record, the Group Policy values set for it, its archive files and the security identifiers in its security descriptor, from local and remote computers. Writes logs.json, accounts.json, appcontainers.json, summary.json and system.json per computer in the output convention 1.5, with -OutputFormat Json, Csv or Both. Application package SIDs and capability SIDs a descriptor names are in appcontainers.json, and accounts.json holds accounts only. No event content is read.'
        }
    }
}
