@{
    RootModule           = 'RemoteSystem.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '0b835ff9-4784-4414-9209-8598772012de'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2026 Tom Stryhn'
    Description          = 'PowerShell Module to collect the description of a Windows computer, its firmware and security state, domain membership with its SIDs, processors, memory, disks, volumes, network adapters, installed updates and Windows features from local and remote computers'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Get-SystemInventory')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteSystem.psd1',
        'RemoteSystem.psm1',
        'LICENSE',
        'src\ps1\Complete-SystemInventoryComputer.ps1',
        'src\ps1\ConvertTo-SystemInventoryCsvRow.ps1',
        'src\ps1\ConvertTo-SystemInventoryResultRow.ps1',
        'src\ps1\Get-SystemInventory.ps1',
        'src\ps1\Get-SystemInventoryHostComputerId.ps1',
        'src\ps1\Get-SystemInventorySafeProperty.ps1',
        'src\ps1\Get-SystemInventoryWorker.ps1',
        'src\ps1\Initialize-SystemInventoryRunFolder.ps1',
        'src\ps1\Invoke-SystemInventoryLocal.ps1',
        'src\ps1\Invoke-SystemInventoryRemote.ps1',
        'src\ps1\Resolve-SystemInventoryComputerList.ps1',
        'src\ps1\Resolve-SystemInventoryRemoteErrorName.ps1',
        'src\ps1\Resolve-SystemInventoryUniqueFolder.ps1',
        'src\ps1\Test-SystemInventoryLocalName.ps1',
        'src\ps1\Write-SystemInventoryCsvFile.ps1',
        'src\ps1\Write-SystemInventoryTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Inventory', 'Hardware', 'Firmware', 'SecureBoot', 'WinRM')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteBaseline'
            ReleaseNotes = 'RemoteSystem 1.0.0. First release. Get-SystemInventory collects the computer system, operating system, firmware and security state, domain membership with its SIDs, processors, memory modules, disks, volumes, network adapters, installed updates and Windows features from local and remote computers, and writes computer.json and one table per class as json, csv or both in output convention 1.5. Windows features are read from Win32_OptionalFeature and from DISM, and each feature carries both states. The DISM read needs elevation and makes Windows append to its own dism.log on the target, and -SkipDismFeatures leaves it out. The accounts that installed an update are in accounts.json, and application package SIDs and capability SIDs among them are in appcontainers.json.'
        }
    }
}
