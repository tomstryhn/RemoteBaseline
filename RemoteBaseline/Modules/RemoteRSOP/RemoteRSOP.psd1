@{
    RootModule           = 'RemoteRSOP.psm1'
    ModuleVersion        = '1.3.0'
    GUID                 = 'd02db818-9b35-4a44-996a-605573b88853'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2026 Tom Stryhn'
    Description          = 'PowerShell Module to collect the Resultant Set of Policy data from the RSOP WMI namespaces of local and remote computers'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Get-RsopInventory')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteRSOP.psd1',
        'RemoteRSOP.psm1',
        'LICENSE',
        'src\ps1\Complete-RsopInventoryComputer.ps1',
        'src\ps1\ConvertFrom-RsopInventoryRegistryValue.ps1',
        'src\ps1\ConvertTo-RsopInventoryExtensionRow.ps1',
        'src\ps1\ConvertTo-RsopInventoryGpoId.ps1',
        'src\ps1\ConvertTo-RsopInventoryGpoRow.ps1',
        'src\ps1\ConvertTo-RsopInventoryLinkRow.ps1',
        'src\ps1\ConvertTo-RsopInventoryResultRow.ps1',
        'src\ps1\ConvertTo-RsopInventorySettingCsvRow.ps1',
        'src\ps1\ConvertTo-RsopInventorySettingRow.ps1',
        'src\ps1\Get-RsopInventory.ps1',
        'src\ps1\Get-RsopInventoryHostComputerId.ps1',
        'src\ps1\Get-RsopInventorySafeProperty.ps1',
        'src\ps1\Get-RsopInventoryWorker.ps1',
        'src\ps1\Initialize-RsopInventoryRunFolder.ps1',
        'src\ps1\Invoke-RsopInventoryLocal.ps1',
        'src\ps1\Invoke-RsopInventoryRemote.ps1',
        'src\ps1\Resolve-RsopInventoryComputerList.ps1',
        'src\ps1\Resolve-RsopInventoryRemoteErrorName.ps1',
        'src\ps1\Resolve-RsopInventoryUniqueFolder.ps1',
        'src\ps1\Test-RsopInventoryLocalName.ps1',
        'src\ps1\Write-RsopInventoryCsvFile.ps1',
        'src\ps1\Write-RsopInventoryTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Security', 'GroupPolicy', 'RSOP', 'Compliance')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteRSOP'
            ReleaseNotes = '1.3.0: the SID reference is read on each target and written to system.json (MachineSid, DomainSid, ComputerAccountSid, DomainNetbiosName after MachineGuid), new -SkipSidReference switch for a caller that needs it from one collector only, run.json gains SkipSidReference after UseSSL; output convention 1.3 (run.json SchemaVersion 1.3). 1.2.0: unelevated runs report the shortfall and come back Partial (RemoteScheduledTask, RemoteService); every error message and csv cell is one line; the per-computer folder name is sanitised; the result callback never ends the run; loader hardened against wildcard paths; user namespace path joined as a string, system.json written from a name list, late host errors recomputed once per computer, Status and denied-worker tests; README Known limits, Automation, File formats, Support and versioning, workgroup prerequisites; SECURITY.md; examples anonymised; output convention 1.2. RemoteRSOP 1.1.1. A worker result carrying an empty entry in its error list no longer ends the run, local aliases in one call get identical rows apart from ComputerName, and remote results are completed and written as each target answers. The Get-WmiObject fallback is removed and internal code is simplified. No output or data format change. RemoteRSOP 1.1.0. New -UseSSL switch: remote targets are reached over WinRM HTTPS (port 5986) instead of HTTP, and run.json gains UseSSL after ThrottleLimit; the output convention moves to version 1.1 (SchemaVersion 1.1). RemoteRSOP 1.0.1. The Version column of the GPO table is Int64 so that a GPO denied by security filtering (RSOP_GPO.version 0xFFFF0001) no longer fails the run. 1.0.0: first release. Collects the populated classes of root\RSOP\Computer and every root\RSOP\User\<SID> namespace, flattens the setting classes into one settings table, and writes the applied GPOs, links, extension status and referenced accounts in the shared Remote collector layout.'
        }
    }
}
