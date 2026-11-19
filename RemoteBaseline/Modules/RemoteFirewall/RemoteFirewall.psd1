@{
    RootModule           = 'RemoteFirewall.psm1'
    ModuleVersion        = '1.5.0'
    GUID                 = '4d0cf6bd-bc17-45ea-9056-9159d2a60290'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2026 Tom Stryhn'
    Description          = 'PowerShell Module to collect the Windows Firewall profile settings, global settings and every firewall rule with its filters and the security principals it names from local and remote computers'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Get-FirewallInventory')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteFirewall.psd1',
        'RemoteFirewall.psm1',
        'LICENSE',
        'src\ps1\Complete-FirewallInventoryComputer.ps1',
        'src\ps1\ConvertTo-FirewallInventoryResultRow.ps1',
        'src\ps1\ConvertTo-FirewallInventoryRuleCsvRow.ps1',
        'src\ps1\Get-FirewallInventory.ps1',
        'src\ps1\Get-FirewallInventoryHostComputerId.ps1',
        'src\ps1\Get-FirewallInventorySafeProperty.ps1',
        'src\ps1\Get-FirewallInventoryWorker.ps1',
        'src\ps1\Initialize-FirewallInventoryRunFolder.ps1',
        'src\ps1\Invoke-FirewallInventoryLocal.ps1',
        'src\ps1\Invoke-FirewallInventoryRemote.ps1',
        'src\ps1\Resolve-FirewallInventoryComputerList.ps1',
        'src\ps1\Resolve-FirewallInventoryRemoteErrorName.ps1',
        'src\ps1\Resolve-FirewallInventoryUniqueFolder.ps1',
        'src\ps1\Test-FirewallInventoryLocalName.ps1',
        'src\ps1\Write-FirewallInventoryCsvFile.ps1',
        'src\ps1\Write-FirewallInventoryTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Security', 'Firewall', 'WindowsFirewall', 'FirewallRules', 'WinRM')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteBaseline'
            ReleaseNotes = 'RemoteFirewall 1.5.0. Csv guard: a text cell that starts with =, +, - or @ is written with one apostrophe in front in every csv file, so a spreadsheet shows it as text and does not run it as a formula. The json files are not changed and hold the exact value. The test suite runs from any folder, also one with square brackets in its name. Application package SIDs and capability SIDs are no longer rows in accounts.json and accounts.csv. They are classed from the SID text without an account lookup and written to appcontainers.json and appcontainers.csv beside them, and summary.json and system.json gain AppContainerCount. The package family names of installed packages are in the new files, and summary.json gains AppContainerUnnamedCount after PackageCount. Output convention 1.5 (run.json SchemaVersion 1.5). RemoteFirewall 1.4.0. Json is the default output: profiles, rules and accounts are written as json files, and the new -OutputFormat parameter (Json, Csv or Both) selects the json files, the csv files or both. results.csv is written only with Csv or Both, and run.json always holds the results. -OutputPath is optional and defaults to the current file-system location. No warning on PowerShell 7.7, where ConvertTo-Csv -NoTypeInformation is obsolete. The run folder is removed again when the output path is not writable. Output convention 1.4 (run.json gains OutputFormat after SkipSidReference, SchemaVersion 1.4). RemoteFirewall 1.3.0. The SID reference (MachineSid, DomainSid, ComputerAccountSid and DomainNetbiosName) is read on each target and written to system.json, and the new -SkipSidReference switch leaves it unread. Output convention 1.3 (run.json SchemaVersion 1.3). RemoteFirewall 1.2.0. Unelevated runs report the shortfall and come back Partial (RemoteScheduledTask, RemoteService). Every error message and csv cell is one line. The per-computer folder name is sanitised. The result callback never ends the run. The loader is hardened against wildcard paths. The unused account lookup dictionary is removed and account reference lists are sorted in place. README gains Known limits, Automation, File formats, Support and versioning and workgroup prerequisites. New SECURITY.md. Examples anonymised. Output convention 1.2. RemoteFirewall 1.1.0. Application package SIDs are resolved to package family names on the target (Get-AppxPackage -AllUsers, hashed the way Windows derives the SID), and summary.json and system.json gain PackageCount and PackagesDurationMs. RemoteFirewall 1.0.0. First release: collects the three firewall profiles, the global settings and every firewall rule with its seven filters, and the security principals the rules name, from local and remote computers in the output convention of the Remote collectors.'
        }
    }
}
