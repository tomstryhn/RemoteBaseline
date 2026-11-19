@{
    RootModule           = 'RemoteSecEdit.psm1'
    ModuleVersion        = '1.8.0'
    GUID                 = '69e5a969-ad16-4a08-bcae-e57bbfcf6349'
    Author               = 'Tom Stryhn'
    CompanyName          = 'Tom Stryhn'
    Copyright            = 'Copyright (c) 2021-2026 Tom Stryhn'
    Description          = 'PowerShell Module to collect the raw secedit /export output, plain and mergedpolicy, from local and remote computers'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @('Get-SecEditExport')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @(
        'RemoteSecEdit.psd1',
        'RemoteSecEdit.psm1',
        'LICENSE',
        'src\ps1\Complete-SecEditComputer.ps1',
        'src\ps1\ConvertTo-SecEditResultRow.ps1',
        'src\ps1\Get-SecEditExport.ps1',
        'src\ps1\Get-SecEditHostComputerId.ps1',
        'src\ps1\Get-SecEditSafeProperty.ps1',
        'src\ps1\Get-SecEditWorker.ps1',
        'src\ps1\Initialize-SecEditRunFolder.ps1',
        'src\ps1\Invoke-SecEditLocal.ps1',
        'src\ps1\Invoke-SecEditRemote.ps1',
        'src\ps1\Resolve-SecEditComputerList.ps1',
        'src\ps1\Resolve-SecEditRemoteErrorName.ps1',
        'src\ps1\Resolve-SecEditUniqueFolder.ps1',
        'src\ps1\Test-SecEditLocalName.ps1',
        'src\ps1\Write-SecEditCsvFile.ps1',
        'src\ps1\Write-SecEditTextFile.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('PSEdition_Desktop', 'PSEdition_Core', 'Windows', 'Security', 'SecEdit', 'SecurityPolicy', 'GroupPolicy')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/tomstryhn/RemoteBaseline'
            ReleaseNotes = 'RemoteSecEdit 1.8.0. Csv guard: a text cell that starts with =, +, - or @ is written with one apostrophe in front in every csv file, so a spreadsheet shows it as text and does not run it as a formula. The json files are not changed and hold the exact value. The test suite runs from any folder, also one with square brackets in its name. Application package SIDs and capability SIDs are no longer rows in accounts.json and accounts.csv. They are classed from the SID text without an account lookup and written to appcontainers.json and appcontainers.csv beside them, and summary.json and system.json gain AppContainerCount. Output convention 1.5 (run.json SchemaVersion 1.5). RemoteSecEdit 1.7.0. Json is the default output: accounts are written as accounts.json, and the new -OutputFormat parameter (Json, Csv or Both) selects the json file, the csv file or both. results.csv is written only with Csv or Both, and run.json always holds the results. The raw export files, system.json and summary.json are written in every format. -OutputPath is optional and defaults to the current file-system location. No warning on PowerShell 7.7, where ConvertTo-Csv -NoTypeInformation is obsolete. The run folder is removed again when the output path is not writable. Output convention 1.4 (run.json gains OutputFormat after SkipSidReference, SchemaVersion 1.4). RemoteSecEdit 1.6.0. The SID reference (MachineSid, DomainSid, ComputerAccountSid, DomainNetbiosName) is read on each target and written to system.json, a new -SkipSidReference switch leaves it unread, and run.json gains SkipSidReference after UseSSL. Output convention 1.3 (run.json SchemaVersion 1.3). RemoteSecEdit 1.5.0. Unelevated runs report the shortfall and come back Partial (RemoteScheduledTask, RemoteService). Every error message and csv cell is one line. The per-computer folder name (reported name and build number) is sanitised. The result callback never ends the run. The loader is hardened against wildcard paths. The worker work folder is removed in a finally block, SHA-256 goes through Get-FileHash (Get-SecEditSha256Hex removed) and the secedit path test reports its own failures. README gains Known limits, Automation, File formats, Support and versioning and workgroup prerequisites. New SECURITY.md. Examples anonymised. Output convention 1.2 (run.json SchemaVersion 1.2). RemoteSecEdit 1.4.1. A worker result carrying an empty entry in its error list no longer ends the run, local aliases in one call get identical rows apart from ComputerName, remote results are completed and written as each target answers, and system.json is built from a fixed property list. The Get-WmiObject fallback is removed and internal code is simplified. No output or data format change. RemoteSecEdit 1.4.0. New -UseSSL switch: remote targets are reached over WinRM HTTPS (port 5986) instead of HTTP, and run.json gains UseSSL after ThrottleLimit. The output convention moves to version 1.1 (SchemaVersion 1.1). RemoteSecEdit 1.3.1. Comments in published files no longer point at working documents that are not part of the repository, and the rules they cited are stated in place. No behaviour, output or data format change. RemoteSecEdit 1.3.0. Output now follows the shared layout used by RemoteService and RemoteScheduledTask: ComputerId and MachineGuid identify every computer independently of its name, run.json and system.json carry Collector, CollectorVersion, SchemaVersion and RunId, summary.json is one object with an Exports array instead of a bare array of two, and every row gains ErrorCount. accounts.csv and the account table rename SettingCount to ReferenceCount and Settings to References. RemoteSecEdit 1.2.0. Resolves every account referenced in the user rights of both exports on the target, in both directions, and writes accounts.json and accounts.csv per computer. Every csv file now carries a UTF-8 byte order mark on both engines. RemoteSecEdit 1.1.0. Renamed from Get-UserRightsAssignments (October 2021), a single script that collected the user rights assignments through secedit over Invoke-Command without error handling and with a CSV per computer as its only output. This version collects the full secedit export in both modes, the identity of each computer and every error, and writes the raw files for a separate analysis.'
        }
    }
}
