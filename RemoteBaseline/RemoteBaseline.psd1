@{
    RootModule           = 'RemoteBaseline.psm1'
    ModuleVersion        = '1.1.0'
    GUID                 = '709bc392-d3b0-4141-ba62-c4598a7af867'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2026 Tom Stryhn'
    Description          = 'PowerShell Module that bundles the Remote collectors for the Windows Firewall, Group Policy results, scheduled tasks, local security policy and services, runs any combination of them against local and remote computers, and arranges the output per host in one hashed, optionally zipped run folder'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # The five collectors ship inside this module as unchanged copies and load as nested modules, so they resolve to the bundled version whatever the caller has installed. Only Get-RemoteBaseline is exported.
    NestedModules = @(
        'Modules\RemoteFirewall\RemoteFirewall.psd1',
        'Modules\RemoteRSOP\RemoteRSOP.psd1',
        'Modules\RemoteScheduledTask\RemoteScheduledTask.psd1',
        'Modules\RemoteSecEdit\RemoteSecEdit.psd1',
        'Modules\RemoteService\RemoteService.psd1'
    )

    FunctionsToExport = @('Get-RemoteBaseline')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteBaseline.psd1',
        'RemoteBaseline.psm1',
        'LICENSE',
        'Modules\RemoteFirewall\LICENSE',
        'Modules\RemoteFirewall\RemoteFirewall.psd1',
        'Modules\RemoteFirewall\RemoteFirewall.psm1',
        'Modules\RemoteFirewall\src\ps1\Complete-FirewallInventoryComputer.ps1',
        'Modules\RemoteFirewall\src\ps1\ConvertTo-FirewallInventoryResultRow.ps1',
        'Modules\RemoteFirewall\src\ps1\ConvertTo-FirewallInventoryRuleCsvRow.ps1',
        'Modules\RemoteFirewall\src\ps1\Get-FirewallInventory.ps1',
        'Modules\RemoteFirewall\src\ps1\Get-FirewallInventoryHostComputerId.ps1',
        'Modules\RemoteFirewall\src\ps1\Get-FirewallInventorySafeProperty.ps1',
        'Modules\RemoteFirewall\src\ps1\Get-FirewallInventoryWorker.ps1',
        'Modules\RemoteFirewall\src\ps1\Initialize-FirewallInventoryRunFolder.ps1',
        'Modules\RemoteFirewall\src\ps1\Invoke-FirewallInventoryLocal.ps1',
        'Modules\RemoteFirewall\src\ps1\Invoke-FirewallInventoryRemote.ps1',
        'Modules\RemoteFirewall\src\ps1\Resolve-FirewallInventoryComputerList.ps1',
        'Modules\RemoteFirewall\src\ps1\Resolve-FirewallInventoryRemoteErrorName.ps1',
        'Modules\RemoteFirewall\src\ps1\Resolve-FirewallInventoryUniqueFolder.ps1',
        'Modules\RemoteFirewall\src\ps1\Test-FirewallInventoryLocalName.ps1',
        'Modules\RemoteFirewall\src\ps1\Write-FirewallInventoryCsvFile.ps1',
        'Modules\RemoteFirewall\src\ps1\Write-FirewallInventoryTextFile.ps1',
        'Modules\RemoteRSOP\LICENSE',
        'Modules\RemoteRSOP\RemoteRSOP.psd1',
        'Modules\RemoteRSOP\RemoteRSOP.psm1',
        'Modules\RemoteRSOP\src\ps1\Complete-RsopInventoryComputer.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertFrom-RsopInventoryRegistryValue.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertTo-RsopInventoryExtensionRow.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertTo-RsopInventoryGpoId.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertTo-RsopInventoryGpoRow.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertTo-RsopInventoryLinkRow.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertTo-RsopInventoryResultRow.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertTo-RsopInventorySettingCsvRow.ps1',
        'Modules\RemoteRSOP\src\ps1\ConvertTo-RsopInventorySettingRow.ps1',
        'Modules\RemoteRSOP\src\ps1\Get-RsopInventory.ps1',
        'Modules\RemoteRSOP\src\ps1\Get-RsopInventoryHostComputerId.ps1',
        'Modules\RemoteRSOP\src\ps1\Get-RsopInventorySafeProperty.ps1',
        'Modules\RemoteRSOP\src\ps1\Get-RsopInventoryWorker.ps1',
        'Modules\RemoteRSOP\src\ps1\Initialize-RsopInventoryRunFolder.ps1',
        'Modules\RemoteRSOP\src\ps1\Invoke-RsopInventoryLocal.ps1',
        'Modules\RemoteRSOP\src\ps1\Invoke-RsopInventoryRemote.ps1',
        'Modules\RemoteRSOP\src\ps1\Resolve-RsopInventoryComputerList.ps1',
        'Modules\RemoteRSOP\src\ps1\Resolve-RsopInventoryRemoteErrorName.ps1',
        'Modules\RemoteRSOP\src\ps1\Resolve-RsopInventoryUniqueFolder.ps1',
        'Modules\RemoteRSOP\src\ps1\Test-RsopInventoryLocalName.ps1',
        'Modules\RemoteRSOP\src\ps1\Write-RsopInventoryCsvFile.ps1',
        'Modules\RemoteRSOP\src\ps1\Write-RsopInventoryTextFile.ps1',
        'Modules\RemoteScheduledTask\LICENSE',
        'Modules\RemoteScheduledTask\RemoteScheduledTask.psd1',
        'Modules\RemoteScheduledTask\RemoteScheduledTask.psm1',
        'Modules\RemoteScheduledTask\src\ps1\Complete-ScheduledTaskInventoryComputer.ps1',
        'Modules\RemoteScheduledTask\src\ps1\ConvertTo-ScheduledTaskInventoryResultRow.ps1',
        'Modules\RemoteScheduledTask\src\ps1\ConvertTo-ScheduledTaskInventoryTaskCsvRow.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Get-ScheduledTaskInventory.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Get-ScheduledTaskInventoryHostComputerId.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Get-ScheduledTaskInventorySafeProperty.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Get-ScheduledTaskInventoryWorker.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Initialize-ScheduledTaskInventoryRunFolder.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Invoke-ScheduledTaskInventoryLocal.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Invoke-ScheduledTaskInventoryRemote.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Resolve-ScheduledTaskInventoryComputerList.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Resolve-ScheduledTaskInventoryRemoteErrorName.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Resolve-ScheduledTaskInventoryUniqueFolder.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Test-ScheduledTaskInventoryLocalName.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Write-ScheduledTaskInventoryCsvFile.ps1',
        'Modules\RemoteScheduledTask\src\ps1\Write-ScheduledTaskInventoryTextFile.ps1',
        'Modules\RemoteSecEdit\LICENSE',
        'Modules\RemoteSecEdit\RemoteSecEdit.psd1',
        'Modules\RemoteSecEdit\RemoteSecEdit.psm1',
        'Modules\RemoteSecEdit\src\ps1\Complete-SecEditComputer.ps1',
        'Modules\RemoteSecEdit\src\ps1\ConvertTo-SecEditResultRow.ps1',
        'Modules\RemoteSecEdit\src\ps1\Get-SecEditExport.ps1',
        'Modules\RemoteSecEdit\src\ps1\Get-SecEditHostComputerId.ps1',
        'Modules\RemoteSecEdit\src\ps1\Get-SecEditSafeProperty.ps1',
        'Modules\RemoteSecEdit\src\ps1\Get-SecEditWorker.ps1',
        'Modules\RemoteSecEdit\src\ps1\Initialize-SecEditRunFolder.ps1',
        'Modules\RemoteSecEdit\src\ps1\Invoke-SecEditLocal.ps1',
        'Modules\RemoteSecEdit\src\ps1\Invoke-SecEditRemote.ps1',
        'Modules\RemoteSecEdit\src\ps1\Resolve-SecEditComputerList.ps1',
        'Modules\RemoteSecEdit\src\ps1\Resolve-SecEditRemoteErrorName.ps1',
        'Modules\RemoteSecEdit\src\ps1\Resolve-SecEditUniqueFolder.ps1',
        'Modules\RemoteSecEdit\src\ps1\Test-SecEditLocalName.ps1',
        'Modules\RemoteSecEdit\src\ps1\Write-SecEditCsvFile.ps1',
        'Modules\RemoteSecEdit\src\ps1\Write-SecEditTextFile.ps1',
        'Modules\RemoteService\LICENSE',
        'Modules\RemoteService\RemoteService.psd1',
        'Modules\RemoteService\RemoteService.psm1',
        'Modules\RemoteService\src\ps1\Complete-ServiceInventoryComputer.ps1',
        'Modules\RemoteService\src\ps1\ConvertTo-ServiceInventoryResultRow.ps1',
        'Modules\RemoteService\src\ps1\ConvertTo-ServiceInventoryServiceCsvRow.ps1',
        'Modules\RemoteService\src\ps1\Get-ServiceInventory.ps1',
        'Modules\RemoteService\src\ps1\Get-ServiceInventoryHostComputerId.ps1',
        'Modules\RemoteService\src\ps1\Get-ServiceInventorySafeProperty.ps1',
        'Modules\RemoteService\src\ps1\Get-ServiceInventoryWorker.ps1',
        'Modules\RemoteService\src\ps1\Initialize-ServiceInventoryRunFolder.ps1',
        'Modules\RemoteService\src\ps1\Invoke-ServiceInventoryLocal.ps1',
        'Modules\RemoteService\src\ps1\Invoke-ServiceInventoryRemote.ps1',
        'Modules\RemoteService\src\ps1\Resolve-ServiceInventoryComputerList.ps1',
        'Modules\RemoteService\src\ps1\Resolve-ServiceInventoryRemoteErrorName.ps1',
        'Modules\RemoteService\src\ps1\Resolve-ServiceInventoryUniqueFolder.ps1',
        'Modules\RemoteService\src\ps1\Test-ServiceInventoryLocalName.ps1',
        'Modules\RemoteService\src\ps1\Write-ServiceInventoryCsvFile.ps1',
        'Modules\RemoteService\src\ps1\Write-ServiceInventoryTextFile.ps1',
        'Modules\bundle.json',
        'src\ps1\Compress-RemoteBaselineRunFolder.ps1',
        'src\ps1\ConvertTo-RemoteBaselineOneLine.ps1',
        'src\ps1\ConvertTo-RemoteBaselineResultRow.ps1',
        'src\ps1\Get-RemoteBaseline.ps1',
        'src\ps1\Get-RemoteBaselineCollectorCommand.ps1',
        'src\ps1\Get-RemoteBaselineCollectorInfo.ps1',
        'src\ps1\Get-RemoteBaselineHostIdentity.ps1',
        'src\ps1\Get-RemoteBaselineSafeProperty.ps1',
        'src\ps1\Initialize-RemoteBaselineRunFolder.ps1',
        'src\ps1\Invoke-RemoteBaselineCollector.ps1',
        'src\ps1\Move-RemoteBaselineComputerFolder.ps1',
        'src\ps1\Read-RemoteBaselineHostSystem.ps1',
        'src\ps1\Resolve-RemoteBaselineComputerList.ps1',
        'src\ps1\Resolve-RemoteBaselineUniqueFolder.ps1',
        'src\ps1\Test-RemoteBaselineChildPath.ps1',
        'src\ps1\Test-RemoteBaselineDesktopEdition.ps1',
        'src\ps1\Write-RemoteBaselineCsvFile.ps1',
        'src\ps1\Write-RemoteBaselineHostFile.ps1',
        'src\ps1\Write-RemoteBaselineManifest.ps1',
        'src\ps1\Write-RemoteBaselineTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Security', 'Baseline', 'Inventory', 'Firewall', 'GroupPolicy', 'RSOP', 'ScheduledTask', 'SecEdit', 'Service', 'WinRM')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteBaseline'
            ReleaseNotes = '1.1.0: the SID reference (MachineSid, DomainSid, ComputerAccountSid, DomainNetbiosName) is read once per host and run by the first selected collector, every later collector is called with -SkipSidReference, and host.json carries the four values after MachineGuid; the values appear with RemoteRSOP 1.3.0, RemoteScheduledTask 1.4.1, RemoteSecEdit 1.6.0, RemoteService 1.4.0 and RemoteFirewall 1.3.0, and a bundled collector without the switch is called without it; output convention 1.3 (run.json SchemaVersion 1.3). 1.0.0: first release. One function, Get-RemoteBaseline, runs any combination of five bundled collectors (Firewall, RSOP, ScheduledTask, SecEdit, Service) against local and remote computers and arranges their output per host, with run.json, results.csv, a SHA-256 manifest and an optional zip. Bundled collectors, unchanged: RemoteFirewall 1.2.0, RemoteRSOP 1.2.0, RemoteScheduledTask 1.3.0, RemoteSecEdit 1.5.0, RemoteService 1.3.0. Output convention 1.2.'
        }
    }
}
