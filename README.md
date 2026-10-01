# RemoteBaseline PowerShell Module

Collects the Windows Firewall, the Group Policy results, the scheduled tasks, the local security policy and the services of local and remote Windows computers in one call, with five collectors that ship inside the module, and arranges what it collects per host in one hashed, optionally zipped run folder, without interpreting anything.

## Table of Content

- [Version Changes](#version-changes)
- [Background](#background)
  - [Risk(s)](#risks)
  - [Mitigation](#mitigation)
  - [Bundled collectors](#bundled-collectors)
- [Requirements](#requirements)
- [Output Data Handling](#output-data-handling)
- [Importing the Module](#importing-the-module)
- [Examples](#examples)
- [Functions](#functions)
  - [Get-RemoteBaseline](#get-remotebaseline)
- [How it works](#how-it-works)
  - [What to send back](#what-to-send-back)
- [Testing](#testing)
- [Support and versioning](#support-and-versioning)
- [References](#references)
- [License](#license)

## Version Changes

##### 1.0.0

- First release. One function, `Get-RemoteBaseline`, runs any combination of five collectors against local and remote computers and arranges their output per host.
- The five collectors are bundled, unchanged, as nested modules: RemoteFirewall 1.2.0, RemoteRSOP 1.2.0, RemoteScheduledTask 1.3.0, RemoteSecEdit 1.5.0 and RemoteService 1.3.0. They load inside this module at exactly these versions, whatever the collecting computer has installed, and nothing else needs to be installed on the collecting computer or on the targets. `Modules\bundle.json` records the SHA-256 of every bundled file, and a test proves the bundle matches it.
- Takes the family's parameters (`-ComputerName`, `-Credential`, `-UseSSL`, `-OutputPath`, `-ThrottleLimit`), forwards them unchanged to every collector, and adds `-Type` (Firewall, RSOP, ScheduledTask, SecEdit, Service; default all five) and `-Compress`.
- Writes one run folder per call with `run.json`, `results.csv`, `manifest.sha256` (the SHA-256 of every other file in the run folder) and one folder per reached host, named `<REPORTED>_<CurrentBuild>_<stamp>Z`, that holds `host.json` and one subfolder per collector with that collector's computer folder, files intact. The collectors' own `run.json` and `results.csv` are kept under `collectors\<Module>\`.
- Returns one result row per requested name, with a `Status` over all selected collectors and a status and error count column per collector, so one look says which collector was not clean.
- `-Compress` writes the run folder as one zip beside it with forward-slash entry names, which every unzip tool reads as folders (`Compress-Archive` in Windows PowerShell 5.1 writes backslashes). It uses `System.IO.Compression`, so there is no 2 GB limit.
- On Windows PowerShell 5.1 the resolved `-OutputPath` may be at most 105 characters; a longer one gives a `Failed` row that says so before anything is written. PowerShell 7 has no such limit.
- Follows output convention 1.2: `run.json` carries `SchemaVersion` `1.2`.
- Runs on Windows PowerShell 5.1 and PowerShell 7, with a Pester test suite covering both engines.

## Background

A security baseline review needs the same five things from every computer: the Windows Firewall rules, the Group Policy that applied, the scheduled tasks, the local security policy (user rights and the accounts they name) and the services. Each has a collector in the Remote family, and each collector writes its own run folder with one folder per computer.

### Risk(s)

Running five collectors means five modules to install and keep at the same version on the collecting computer, five run folders per call, and a hand-made match of the five computer folders of one host. A set of loose files handed back by a client or a technician cannot be told from a set that was edited, partly copied or mixed with an older run.

### Mitigation

One function runs the collectors you pick, from versions pinned inside the module, and arranges the result per host: one folder per host with a `host.json` and one subfolder per collector, and one result row per requested name. `manifest.sha256` lists the SHA-256 of every file of the run, so the receiver can prove that what arrived is what was collected.

### Bundled collectors

The collectors are not changed: the module holds their released module folders byte for byte, and every bundled file has its hash in `Modules\bundle.json`. Each collector's own README describes its subject files and its verification.

| Module | Version | What it collects | Repository |
|---|---|---|---|
| RemoteFirewall | 1.2.0 | The three firewall profiles, the global settings, every firewall rule with its seven filters, and the security principals the rules name | https://github.com/tomstryhn/RemoteFirewall |
| RemoteRSOP | 1.2.0 | The Resultant Set of Policy data Windows keeps in `root\RSOP`, and every account a user right or a restricted group references | https://github.com/tomstryhn/RemoteRSOP |
| RemoteScheduledTask | 1.3.0 | Every scheduled task with its definition, account, security descriptor, run-time state and the identity and signature of each action binary | https://github.com/tomstryhn/RemoteScheduledTask |
| RemoteSecEdit | 1.5.0 | The raw output of `secedit /export`, plain and `/mergedpolicy`, and every account the user rights reference | https://github.com/tomstryhn/RemoteSecEdit |
| RemoteService | 1.3.0 | Every Windows service with its account, security descriptor, and the identity and signature of its binary | https://github.com/tomstryhn/RemoteService |

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on the collecting computer; the targets run Windows PowerShell 5.1.
- Nothing else to install: the five collectors are inside the module. The firewall collector reads through the `NetSecurity` module on the target (it ships with Windows 8 and Server 2012 and later, so this is normally already true).
- The module is read-only on every target: the collectors only read, and `Get-RemoteBaseline` adds no action on a target.

Run elevated for a complete collection. Running without administrative rights has consequences that are captured in the rows rather than hidden, one per collector: RemoteFirewall comes back `Partial` (the address, port, interface and interface type filters and the installed packages cannot be read), RemoteRSOP `Failed` (the RSOP namespaces cannot be read), RemoteScheduledTask `Partial` (tasks the caller cannot open are not listed), RemoteSecEdit `Failed` (`secedit` exits with 740) and RemoteService `Partial` (services and security descriptors the caller cannot open are not listed). The row of the host is `Partial`, its per-type status columns say which collector was not clean, and `IsElevated` says which case a row is in. The Examples section shows such a run.

Hardening baselines can switch remote collection off. The CIS Level 2 benchmarks, for example,
set "Allow remote server management through WinRM" to Disabled, which removes the WinRM
listener on member servers and domain controllers. A remote call to such a computer returns a
`Failed` row with the connection error, and the other computers in the same call are not
affected. Run the command locally on those computers instead, for example through your software
distribution tool or a scheduled task, and collect the output folders afterwards. A local run
never uses WinRM and gives the same output.

Use the fully qualified domain name (FQDN) for remote targets, for example
`SRV010.contoso.com` rather than `SRV010` or an IP address. Kerberos, which WinRM uses by
default in a domain, needs a name it can match to the computer's account, and an IP
address falls back to rules that need TrustedHosts and explicit credentials. With
`-UseSSL` the FQDN is normally required: the collection then connects over WinRM HTTPS
(port 5986), and the name you pass must match the subject or subject alternative name of
the target's listener certificate, which normally carries only the FQDN. A short name or
an IP address then fails with WinRM error 12175, a certificate name mismatch. The target
needs an HTTPS listener and an inbound firewall rule for port 5986, and the collecting
computer must trust the certificate's issuing CA. Certificate checks are never skipped:
the module offers no SkipCACheck or SkipCNCheck option, by design. A target in a workgroup, or addressed by IP, needs the collecting computer to list it in TrustedHosts and, for a local administrator account that is not the built-in Administrator, `LocalAccountTokenFilterPolicy` set to 1 on the target; the module changes neither setting.

Known limits. The collection was verified with a local run on Windows Server 2022, over WinRM HTTP and HTTPS against Windows Server 2016, 2019, 2022 and 2025, and with a local run on Windows 11; the bundled collectors carry their own verification matrix. Windows client editions as remote targets and non-English Windows installations are untested: the code matches no English console text and reads SIDs and numeric codes, so locale risk is low, but it is not proven. The module runs in FullLanguage mode only: under ConstrainedLanguage mode, which an enforced WDAC or AppLocker policy produces, a target's worker fails at its first .NET call and the computer's row comes back `Failed` with that error; no file is left behind. On a collecting computer whose session runs in ConstrainedLanguage mode the call itself throws at its first .NET use before anything is written (the collectors behave the same when run locally there). The module files are not signed, so an AllSigned execution policy or a publisher rule refuses the import (see Importing the Module). A JEA endpoint does not run the worker: the module has no -ConfigurationName. On Windows PowerShell 5.1 the output path must be at most 105 characters, because the staging layout needs about 150 characters below it and 5.1 limits a path to 260; a longer path gives a Failed row that says so before anything is written.

Automation. The functions never throw and the process exit code is 0 even when every row is `Failed`: a wrapper decides on the `Status` column of `results.csv` or the row objects, not on the exit code. No timeout parameter exists; a remote call uses the WinRM defaults (operation timeout 3 minutes). Running twice into the same `-OutputPath` never overwrites: every run gets its own UTC-stamped run folder. A caller's -WarningAction Stop turns a warning into a terminating error; the collectors emit their warnings after the run files are written, so the output on disk is complete in that case too.

## Output Data Handling

The output is a configuration inventory of every computer you collect from. It holds no password, key or password hash that the module reads on purpose, but it names hosts, firewall rules, programs, ports, addresses, accounts, SIDs, scheduled tasks and services, the Group Policy objects that apply and the local security policy: which program may accept connections from where, which account runs which service or task, and which accounts hold which rights. It describes how each computer is exposed and administered in a detail that is useful to an attacker. Treat every output folder, and the zip, as confidential.

Each call writes one run folder under `-OutputPath`, and with `-Compress` a zip of it beside the run folder:

```
C:\BaselineRuns\RemoteBaseline-<yyyyMMdd-HHmmss>Z\
    run.json                           summary of the whole run
    results.csv                        one row per requested name, opens in Excel
    manifest.sha256                    the SHA-256 of every other file in this folder
    collectors\
        RemoteFirewall\                run.json and results.csv of that collector's run
        RemoteRSOP\                    (one folder per selected collector)
        ...
    <REPORTED>_<CurrentBuild>_<stamp>Z\    one folder per reached host, per requested name
        host.json                      identity of the host and the status of each collector
        RemoteFirewall\                the collector's computer folder, files intact
        RemoteRSOP\
        ...
C:\BaselineRuns\RemoteBaseline-<yyyyMMdd-HHmmss>Z.zip      only with -Compress
```

A suffix `_2`, `_3` is added to the run folder name when the name is taken, and to a host folder name when two requested names of one host (a short name and a fully qualified name) map to the same name; names of one local computer (`localhost`, `.` and its own name) share one host folder. A host that no selected collector reached has no host folder and a `Failed` row; a host that only some collectors reached has the subfolders of those collectors. The stamp in a host folder name is the stamp of the run folder; the stamp inside a collector's own folder names is that collector's. The subfolders hold exactly what the collector wrote, and each collector's README lists the files: `rules.csv` and the profile files for the firewall, `gpos.csv` and `settings.csv` for RSOP, `tasks.csv` and `binaries.csv` for the scheduled tasks, the `secedit-export` files for the security policy, `services.csv` and `binaries.csv` for the services, each with `system.json` and `summary.json`.

`host.json` is deliberately not named `system.json`, so a loader that looks for computer folders by `system.json` never mistakes a host folder for one. Its keys, in this order: `ComputerName` (as requested, the first name for aliases), `RequestedNames`, `ComputerId`, `DnsHostName`, `Domain`, `OSCaption`, `OSVersion`, `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID`, `InstallationType`, `Culture`, `TimeZoneId`, `PartOfDomain`, `DomainRole`, `IsElevated` and `MachineGuid` (copied from the first present subfolder's `system.json`, null when absent), `Collector`, `CollectorVersion`, `RunId`, `Types`, `Collectors` (per selected type: `Type`, `Module`, `Version`, `Subfolder`, `Status`, `ErrorCount`, `RunId`), `Status` and `Errors`.

`run.json` is one object, with the keys in this order: `RunId`, `Collector`, `CollectorVersion`, `SchemaVersion`, `HostComputer`, `HostComputerId`, `HostUser`, `PSVersion`, `StartUtc`, `EndUtc`, `RequestedComputers`, `Types`, `ThrottleLimit`, `UseSSL`, `Compress`, `Archive` (the zip name, null without `-Compress`), `Collectors` (per selected type: `Type`, `Module`, `Version`, `RunId`, `DurationMs`, `RowCount`, `SuccessCount`, `PartialCount`, `FailedCount`, `Error`) and `Results`, always an array. The collectors' own `run.json` keeps the `OutputFolder` values of the staging location where the computer folders were before they moved; the `run.json`, `results.csv` and `host.json` of the run folder are the authority for where files are.

The result row, in `run.json` and as the output of the function, has these columns in this order: `ComputerName` (as requested), `ComputerId`, `Status`, `Transport` (`Local` or `WinRM`), `OutputFolder` (the host folder, an empty string when no collector reached the host), `IsElevated`, `Types` (the selected types in run order; a string array in the json files and in the row, one text cell joined with a comma and a space in `results.csv`), `FirewallStatus`, `RSOPStatus`, `ScheduledTaskStatus`, `SecEditStatus`, `ServiceStatus`, `FirewallErrorCount`, `RSOPErrorCount`, `ScheduledTaskErrorCount`, `SecEditErrorCount`, `ServiceErrorCount` (null for a type that was not selected), `Error`, `ErrorCount` and `Errors`. `results.csv` holds every column but `Errors`. `Errors` lists every collector's error lines, each prefixed with its type (`Firewall: ...`), in run order, then the lines of the module itself: `arrange: <Module>: ...` when a folder could not be moved into place, `host.json: ...` when `host.json` could not be written or a `system.json` could not be read. `Error` is the first entry and every entry is one line.

`Status` is `Failed` when every selected collector's row is `Failed` (or the name has none), `Success` when every selected collector's row is `Success` and the module added no line, and `Partial` otherwise. A failure to write `run.json` or `results.csv`, to write the manifest or to write the zip cannot be recorded in the files it concerns, because `run.json` and `results.csv` are inside the manifest and the zip. So the lines `run.json: <message>`, `results.csv: <message>`, `manifest: <message>` and `zip: <message>` exist in the returned rows only, never in a file on disk, and none of them is a warning in the middle of the run; the manifest and the zip are still written over what exists; they make every `Success` row `Partial`, because the deliverable (an intact, hashed, zipped run folder) is incomplete.

Nothing is redacted. The files are written exactly as the collectors write them.

Recommended handling:

- Write the output to a folder that only administrators can read. The module creates its run
  folder under `-OutputPath` and sets no permissions of its own, so the run folder inherits the
  permissions of its parent.
- Move the output only as an encrypted archive or over an encrypted channel, never by
  unencrypted email or an open file share.
- Keep each run folder intact. Its files refer to each other by `RunId` and `ComputerId`, and an
  edited file cannot be told apart from an original one.
- Delete the output when the analysis is finished, following your own retention rules.

The collection writes nothing to the computers it reads. A remote run returns its data over
WinRM, which encrypts the traffic of a Kerberos or NTLM authenticated session even over HTTP,
unless unencrypted traffic has been allowed on the endpoint.

File formats. The csv files are UTF-8 with a byte order mark, every cell quoted, one row per line (whitespace inside a cell is collapsed to one space); the json files are UTF-8 without a byte order mark, and a top-level array is an array at zero and one element too. The csv is for spreadsheets; a loader that needs the source form of a value, or the null against empty-string distinction, reads the json.

`manifest.sha256` has one line per file of the run folder except itself: the SHA-256 in lower-case hexadecimal, two spaces, and the path relative to the run folder with forward slashes, sorted by ordinal comparison, with LF line endings and no byte order mark, so `sha256sum -c manifest.sha256` checks it on Linux and macOS.

## Importing the Module

From a Windows PowerShell 5.1 prompt, on the computer you want to collect from or run the
collection from. The module is not signed, so a copy downloaded or copied from elsewhere needs
unblocking and a process-scoped execution policy relaxed before it will import. This does not
bypass a Group Policy-enforced `AllSigned` execution policy, which overrides the process scope
and still blocks the import:

```powershell
Get-ChildItem C:\Path\To\RemoteBaseline -Recurse | Unblock-File
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module C:\Path\To\RemoteBaseline\RemoteBaseline\RemoteBaseline.psd1
```

## Examples

Collecting everything from the local computer from a session that is not elevated, on a workgroup Windows 11 host, into a zip as well:

```powershell
PS C:\> Get-RemoteBaseline -OutputPath C:\BaselineRuns -Compress | Format-List

ComputerName            : WS01
ComputerId              : 11111111-2222-3333-4444-555555555501
Status                  : Partial
Transport               : Local
OutputFolder            : C:\BaselineRuns\RemoteBaseline-20261001-093321Z\WS01_26300_20261001-093321Z
IsElevated              : False
Types                   : {Firewall, RSOP, ScheduledTask, SecEdit...}
FirewallStatus          : Partial
RSOPStatus              : Failed
ScheduledTaskStatus     : Partial
SecEditStatus           : Failed
ServiceStatus           : Partial
FirewallErrorCount      : 5
RSOPErrorCount          : 2
ScheduledTaskErrorCount : 1
SecEditErrorCount       : 6
ServiceErrorCount       : 5
Error                   : Firewall: filter Address: Access is denied.
ErrorCount              : 19
Errors                  : {Firewall: filter Address: Access is denied., Firewall: filter Port: Access is denied., Firewall: filter Interface: Access is denied., Firewall: filter InterfaceType: Access is denied....}
```

That run took 34 s and wrote a zip of 248146 bytes beside the run folder. One row came back for the one name, `Partial`, and the five per-type columns show which collector was not clean: RemoteRSOP and RemoteSecEdit could not read anything without administrative rights, the other three collected what a standard user can read. The call also wrote one warning, `WS01: Partial, 19 error(s): Firewall: filter Address: Access is denied.`, after the row and after every file was written. The run folder, with the files of each collector left out where the list is long:

```
C:\BaselineRuns\RemoteBaseline-20261001-093321Z\
    run.json                    7770 bytes
    results.csv                 618
    manifest.sha256             7179
    collectors\
        RemoteFirewall\         results.csv, run.json
        RemoteRSOP\             results.csv, run.json
        RemoteScheduledTask\    results.csv, run.json
        RemoteSecEdit\          results.csv, run.json
        RemoteService\          results.csv, run.json
    WS01_26300_20261001-093321Z\
        host.json               5470
        RemoteFirewall\         accounts.csv, accounts.json, globalsettings.json, profiles.csv, profiles.json, rules.csv, rules.json, summary.json, system.json
        RemoteRSOP\             accounts, extensions, gpos, links, settings (.csv and .json), raw.json, summary.json, system.json
        RemoteScheduledTask\    accounts, binaries, tasks (.csv and .json), summary.json, system.json
        RemoteSecEdit\          accounts.csv, accounts.json, the secedit-export and secedit-mergedpolicy logs, summary.json, system.json
        RemoteService\          accounts, binaries, services (.csv and .json), summary.json, system.json
```

The first lines of `host.json` of that run (the `Errors` list is the same 19 lines as in the row):

```json
{
    "ComputerName":  "WS01",
    "RequestedNames":  [
                           "WS01"
                       ],
    "ComputerId":  "11111111-2222-3333-4444-555555555501",
    "DnsHostName":  "ws01",
    "Domain":  "WORKGROUP",
    "OSCaption":  "Microsoft Windows 11 Pro",
    "OSVersion":  "10.0.26300",
    "CurrentBuild":  "26300",
    "UBR":  "9457",
    "DisplayVersion":  "26H2",
    "EditionID":  "Professional",
    "InstallationType":  "Client",
    "Culture":  "en-US",
    "TimeZoneId":  "Romance Standard Time",
    "PartOfDomain":  false,
    "DomainRole":  0,
    "IsElevated":  false,
    "MachineGuid":  "00000000-1111-2222-3333-444444444401",
    "Collector":  "RemoteBaseline",
    "CollectorVersion":  "1.0.0",
    "RunId":  "RemoteBaseline-20261001-093321Z",
    "Types":  [ "Firewall", "RSOP", "ScheduledTask", "SecEdit", "Service" ],
    "Collectors":  [
                       {
                           "Type":  "Firewall",
                           "Module":  "RemoteFirewall",
                           "Version":  "1.2.0",
                           "Subfolder":  "RemoteFirewall",
                           "Status":  "Partial",
                           "ErrorCount":  5,
                           "RunId":  "RemoteFirewall-20261001-093321Z"
                       },
                       ...
```

`results.csv` of that run (the `OutputFolder` cell is the host folder, and every cell is quoted):

```
"ComputerName","ComputerId","Status","Transport","OutputFolder","IsElevated","Types","FirewallStatus","RSOPStatus","ScheduledTaskStatus","SecEditStatus","ServiceStatus","FirewallErrorCount","RSOPErrorCount","ScheduledTaskErrorCount","SecEditErrorCount","ServiceErrorCount","Error","ErrorCount"
"WS01","11111111-2222-3333-4444-555555555501","Partial","Local","C:\BaselineRuns\RemoteBaseline-20261001-093321Z\WS01_26300_20261001-093321Z","False","Firewall, RSOP, ScheduledTask, SecEdit, Service","Partial","Failed","Partial","Failed","Partial","5","2","1","6","5","Firewall: filter Address: Access is denied.","19"
```

The first lines of `manifest.sha256` of that run, which has 61 lines, one per file (the zip holds those 61 files and `manifest.sha256`, 62 entries); the receiver's check is in What to send back:

```
d173844e3d09aac68f7971764565670f6be8708c748d40d44a139174ef2d6099  WS01_26300_20261001-093321Z/RemoteFirewall/accounts.csv
b703b884d9bf432cdde48248270215725b6011e5825bd1828d9b8bd3ac2b7400  WS01_26300_20261001-093321Z/RemoteFirewall/accounts.json
e8fdbed67a3318e5bec73d5608cf7b355b9e6fd83859d737229c073c94344cb5  WS01_26300_20261001-093321Z/RemoteFirewall/globalsettings.json
...
```

Only the firewall and the services of a list of computers over WinRM HTTPS, with fully qualified names that match the listener certificates:

```powershell
PS C:\> 'SRV01.contoso.com', 'SRV02.contoso.com' | Get-RemoteBaseline -OutputPath C:\BaselineRuns -Type Firewall, Service -UseSSL
```

Two collectors run, in the fixed order Firewall then Service, each once for both computers, with `-UseSSL` and the default `-ThrottleLimit` of 32. The result is one row per name, `Success` when both collectors collected everything and `Partial` or `Failed` otherwise, and one host folder per reached computer with a `RemoteFirewall` and a `RemoteService` subfolder.

A name that is not reachable gets a `Failed` row with an empty `OutputFolder` and the connection error in `Errors`, and the other names of the call are not affected:

```powershell
PS C:\> Get-RemoteBaseline -ComputerName 'SRV01.contoso.com', 'NOSUCH.contoso.com' -OutputPath C:\BaselineRuns -Type Service | Format-Table -Property ComputerName, Status, ServiceStatus, ErrorCount
```

## Functions

The list of the functions contained in this module.

### Get-RemoteBaseline

```PowerShell
<#
.SYNOPSIS
    Runs the bundled Remote collectors against local or remote computers and arranges the
    output per host.

.DESCRIPTION
    Collects with any combination of five collectors that ship inside this module as unchanged
    copies, so nothing else needs to be installed on the collecting computer or on the
    targets: Firewall (RemoteFirewall), RSOP (RemoteRSOP), ScheduledTask (RemoteScheduledTask),
    SecEdit (RemoteSecEdit) and Service (RemoteService). Each collector runs once for the
    whole list of computers, in the fixed order Firewall, RSOP, ScheduledTask, SecEdit,
    Service, with the parameters of this call, and keeps its own WinRM fan-out. Targets are
    only read, never changed; this module adds no action on a target.

    Writes <OutputPath>\RemoteBaseline-<yyyyMMdd-HHmmss>Z\ (a _2, _3 suffix on collision)
    containing run.json, results.csv, manifest.sha256, a collectors folder with the run.json
    and results.csv of each collector run, and one host folder per reached computer
    (<REPORTED>_<CurrentBuild>_<stamp>Z) with host.json and one subfolder per collector, named
    after the module, holding that collector's computer folder with its files intact. Names of
    one local computer share one host folder. A computer that no selected collector reached
    has no host folder and a Failed row; one that only some reached has the subfolders of
    those collectors. host.json is deliberately not named system.json, so a reader looking for
    computer folders never mistakes a host folder for one.

    manifest.sha256 holds the SHA-256 of every other file in the run folder, one line each, so
    the run can be checked after it has been copied or sent. With -Compress the run folder is
    also written as <run folder>.zip beside it.

    Returns one result row per requested name after the last collector has returned and the
    arrangement is done. Status is Success when every selected collector's row is Success and
    the arrangement added nothing, Failed when every collector's row is Failed (or the name
    has none), and Partial otherwise. The per-type status and error count columns say which
    collector was not clean. The function never throws: every failure is a row value, an
    Errors line or a warning, one warning per row that is not Success, written after the files
    are and after the rows have been returned. A failure to write run.json or results.csv, or
    to write the manifest or the zip, cannot be recorded in the files it concerns, so the lines
    run.json:, results.csv:, manifest: and zip: appear in the returned rows only and make
    every Success row Partial; the manifest and the zip are still written over what exists.
    A rename or move of a collector's folder that NTFS refuses is tried three times, 500 ms
    apart, before an arrange: line is written.

.PARAMETER ComputerName
    Targets, as in the collectors: '.', 'localhost', '127.0.0.1', '::1', the local NetBIOS name
    and the local FQDN run in-process without WinRM, everything else goes through WinRM.
    Accepts pipeline input by value and by property name. Duplicates are removed
    case-insensitively and the first-seen order is kept. Defaults to the local computer name.

.PARAMETER Type
    The collectors to run: Firewall, RSOP, ScheduledTask, SecEdit, Service. Defaults to all
    five. Duplicates and case differences collapse, and the run order is fixed whatever the
    order given.

.PARAMETER Credential
    Passed to every collector, only when given. The collectors use it for remote targets only.

.PARAMETER UseSSL
    Passed to every collector, only when set: remote targets are contacted over WinRM HTTPS
    (port 5986). Certificate checks are never skipped.

.PARAMETER OutputPath
    Root folder for the run. May be relative. Resolved once against the current location,
    created if missing, and tested for writing before any target is contacted. In Windows
    PowerShell 5.1 the resolved path may be at most 105 characters, because a collection writes
    about 150 characters below it and 5.1 limits a path to 260; a longer path gives a Failed
    row per computer and writes nothing. PowerShell 7 has no such check.

.PARAMETER ThrottleLimit
    Passed to every collector. From 1 to 256. Defaults to 32.

.PARAMETER Compress
    Writes <run folder>.zip beside the run folder after the manifest, one entry per file with
    forward-slash entry names that every unzip tool reads as folders (Compress-Archive in
    Windows PowerShell 5.1 writes backslashes, so it is not used). Optional because the raw
    dumps of many hosts make the zip large and slow to write. An existing zip of the same name
    is never replaced: the row gets a zip: line instead.

.EXAMPLE
    PS C:\> Get-RemoteBaseline -OutputPath C:\BaselineRuns -Type Firewall, Service | Format-Table -Property ComputerName, Status, FirewallStatus, ServiceStatus, ErrorCount

    ComputerName Status  FirewallStatus ServiceStatus ErrorCount
    ------------ ------  -------------- ------------- ----------
    WS01         Partial Partial        Partial               10

    Collects the firewall and the services of the local computer from a session that is not
    elevated. Two collectors run, in the order Firewall then Service, and the row carries a
    status for each of them. Both came back Partial because they could not open every item
    without administrative rights, so the umbrella row is Partial too, with the ten error
    lines of the two collectors prefixed Firewall: and Service:.

.EXAMPLE
    PS C:\> 'WS01', 'SRV01.contoso.com' | Get-RemoteBaseline -OutputPath C:\BaselineRuns -UseSSL -Compress

    Runs all five collectors against two computers over WinRM HTTPS and writes the run folder
    and a zip of it. The names must match the listener certificates, as for any collector.

.NOTES
    FUNCTION: Get-RemoteBaseline
    AUTHOR:   Tom Stryhn
    GITHUB:   https://github.com/tomstryhn/

.INPUTS
    System.String[]. ComputerName is accepted from the pipeline, by value and by property
    name.

.OUTPUTS
    System.Management.Automation.PSObject, type name RemoteBaseline.Result

.LINK
    https://github.com/tomstryhn/RemoteBaseline
#>
```

## How it works

`Get-RemoteBaseline` is a thin layer over the five collectors; it collects nothing itself. In order, one call:

1. Resolves `-OutputPath` once against the current location, creates the run folder `RemoteBaseline-<stamp>Z` (and `collectors\` inside it) and proves it can write. A failure here gives one `Failed` row per requested name with the error `output path: <message>`, no files, and the call returns before any target is contacted. On Windows PowerShell 5.1 a resolved path longer than 105 characters fails here too, because the staging layout needs about 150 characters below it and 5.1 limits a path to 260.
2. Reads the identity of the collecting computer for `run.json`.
3. Runs each selected collector once, in the fixed order Firewall, RSOP, ScheduledTask, SecEdit, Service, for the whole list of computers, with `-OutputPath` set to `collectors\`, the de-duplicated names, `-ThrottleLimit`, `-Credential` and `-UseSSL` only when given, and the collector's own warnings suppressed (their content reaches the caller through the rows). Each collector keeps its own WinRM fan-out. A collector that throws, which is not expected, gives every name a synthetic `Failed` row with the error `host: <message>`; a name a collector returned no row for gets a `Failed` row with `host: no result row returned`. The collector is called from this module's own nested module copy, never by name through your session, so an alias or function of the same name in a profile cannot take its place. The collector's run folder is renamed to `collectors\<Module>`, and only when it sits directly under `collectors\`.
4. Moves every computer folder a row names to `<host folder>\<Module>`, with a single rename on the same volume, so the files are not copied or touched; a computer folder that is not directly inside its collector's run folder is refused, and a rename or move that NTFS refuses is tried three times, 500 ms apart, before it counts as failed. The host folder is `<REPORTED>_<CurrentBuild>_<stamp of the run>Z`, built from the computer folder name by reading its stamp, build and reported name from the right. A name that an earlier collector already placed keeps its host folder, so one host ends in one folder per requested name whatever collectors reached it. A failure adds `arrange: <Module>: <message>` and leaves the folder where it was.
5. Writes `host.json` in every host folder.
6. Builds the result rows, then writes `run.json` and `results.csv`.
7. Writes `manifest.sha256` and, with `-Compress`, the zip. The manifest hashes every file with `Get-FileHash` and leaves no partial file on a failure; the zip is written with `System.IO.Compression`, with one entry per file in the order of the manifest, forward-slash entry names and no existing file overwritten, and a partial zip is removed.
8. Emits the rows, then one `Write-Warning` per row whose `Status` is not `Success`: `<ComputerName>: <Status>, <ErrorCount> error(s): <Error>`. The warnings come last, so a caller's `-WarningAction Stop` already has the rows and every file.

The function never throws and the exit code is 0: every failure is a row value, an `Errors` line or a warning. An empty `-ComputerName` list gives one warning and no row. The five collectors are loaded as nested modules of `RemoteBaseline`, so they resolve to the bundled versions inside it whatever the caller has imported or installed, only `Get-RemoteBaseline` is exported, and removing `RemoteBaseline` leaves the caller's own copies of the collectors as they were. The collectors' files are never read for content except each host's first `system.json`, for `host.json`, and never modified after they were written.

### What to send back

Send the zip `RemoteBaseline-<timestamp>Z.zip`, or the whole `RemoteBaseline-<timestamp>Z` folder, and keep `manifest.sha256` in it. Do not edit any file inside it before sending. The receiver proves that every file is intact and none is missing or added by recomputing the hashes against the manifest. In PowerShell, from the unzipped run folder:

```powershell
$run = 'C:\Path\To\RemoteBaseline-20261001-093321Z'
$listed = @()
foreach ($line in Get-Content -LiteralPath (Join-Path $run 'manifest.sha256')) {
    $hash, $relative = $line -split '  ', 2
    $listed += $relative
    $file = Join-Path $run $relative
    if (-not (Test-Path -LiteralPath $file)) { "MISSING  $relative" }
    elseif ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $hash) { "DIFFERS  $relative" }
}
Get-ChildItem -LiteralPath $run -Recurse -File | ForEach-Object { $_.FullName.Substring($run.Length + 1).Replace('\', '/') } |
    Where-Object { $_ -ne 'manifest.sha256' -and $listed -notcontains $_ } | ForEach-Object { "EXTRA    $_" }
```

It prints nothing when the run folder is exactly what was hashed. On Linux or macOS, `sha256sum -c manifest.sha256` (or `shasum -a 256 -c manifest.sha256`) from inside the run folder does the first part. The manifest proves the files were not changed after the run; it does not prove who wrote them, and the files are not signed. The `run.json:`, `results.csv:`, `manifest:` and `zip:` lines of the returned rows are not in any file, so a run whose `run.json`, `results.csv`, manifest or zip failed lacks that file, and its rows say why.

## Testing

`tests\Invoke-Tests.ps1` runs `PSScriptAnalyzer` (pinned to 1.25.0) over the module and tests
folder using `PSScriptAnalyzerSettings.psd1`, then runs the Pester suite (pinned to 6.1.0). It exits 1 on any analyzer Error or Warning
result, on any failed test, or when zero tests ran.

The gate needs Pester 6.1.0 and PSScriptAnalyzer 1.25.0 exactly; Windows PowerShell 5.1 ships Pester 3.4, so install both once per engine with `Install-Module Pester -RequiredVersion 6.1.0 -Scope CurrentUser -Force` and `Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser`. Without them the gate exits 1 before any test runs. A few tests that need administrative rights report Inconclusive in an unelevated session, which does not fail the gate; run the gate once elevated per release to cover them.

Run it under both engines from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-Tests.ps1
pwsh -NoProfile -File tests\Invoke-Tests.ps1
```

Every path inside the test suite is derived from `$PSScriptRoot`, so it also passes from a
relocated copy of the repository.

## Support and versioning

Versions follow semantic versioning: a patch release changes no output file, column or value; a minor release may add columns, keys or files and may change a value's rule, and the five Remote collectors release such a change together under one output convention version; a major release would change an existing column or key. Every release is a tagged commit (`v<version>`) and the Version Changes list above is the change log. Report a defect or a question as an issue on the project repository (ProjectUri in the manifest); report a security concern as described in SECURITY.md. The module is provided under the MIT licence without a support contract; fixes land in the next release.

## References

- [RemoteFirewall](https://github.com/tomstryhn/RemoteFirewall)
- [RemoteRSOP](https://github.com/tomstryhn/RemoteRSOP)
- [RemoteScheduledTask](https://github.com/tomstryhn/RemoteScheduledTask)
- [RemoteSecEdit](https://github.com/tomstryhn/RemoteSecEdit)
- [RemoteService](https://github.com/tomstryhn/RemoteService)
- [Get-FileHash - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash)
- [ZipArchive Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.io.compression.ziparchive)

## License

Tom Stryhn, https://github.com/tomstryhn

Project: https://github.com/tomstryhn/RemoteBaseline

MIT License, see [LICENSE](LICENSE)
