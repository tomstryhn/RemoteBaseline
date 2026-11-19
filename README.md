# RemoteBaseline PowerShell Module

Collects the computer itself (hardware, hotfixes and features), the Group Policy results, the scheduled tasks, the local security policy, the services, the Windows Firewall and the event logs of local and remote Windows computers in one call, with seven collectors that ship inside the module, and arranges what it collects per host in one hashed, optionally zipped run folder, without interpreting anything.

## Table of Contents

- [Version Changes](#version-changes)
- [Background](#background)
  - [Risk(s)](#risks)
  - [Mitigation](#mitigation)
  - [Bundled collectors](#bundled-collectors)
- [Requirements](#requirements)
- [Output Data Handling](#output-data-handling)
- [Download](#download)
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

##### 1.4.0

- Bundles seven collectors: RemoteEventLog 1.0.0, RemoteFirewall 1.5.0, RemoteRSOP 1.5.0, RemoteScheduledTask 1.6.0, RemoteSecEdit 1.8.0, RemoteService 1.7.0 and RemoteSystem 1.0.0. The two new ones are RemoteSystem (the computer, its processors, memory modules, disks, volumes, network adapters, hotfixes and features) and RemoteEventLog (the event logs with their configuration, size, oldest and newest record, retention policy, archived files and the accounts that may read them).
- `-Type` accepts `System` and `EventLog` besides the five it had, and the default is all seven.
- The run order is now System, RSOP, ScheduledTask, SecEdit, Service, Firewall, EventLog. It was Firewall, RSOP, ScheduledTask, SecEdit, Service, so Firewall moves from the first place to the sixth. RemoteSystem is first, so it is the collector that reads the SID reference of the host and the six others are called with `-SkipSidReference`. `Types` in the row, in `run.json` and in `host.json`, the `Collectors` lists, the per-type columns and the order of the lines in `Errors` follow the new order. A script that reads the per-type columns of `results.csv` by position, and not by name, sees them move.
- The result row, `run.json` and `results.csv` gain `SystemStatus`, `EventLogStatus`, `SystemErrorCount` and `EventLogErrorCount`. The status columns come first, then the error counts, each group in run order, null for a type that was not selected.
- Csv guard. In `results.csv` a text cell that starts with `=`, `+`, `-` or `@` is written with one apostrophe in front, so a spreadsheet shows it as text and does not run it as a formula. This is applied after the whitespace of the cell is trimmed. Null, an empty string, numbers and booleans are written as before, the header row is not touched, and a string that holds a negative number as text (`-1`) gets the apostrophe. `run.json` is not changed and holds the exact value, so a script that needs the source value reads the json, or removes one leading apostrophe from a csv cell when the next character is one of the four. A source value that itself starts with an apostrophe and one of the four cannot be told apart in the csv. The csv files of the bundled collectors follow the same rule from their versions in this bundle (in `rules.csv` of RemoteFirewall a `Group` such as `@FirewallAPI.dll,-30267` now reads `'@FirewallAPI.dll,-30267`).
- The test suite runs from any folder, also one with square brackets or a space in its name. The analyzer step takes the folder path literally.
- Follows the common file layout of the Remote collectors (output convention 1.5): `run.json` carries `SchemaVersion` `1.5`.
- New `-SkipDismFeatures`. It is handed to the System collector only, and `run.json` records it as `SkipDismFeatures` directly after `UseSSL`. With it RemoteSystem does not read the DISM feature list: the `DismState` column of its features output stays empty. Use it when a trace on the target or the run time matters (see What RemoteSystem reads from DISM below). A bundled RemoteSystem that has no such switch is called without it.
- Application package and capability SIDs are no longer in `accounts.json` and `accounts.csv`. Every collector now writes them to their own pair, `appcontainers.json` and `appcontainers.csv`, in the same folder and under the same `-OutputFormat` rule as `accounts`. Only RemoteFirewall gives a package its package family name, and a capability has no name. `AppContainerCount` is a new key in each `summary.json` and `system.json`, and `AccountCount` counts accounts only.
- RemoteSystem: the features output has a `DismState` column beside `InstallState`, a new `ReadSkippedCount` counts a read that was left out on purpose (the DISM read with `-SkipDismFeatures`), and `run.json` of that collector has `SkipDismFeatures`.

##### 1.3.0

- Bundles RemoteFirewall 1.4.0, RemoteRSOP 1.4.0, RemoteScheduledTask 1.5.0, RemoteSecEdit 1.7.0 and RemoteService 1.6.0.
- RemoteService 1.6.0 adds data to the services files of each host. Every service in `services.json` also lists the services and groups it depends on (`DependOnService`, `DependOnGroup`), the services of the computer that depend on it (`DependentServices`) and its ServiceDll (`ServiceDll`, `ServiceDllPath`). `services.csv` gains the columns `ServiceDll` and `ServiceDllPath`. Every ServiceDll file is identified like a service executable, so it is a row in `binaries.json` and `binaries.csv`, counts in `BinaryCount`, and a missing one counts in `BinaryMissingCount` and makes the service row `Partial`. `summary.json` and `system.json` gain `ServiceDllCount` and `RegistryDurationMs`.
- No change to `Get-RemoteBaseline`, its parameters, `run.json`, `host.json` or the output convention (version 1.4).

##### 1.2.0

- Bundles RemoteFirewall 1.4.0, RemoteRSOP 1.4.0, RemoteScheduledTask 1.5.0, RemoteSecEdit 1.7.0 and RemoteService 1.5.0.
- New `-OutputFormat` with `Json`, `Csv` or `Both`, default `Json`. A default call no longer writes a csv file: the module's own `results.csv` is written with `Csv` and `Both` only, and `run.json` always holds the results. The format is passed to every bundled collector that has the parameter, so their `results.csv` and per-computer csv files follow it. A bundled collector without the parameter is called without it, writes both kinds of file, and its files are kept as they are.
- `-OutputPath` is optional. Without it the run folder is created in the current location. A call made from a drive such as `HKLM:` uses the last file-system location of the session.
- `run.json` records `OutputFormat` after `Archive` and carries `SchemaVersion` `1.4`, following output convention 1.4.
- `manifest.sha256` lists the files that are on disk, whichever format wrote them.
- On PowerShell 7 the csv writer no longer passes `-NoTypeInformation`, which that engine reports as obsolete in a warning on every call. The file is the same on both engines.

##### 1.1.0

- Bundles RemoteFirewall 1.3.0, RemoteRSOP 1.3.0, RemoteScheduledTask 1.4.1, RemoteSecEdit 1.6.0 and RemoteService 1.4.0.
- An elevated run against Windows Server 2022, Windows Server 2025 or Windows 11 no longer comes back `Partial` for the Windows Update task whose program is not on the disk (`failover.exe`, `MusNotification.exe`): RemoteScheduledTask 1.4.1 records the file as data and does not count it as an error.
- `RemoteBaseline-v<version>.zip` in the repository root holds the module folder and a quick guide, for download and sharing.
- The SID reference of output convention 1.3 is read once per host and run. The first selected collector in run order reads `MachineSid`, `DomainSid`, `ComputerAccountSid` and `DomainNetbiosName`. Every later collector is called with `-SkipSidReference`, so its `system.json` holds null for them. `Get-RemoteBaseline` has no new parameter.
- `host.json` gains `MachineSid`, `DomainSid`, `ComputerAccountSid` and `DomainNetbiosName` directly after `MachineGuid`, copied from the first present `system.json` like its other identity values. In a bundle run `host.json` is the place to read them. A host the first selected collector did not reach has null in `host.json`.
- A bundled collector whose function has no `-SkipSidReference` parameter is called without it, and nothing is reported. The values appear only with RemoteRSOP 1.3.0, RemoteScheduledTask 1.4.1, RemoteSecEdit 1.6.0, RemoteService 1.4.0 and RemoteFirewall 1.3.0 in the bundle.
- Follows output convention 1.3: `run.json` carries `SchemaVersion` `1.3`. No new key in `run.json`.

##### 1.0.0

- First release. One function, `Get-RemoteBaseline`, runs any combination of five collectors against local and remote computers and arranges their output per host.
- The five collectors are bundled, unchanged, as nested modules: RemoteFirewall 1.2.0, RemoteRSOP 1.2.0, RemoteScheduledTask 1.3.0, RemoteSecEdit 1.5.0 and RemoteService 1.3.0. They load inside this module at exactly these versions, whatever the collecting computer has installed, and nothing else needs to be installed on the collecting computer or on the targets. `Modules\bundle.json` records the SHA-256 of every bundled file, and a test proves the bundle matches it.
- Takes the family's parameters (`-ComputerName`, `-Credential`, `-UseSSL`, `-OutputPath`, `-ThrottleLimit`), forwards them unchanged to every collector, and adds `-Type` (Firewall, RSOP, ScheduledTask, SecEdit, Service, default all five) and `-Compress`.
- Writes one run folder per call with `run.json`, `results.csv`, `manifest.sha256` (the SHA-256 of every other file in the run folder) and one folder per reached host, named `<REPORTED>_<CurrentBuild>_<stamp>Z`, that holds `host.json` and one subfolder per collector with that collector's computer folder, files intact. The collectors' own `run.json` and `results.csv` are kept under `collectors\<Module>\`.
- Returns one result row per requested name, with a `Status` over all selected collectors and a status and error count column per collector, so one look says which collector was not clean.
- `-Compress` writes the run folder as one zip beside it with forward-slash entry names, which every unzip tool reads as folders (`Compress-Archive` in Windows PowerShell 5.1 writes backslashes). It uses `System.IO.Compression`, so there is no 2 GB limit.
- On Windows PowerShell 5.1 the resolved `-OutputPath` may be at most 105 characters. A longer one gives a `Failed` row that says so before anything is written. PowerShell 7 has no such limit.
- Follows output convention 1.2: `run.json` carries `SchemaVersion` `1.2`.
- Runs on Windows PowerShell 5.1 and PowerShell 7, with a Pester test suite covering both engines.

## Background

A security baseline review needs the same seven things from every computer: the computer itself (hardware, hotfixes and features), the Group Policy that applied, the scheduled tasks, the local security policy (user rights and the accounts they name), the services, the Windows Firewall rules and the event logs. Each has a collector in the Remote family, and each collector writes its own run folder with one folder per computer.

### Risk(s)

Running seven collectors means seven modules to install and keep at the same version on the collecting computer, seven run folders per call, and a hand-made match of the seven computer folders of one host. A set of loose files handed back by a client or a technician cannot be told from a set that was edited, partly copied or mixed with an older run.

### Mitigation

One function runs the collectors you pick, from versions pinned inside the module, and arranges the result per host: one folder per host with a `host.json` and one subfolder per collector, and one result row per requested name. `manifest.sha256` lists the SHA-256 of every file of the run, so the receiver can prove that what arrived is what was collected.

### Bundled collectors

The collectors are not changed: the module holds their module folders byte for byte, and every bundled file has its hash in `Modules\bundle.json`. Each collector is a complete module of its own under `RemoteBaseline\Modules\<Name>`. To read what one collects and which files it writes, import its manifest and ask for the help of its function, for example `Import-Module .\RemoteBaseline\Modules\RemoteService\RemoteService.psd1` and `Get-Help Get-ServiceInventory -Full`.

| Module | Version | What it collects | Function |
|---|---|---|---|
| RemoteSystem | 1.0.0 | The computer, its processors, memory modules, disks, volumes, network adapters, hotfixes and features, and every account that installed a hotfix | `Get-SystemInventory` |
| RemoteRSOP | 1.5.0 | The Resultant Set of Policy data Windows keeps in `root\RSOP`, and every account a user right or a restricted group references | `Get-RsopInventory` |
| RemoteScheduledTask | 1.6.0 | Every scheduled task with its definition, account, security descriptor, run-time state and the identity and signature of each action binary | `Get-ScheduledTaskInventory` |
| RemoteSecEdit | 1.8.0 | The raw output of `secedit /export`, plain and `/mergedpolicy`, and every account the user rights reference | `Get-SecEditExport` |
| RemoteService | 1.7.0 | Every Windows service with its account, dependencies, ServiceDll, security descriptor, and the identity and signature of its binary and ServiceDll file | `Get-ServiceInventory` |
| RemoteFirewall | 1.5.0 | The three firewall profiles, the global settings, every firewall rule with its seven filters, and the security principals the rules name | `Get-FirewallInventory` |
| RemoteEventLog | 1.0.0 | Every event log with its configuration, size, oldest and newest record, retention policy and archived files, and the accounts its security descriptor names | `Get-EventLogInventory` |

The table is in run order.

SID reference. From output convention 1.3 each collector can also read four values that say whose an `S-1-5-21-...` SID is: `MachineSid` (the computer's own account database, null on a domain controller), and `DomainSid`, `ComputerAccountSid` and `DomainNetbiosName` (null on a workgroup computer). RemoteBaseline has them read once per host and run: the first selected collector in run order reads them (RemoteSystem when it is selected), every later one is called with `-SkipSidReference`, and `host.json` carries them. Read them from `host.json` in a bundle run, because the `system.json` of the later collectors holds null. A bundled collector without the switch is called without it and nothing is reported, so a bundle that holds the released 1.x collectors gives null in `host.json`. The values appear with RemoteRSOP 1.3.0, RemoteScheduledTask 1.4.1, RemoteSecEdit 1.6.0, RemoteService 1.4.0 and RemoteFirewall 1.3.0, and RemoteSystem and RemoteEventLog have the switch from their first version.

What RemoteSystem reads from DISM. The features output of RemoteSystem has two state columns for an optional feature: `InstallState`, read from the Windows feature list, and `DismState`, read from DISM. The second one tells a feature that is disabled with its files still on the disk (`Disabled`) from one that is disabled with its files removed (`DisabledWithPayloadRemoved`), which `InstallState` cannot do, so a feature that cannot be switched on again without a source is visible in the output. The DISM read has two costs. Windows appends to its own log, `%WINDIR%\Logs\DISM\dism.log`, on every target that is read, so that file on the target shows the read (RemoteSystem writes no file on the target, Windows writes this one). And the read adds about 4 s per server and 12 to 14 s per Windows 11 client to the run. `-SkipDismFeatures` leaves the read out: no trace in `dism.log`, no extra time, and `DismState` is empty on every feature row. Nothing else changes and the row is not made `Partial` by it. The DISM read needs an elevated session.

Accounts and application containers. In every collector that writes `accounts.json` and `accounts.csv` (all seven), the accounts file holds principals that an account lookup can answer: users, groups, computers, service accounts and well-known SIDs. The SIDs of an application package (`S-1-15-2-...`) and of a capability (`S-1-15-3-...`) are not accounts and have their own file pair, `appcontainers.json` and `appcontainers.csv`, in the same computer folder. The class comes from the text of the SID alone, so a token lands in the same file on every computer, and no lookup is made for it. The two well-known groups `S-1-15-2-1` and `S-1-15-2-2` (all application packages, all restricted application packages) stay in the accounts file. The csv columns are `Token`, `Kind` (`Package` or `Capability`), `Sid`, `Name`, `ReferenceCount`, and the json also lists `References`. Only RemoteFirewall names a package, with its package family name, when the package is installed. Everywhere else `Name` is empty and no name is known. `summary.json` has `AppContainerCount` directly after `AccountUnresolvedTokens`, and `AccountCount`, `AccountUnresolvedCount` and `AccountUnresolvedTokens` count accounts only. A script that took package SIDs from the accounts file reads the appcontainers file now.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on the collecting computer. The targets run Windows PowerShell 5.1.
- Nothing else to install: the seven collectors are inside the module. The firewall collector reads through the `NetSecurity` module on the target (it ships with Windows 8 and Server 2012 and later, so this is normally already true).
- The module is read-only on every target: the collectors only read, and `Get-RemoteBaseline` adds no action on a target. Two traces remain. RemoteSecEdit creates a work folder `%TEMP%\RemoteSecEdit-<guid>` on the target for the `secedit /export` files and deletes it again before it returns. The DISM read of RemoteSystem makes Windows append to `%WINDIR%\Logs\DISM\dism.log`. `-SkipDismFeatures` avoids the second, and leaving `SecEdit` out of `-Type` avoids the first.

Run elevated for a complete collection. Running without administrative rights has consequences that are captured in the rows rather than hidden, one per collector: RemoteSystem `Partial` (the Tpm, Secure Boot and DISM feature reads fail, the last one only without `-SkipDismFeatures`), RemoteRSOP `Failed` (the RSOP namespaces cannot be read), RemoteScheduledTask `Partial` (tasks the caller cannot open are not listed), RemoteSecEdit `Failed` (`secedit` exits with 740), RemoteService `Partial` (services and security descriptors the caller cannot open are not listed), RemoteFirewall `Partial` (the address, port, interface and interface type filters and the installed packages cannot be read) and RemoteEventLog `Partial` (the information of a log the caller cannot open is not read, and each such log is an error line). The row of the host is `Partial`, its per-type status columns say which collector was not clean, and `IsElevated` says which case a row is in. The first example of `Get-RemoteBaseline` in the Functions section shows such a run.

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
the module offers no SkipCACheck or SkipCNCheck option, by design. A target in a workgroup, or addressed by IP, needs the collecting computer to list it in TrustedHosts and, for a local administrator account that is not the built-in Administrator, `LocalAccountTokenFilterPolicy` set to 1 on the target. The module changes neither setting.

Known limits. The collection was verified with a local run on Windows Server 2022, over WinRM HTTP and HTTPS against Windows Server 2016, 2019, 2022 and 2025, and with a local run on Windows 11. The bundled collectors carry their own verification matrix. Windows client editions as remote targets and non-English Windows installations are untested: the code matches no English console text and reads SIDs and numeric codes, so locale risk is low, but it is not proven. The module runs in FullLanguage mode only: under ConstrainedLanguage mode, which an enforced WDAC or AppLocker policy produces, a target's worker fails at its first .NET call and the computer's row comes back `Failed` with that error. No file is left behind. On a collecting computer whose session runs in ConstrainedLanguage mode the call itself throws at its first .NET use before anything is written (the collectors behave the same when run locally there). The module files are not signed, so an AllSigned execution policy or a publisher rule refuses the import (see Importing the Module). A JEA endpoint does not run the worker: the module has no -ConfigurationName. On Windows PowerShell 5.1 the output path must be at most 105 characters, because the staging layout needs about 150 characters below it and 5.1 limits a path to 260. A longer path gives a Failed row that says so before anything is written.

Automation. `Get-RemoteBaseline` never throws once it runs in FullLanguage mode, and the exit code is 0 even when every row is `Failed`: a wrapper decides on the `Status` column of the row objects (or of `results.csv`, when `-OutputFormat` writes it), not on the exit code. No timeout parameter exists. A remote call uses the WinRM defaults (operation timeout 3 minutes). Running twice into the same `-OutputPath` never overwrites: every run gets its own UTC-stamped run folder. A caller's -WarningAction Stop turns a warning into a terminating error. The collectors emit their warnings after the run files are written, so the output on disk is complete in that case too.

## Output Data Handling

The output is a configuration inventory of every computer you collect from. It holds no password, key or password hash that the module reads on purpose, but it names hosts, hardware, patches, firewall rules, programs, ports, addresses, accounts, SIDs, scheduled tasks, services and event logs, the Group Policy objects that apply and the local security policy: which program may accept connections from where, which account runs which service or task, and which accounts hold which rights. It describes how each computer is exposed and administered in a detail that is useful to an attacker. Treat every output folder, and the zip, as confidential.

Each call writes one run folder under `-OutputPath` (the current location when the parameter is not given), and with `-Compress` a zip of it beside the run folder. `-OutputFormat` chooses which files of the tabular pairs are written: `Json`, the default, writes the json file of each pair and no csv file, `Csv` writes the csv files instead and `Both` writes both. For this module the pair is the results: `run.json` always holds them and `results.csv` is written with `Csv` and `Both`. The format is passed to every bundled collector that has the parameter. `run.json`, `host.json` and `manifest.sha256` are written whatever the format.

```
C:\BaselineRuns\RemoteBaseline-<yyyyMMdd-HHmmss>Z\
    run.json                           summary of the whole run
    results.csv                        one row per requested name, opens in Excel (only with -OutputFormat Csv or Both)
    manifest.sha256                    the SHA-256 of every other file in this folder
    collectors\
        RemoteSystem\                  run.json of that collector's run, and its results.csv when it wrote one
        RemoteRSOP\                    (one folder per selected collector)
        ...
    <REPORTED>_<CurrentBuild>_<stamp>Z\    one folder per reached host, per requested name
        host.json                      identity of the host and the status of each collector
        RemoteSystem\                  the collector's computer folder, files intact
        RemoteRSOP\
        ...
C:\BaselineRuns\RemoteBaseline-<yyyyMMdd-HHmmss>Z.zip      only with -Compress
```

A suffix `_2`, `_3` is added to the run folder name when the name is taken, and to a host folder name when two requested names of one host (a short name and a fully qualified name) map to the same name. Names of one local computer (`localhost`, `.` and its own name) share one host folder. A host that no selected collector reached has no host folder and a `Failed` row. A host that only some collectors reached has the subfolders of those collectors. The stamp in a host folder name is the stamp of the run folder. The stamp inside a collector's own folder names is that collector's. The subfolders hold exactly what the collector wrote, and the help of each collector's function lists the files: `computer.json` and `processors`, `memory`, `disks`, `volumes`, `adapters`, `hotfixes` and `features` for the computer, `gpos` and `settings` for RSOP, `tasks` and `binaries` for the scheduled tasks, the `secedit-export` files for the security policy, `services` and `binaries` for the services, `rules` and the profile files for the firewall, `logs` for the event logs. Every collector also writes `accounts` and `appcontainers` (the accounts the data names, and the application package and capability SIDs it names). The tabular ones are written as `.json` by default and as `.csv` with `-OutputFormat Csv` or `Both`, and each subfolder always has `system.json` and `summary.json`. A bundled collector that does not have `-OutputFormat` writes both kinds, and they are kept as they are.

`host.json` is deliberately not named `system.json`, so a loader that looks for computer folders by `system.json` never mistakes a host folder for one. Its keys, in this order: `ComputerName` (as requested, the first name for aliases), `RequestedNames`, `ComputerId`, `DnsHostName`, `Domain`, `OSCaption`, `OSVersion`, `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID`, `InstallationType`, `Culture`, `TimeZoneId`, `PartOfDomain`, `DomainRole`, `IsElevated`, `MachineGuid`, `MachineSid`, `DomainSid`, `ComputerAccountSid` and `DomainNetbiosName` (copied from the first present subfolder's `system.json`, null when absent, the last four are the SID reference, which only the first selected collector reads, so they are null when that collector did not reach the host), `Collector`, `CollectorVersion`, `RunId`, `Types`, `Collectors` (per selected type: `Type`, `Module`, `Version`, `Subfolder`, `Status`, `ErrorCount`, `RunId`), `Status` and `Errors`.

`run.json` is one object, with the keys in this order: `RunId`, `Collector`, `CollectorVersion`, `SchemaVersion`, `HostComputer`, `HostComputerId`, `HostUser`, `PSVersion`, `StartUtc`, `EndUtc`, `RequestedComputers`, `Types`, `ThrottleLimit`, `UseSSL`, `SkipDismFeatures` (`true` with `-SkipDismFeatures`, `false` without), `Compress`, `Archive` (the zip name, null without `-Compress`), `OutputFormat` (`Json`, `Csv` or `Both`), `Collectors` (per selected type: `Type`, `Module`, `Version`, `RunId`, `DurationMs`, `RowCount`, `SuccessCount`, `PartialCount`, `FailedCount`, `Error`) and `Results`, always an array. The collectors' own `run.json` keeps the `OutputFolder` values of the staging location where the computer folders were before they moved. The `run.json`, `results.csv` and `host.json` of the run folder are the authority for where files are.

The result row, in `run.json` and as the output of the function, has these columns in this order: `ComputerName` (as requested), `ComputerId`, `Status`, `Transport` (`Local` or `WinRM`), `OutputFolder` (the host folder, an empty string when no collector reached the host), `IsElevated`, `Types` (the selected types in run order, a string array in the json files and in the row, one text cell joined with a comma and a space in `results.csv`), `SystemStatus`, `RSOPStatus`, `ScheduledTaskStatus`, `SecEditStatus`, `ServiceStatus`, `FirewallStatus`, `EventLogStatus`, `SystemErrorCount`, `RSOPErrorCount`, `ScheduledTaskErrorCount`, `SecEditErrorCount`, `ServiceErrorCount`, `FirewallErrorCount`, `EventLogErrorCount` (null for a type that was not selected), `Error`, `ErrorCount` and `Errors`. `results.csv`, when it is written, holds every column but `Errors`. `Errors` lists every collector's error lines, each prefixed with its type (`Firewall: ...`), in run order, then the lines of the module itself: `arrange: <Module>: ...` when a folder could not be moved into place, `host.json: ...` when `host.json` could not be written or a `system.json` could not be read, `host: <message>` when a collector throws or returns no row, and `output path: <message>` when the run folder cannot be made. `Error` is the first entry and every entry is one line.

`Status` is `Failed` when every selected collector's row is `Failed` (or the name has none), `Success` when every selected collector's row is `Success` and the module added no line, and `Partial` otherwise. A failure to write `run.json` or `results.csv`, to write the manifest or to write the zip cannot be recorded in the files it concerns, because `run.json` and `results.csv` are inside the manifest and the zip. So the lines `run.json: <message>`, `results.csv: <message>`, `manifest: <message>` and `zip: <message>` exist in the returned rows only, never in a file on disk, and none of them is a warning in the middle of the run. The manifest and the zip are still written over what exists. They make every `Success` row `Partial`, because the deliverable (an intact, hashed, zipped run folder) is incomplete.

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

The collection leaves two traces on the computers it reads. RemoteSecEdit creates a work folder `%TEMP%\RemoteSecEdit-<guid>` for the `secedit /export` files and deletes it again before it returns. The DISM read of RemoteSystem makes Windows itself append to `%WINDIR%\Logs\DISM\dism.log`. `-SkipDismFeatures` leaves the DISM read out, and leaving `SecEdit` out of `-Type` avoids the work folder. A remote run returns its data over
WinRM, which encrypts the traffic of a Kerberos or NTLM authenticated session even over HTTP,
unless unencrypted traffic has been allowed on the endpoint.

File formats. The csv files, written with `-OutputFormat Csv` or `Both`, are UTF-8 with a byte order mark, every cell quoted, one row per line (whitespace inside a cell is collapsed to one space), with the same bytes on both engines. The json files are UTF-8 without a byte order mark, and a top-level array is an array at zero and one element too. The csv is for spreadsheets. A loader that needs the source form of a value, or the null against empty-string distinction, reads the json. A text cell that starts with `=`, `+`, `-` or `@` has one apostrophe in front in `results.csv`, so a spreadsheet does not take it for a formula, for example a requested name `-host01` reads `'-host01` in `results.csv` and is exact in `run.json`. The csv files of the bundled collectors follow the same rule, and a known effect is that the `Group` column of `rules.csv` from RemoteFirewall, which holds values such as `@FirewallAPI.dll,-30267`, and any other value that starts with `@` or `-` reads with the apostrophe. A script that reads a csv and needs the source value removes one leading apostrophe when the next character is one of the four. A source value that itself starts with an apostrophe and one of the four cannot be told apart in the csv, and the json is exact.

`manifest.sha256` has one line per file of the run folder except itself, whichever files the format wrote: the SHA-256 in lower-case hexadecimal, two spaces, and the path relative to the run folder with forward slashes, sorted by ordinal comparison, with LF line endings and no byte order mark, so `sha256sum -c manifest.sha256` checks it on Linux and macOS.

## Download

Every release has `RemoteBaseline-v<version>.zip` in the root of the repository: the module folder `RemoteBaseline\` and a quick guide, `QuickGuide-v<version>.txt`, and nothing else, so it is quick to download and to hand to someone who only needs to run the collection. Extract it with "Extract All" and follow the guide. Only the zip of the current version is kept in the root.

To check that the zip holds the same module as the repository, run the tests (see Testing): the release zip tests compare the entry names of the zip with the files of the module folder, and the SHA-256 of every file in the zip with the file on disk. They are skipped while the repository root holds no zip.

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

Keep the module in a folder whose path has no square brackets. Both engines refuse to import it
from a path with `[` or `]` in it, with the error `Wildcard characters are not allowed in members
'ModuleToProcess', 'RootModule', or 'NestedModules'`, because the module loads its collectors as
nested modules. A space in the path is fine.

## Examples

Collecting everything from one remote computer, with the json and the csv files and into a zip as well. Use the fully qualified name of a remote computer:

```powershell
PS C:\> Get-RemoteBaseline -ComputerName srv01.contoso.com -OutputPath C:\BaselineRuns -OutputFormat Both -Compress | Format-List

ComputerName            : srv01.contoso.com
ComputerId              : 11111111-2222-3333-4444-555555555501
Status                  : Success
Transport               : WinRM
OutputFolder            : C:\BaselineRuns\RemoteBaseline-20261015-093000Z\SRV01_20348_20261015-093000Z
IsElevated              : True
Types                   : {System, RSOP, ScheduledTask, SecEdit...}
SystemStatus            : Success
RSOPStatus              : Success
ScheduledTaskStatus     : Success
SecEditStatus           : Success
ServiceStatus           : Success
FirewallStatus          : Success
EventLogStatus          : Success
SystemErrorCount        : 0
RSOPErrorCount          : 0
ScheduledTaskErrorCount : 0
SecEditErrorCount       : 0
ServiceErrorCount       : 0
FirewallErrorCount      : 0
EventLogErrorCount      : 0
Error                   :
ErrorCount              : 0
Errors                  : {}
```

That run took 45 s and wrote a zip beside the run folder. One row came back for the one name, `Success`, and the seven per-type columns show that every collector was clean, so no warning was written. With `-OutputFormat Both` the run folder looks as follows, with the files of each collector summarised:

```
C:\BaselineRuns\RemoteBaseline-20261015-093000Z\
    run.json
    results.csv
    manifest.sha256
    collectors\
        RemoteSystem\           results.csv, run.json
        RemoteRSOP\             results.csv, run.json
        RemoteScheduledTask\    results.csv, run.json
        RemoteSecEdit\          results.csv, run.json
        RemoteService\          results.csv, run.json
        RemoteFirewall\         results.csv, run.json
        RemoteEventLog\         results.csv, run.json
    SRV01_20348_20261015-093000Z\
        host.json
        RemoteSystem\           accounts, adapters, appcontainers, disks, features, hotfixes, memory, processors, volumes (.csv and .json), computer.json, summary.json, system.json
        RemoteRSOP\             accounts, appcontainers, extensions, gpos, links, settings (.csv and .json), raw.json, summary.json, system.json
        RemoteScheduledTask\    accounts, appcontainers, binaries, tasks (.csv and .json), summary.json, system.json
        RemoteSecEdit\          accounts, appcontainers (.csv and .json), secedit-export and secedit-mergedpolicy (.inf, .log and .stdout.txt), summary.json, system.json
        RemoteService\          accounts, appcontainers, binaries, services (.csv and .json), summary.json, system.json
        RemoteFirewall\         accounts, appcontainers, profiles, rules (.csv and .json), globalsettings.json, summary.json, system.json
        RemoteEventLog\         accounts, appcontainers, logs (.csv and .json), summary.json, system.json
```

Every collector writes `appcontainers.json` and `appcontainers.csv` (with `-OutputFormat Csv` or `Both` for the csv) beside `accounts`. This is `appcontainers.json` of RemoteFirewall:

```json
[
    {
        "Token":  "S-1-15-2-1111111111-2222222222-3333333333-4444444444-5555555555-6666666666-7777777777",
        "Kind":  "Package",
        "Sid":  "S-1-15-2-1111111111-2222222222-3333333333-4444444444-5555555555-6666666666-7777777777",
        "Name":  "Contoso.ExampleApp_8wekyb3d8bbwe",
        "ReferenceCount":  2,
        "References":  [ "rule1", "rule2" ]
    }
]
```

`host.json` of that run. The first entry of `Collectors` is shown, one entry per selected type follows in run order:

```json
{
    "ComputerName":  "srv01.contoso.com",
    "RequestedNames":  [
                           "srv01.contoso.com"
                       ],
    "ComputerId":  "11111111-2222-3333-4444-555555555501",
    "DnsHostName":  "SRV01",
    "Domain":  "contoso.com",
    "OSCaption":  "Microsoft Windows Server 2022 Standard",
    "OSVersion":  "10.0.20348",
    "CurrentBuild":  "20348",
    "UBR":  "5000",
    "DisplayVersion":  "21H2",
    "EditionID":  "ServerStandard",
    "InstallationType":  "Server",
    "Culture":  "en-US",
    "TimeZoneId":  "UTC",
    "PartOfDomain":  true,
    "DomainRole":  3,
    "IsElevated":  true,
    "MachineGuid":  "11111111-2222-3333-4444-555555555502",
    "MachineSid":  "S-1-5-21-4444444444-5555555555-6666666666",
    "DomainSid":  "S-1-5-21-1111111111-2222222222-3333333333",
    "ComputerAccountSid":  "S-1-5-21-1111111111-2222222222-3333333333-1104",
    "DomainNetbiosName":  "CONTOSO",
    "Collector":  "RemoteBaseline",
    "CollectorVersion":  "1.4.0",
    "RunId":  "RemoteBaseline-20261015-093000Z",
    "Types":  [ "System", "RSOP", "ScheduledTask", "SecEdit", "Service", "Firewall", "EventLog" ],
    "Collectors":  [
                       {
                           "Type":  "System",
                           "Module":  "RemoteSystem",
                           "Version":  "1.0.0",
                           "Subfolder":  "RemoteSystem",
                           "Status":  "Success",
                           "ErrorCount":  0,
                           "RunId":  "RemoteSystem-20261015-093000Z"
                       },
                       ...
                   ],
    "Status":  "Success",
    "Errors":  [

               ]
}
```

`run.json` of that run. The first entry of `Collectors` is shown, and `Results` holds the one row:

```json
{
    "RunId":  "RemoteBaseline-20261015-093000Z",
    "Collector":  "RemoteBaseline",
    "CollectorVersion":  "1.4.0",
    "SchemaVersion":  "1.5",
    "HostComputer":  "ADMIN01",
    "HostComputerId":  "11111111-2222-3333-4444-555555555510",
    "HostUser":  "CONTOSO\\admin01",
    "PSVersion":  "5.1.20348.2000",
    "StartUtc":  "2026-10-15T09:30:00Z",
    "EndUtc":  "2026-10-15T09:30:45Z",
    "RequestedComputers":  [
                               "srv01.contoso.com"
                           ],
    "Types":  [ "System", "RSOP", "ScheduledTask", "SecEdit", "Service", "Firewall", "EventLog" ],
    "ThrottleLimit":  32,
    "UseSSL":  false,
    "SkipDismFeatures":  false,
    "Compress":  true,
    "Archive":  "RemoteBaseline-20261015-093000Z.zip",
    "OutputFormat":  "Both",
    "Collectors":  [
                       {
                           "Type":  "System",
                           "Module":  "RemoteSystem",
                           "Version":  "1.0.0",
                           "RunId":  "RemoteSystem-20261015-093000Z",
                           "DurationMs":  7500,
                           "RowCount":  1,
                           "SuccessCount":  1,
                           "PartialCount":  0,
                           "FailedCount":  0,
                           "Error":  null
                       },
                       ...
                   ],
    "Results":  [
                    {
                        "ComputerName":  "srv01.contoso.com",
                        "ComputerId":  "11111111-2222-3333-4444-555555555501",
                        "Status":  "Success",
                        "Transport":  "WinRM",
                        "OutputFolder":  "C:\\BaselineRuns\\RemoteBaseline-20261015-093000Z\\SRV01_20348_20261015-093000Z",
                        "IsElevated":  true,
                        "Types":  [ "System", "RSOP", "ScheduledTask", "SecEdit", "Service", "Firewall", "EventLog" ],
                        "SystemStatus":  "Success",
                        "RSOPStatus":  "Success",
                        "ScheduledTaskStatus":  "Success",
                        "SecEditStatus":  "Success",
                        "ServiceStatus":  "Success",
                        "FirewallStatus":  "Success",
                        "EventLogStatus":  "Success",
                        "SystemErrorCount":  0,
                        "RSOPErrorCount":  0,
                        "ScheduledTaskErrorCount":  0,
                        "SecEditErrorCount":  0,
                        "ServiceErrorCount":  0,
                        "FirewallErrorCount":  0,
                        "EventLogErrorCount":  0,
                        "Error":  "",
                        "ErrorCount":  0,
                        "Errors":  [

                                   ]
                    }
                ]
}
```

`results.csv` of that run (the `OutputFolder` cell is the host folder, and every cell is quoted):

```
"ComputerName","ComputerId","Status","Transport","OutputFolder","IsElevated","Types","SystemStatus","RSOPStatus","ScheduledTaskStatus","SecEditStatus","ServiceStatus","FirewallStatus","EventLogStatus","SystemErrorCount","RSOPErrorCount","ScheduledTaskErrorCount","SecEditErrorCount","ServiceErrorCount","FirewallErrorCount","EventLogErrorCount","Error","ErrorCount"
"srv01.contoso.com","11111111-2222-3333-4444-555555555501","Success","WinRM","C:\BaselineRuns\RemoteBaseline-20261015-093000Z\SRV01_20348_20261015-093000Z","True","System, RSOP, ScheduledTask, SecEdit, Service, Firewall, EventLog","Success","Success","Success","Success","Success","Success","Success","0","0","0","0","0","0","0","","0"
```

The first lines of `manifest.sha256` of that run, which has 104 lines, one per file (the zip holds those 104 files and `manifest.sha256`, 105 entries). The receiver's check is in What to send back:

```
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  SRV01_20348_20261015-093000Z/RemoteEventLog/accounts.csv
fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210  SRV01_20348_20261015-093000Z/RemoteEventLog/accounts.json
89abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567  SRV01_20348_20261015-093000Z/RemoteEventLog/appcontainers.csv
...
```

Without `-OutputPath` the run folder is created in the current location, and the default `-OutputFormat Json` writes no csv file:

```powershell
PS C:\BaselineRuns> Get-RemoteBaseline -Type Service | Format-Table -Property ComputerName, Status, ServiceStatus
```

The run folder then holds `run.json`, `manifest.sha256`, `collectors\` and one host folder. Add `-OutputFormat Csv` for the csv files of the pairs instead of the json files, or `-OutputFormat Both` for both.

Only the firewall and the services of a list of computers over WinRM HTTPS, with fully qualified names that match the listener certificates:

```powershell
PS C:\> 'SRV01.contoso.com', 'SRV02.contoso.com' | Get-RemoteBaseline -OutputPath C:\BaselineRuns -Type Firewall, Service -UseSSL
```

Two collectors run, in the fixed order Service then Firewall, each once for both computers, with `-UseSSL` and the default `-ThrottleLimit` of 32. The result is one row per name, `Success` when both collectors collected everything and `Partial` or `Failed` otherwise, and one host folder per reached computer with a `RemoteFirewall` and a `RemoteService` subfolder.

Only the computer of a list of servers, without the DISM feature read (no trace in `dism.log` on the targets, about 4 s less per server):

```powershell
PS C:\> 'SRV01.contoso.com', 'SRV02.contoso.com' | Get-RemoteBaseline -OutputPath C:\BaselineRuns -Type System -SkipDismFeatures
```

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
    Collects with any combination of seven collectors that ship inside this module as unchanged
    copies, so nothing else needs to be installed on the collecting computer or on the
    targets: System (RemoteSystem), RSOP (RemoteRSOP), ScheduledTask (RemoteScheduledTask),
    SecEdit (RemoteSecEdit), Service (RemoteService), Firewall (RemoteFirewall) and EventLog
    (RemoteEventLog). Each collector runs once for the whole list of computers, in the fixed
    order System, RSOP, ScheduledTask, SecEdit, Service, Firewall, EventLog, with the
    parameters of this call, and keeps its own WinRM fan-out. Targets are only read, never
    reconfigured. The only files written there are the temporary RemoteSecEdit work folder,
    removed again, and the dism.log of Windows (see -SkipDismFeatures). This module adds no
    action on a target.

    The SID reference (MachineSid, DomainSid, ComputerAccountSid and DomainNetbiosName, output
    convention 1.3) is read once per host and run: the first selected collector in run order
    reads it, and every later one is called with -SkipSidReference, so its system.json holds
    null for the four values. host.json is the place to read them in a bundle run. A host the
    first selected collector did not reach has null there. A bundled collector without the
    switch is called without it. For the values to appear the bundle needs RemoteRSOP 1.3.0,
    RemoteScheduledTask 1.4.1, RemoteSecEdit 1.6.0, RemoteService 1.4.0 and RemoteFirewall
    1.3.0. RemoteSystem and RemoteEventLog have the switch from their first version.

    -SkipDismFeatures is handed to the System collector only, and only when its function has
    the parameter, so a bundled RemoteSystem from before the switch is called without it. No
    other collector reads the DISM feature list.

    Writes <OutputPath>\RemoteBaseline-<yyyyMMdd-HHmmss>Z\ (a _2, _3 suffix on collision)
    containing run.json, manifest.sha256, a collectors folder with the run.json of each
    collector run, and one host folder per reached computer
    (<REPORTED>_<CurrentBuild>_<stamp>Z) with host.json and one subfolder per collector, named
    after the module, holding that collector's computer folder with its files intact. Without
    -OutputPath the run folder is created in the current location. Names of
    one local computer share one host folder. A computer that no selected collector reached
    has no host folder and a Failed row. One that only some reached has the subfolders of
    those collectors. host.json is deliberately not named system.json, so a reader looking for
    computer folders never mistakes a host folder for one.

    -OutputFormat Json, the default, writes the json of each tabular pair and no csv file.
    Csv writes the csv files instead and Both writes both. For this module the pair is the
    results: results.csv in the run folder is written with Csv and Both, and run.json always
    holds the results. The format is passed on to every bundled collector that has the
    parameter, so the collectors' own results.csv and per-computer csv files follow it. A
    bundled collector without the parameter writes both kinds of file, and its files are kept
    as they are. host.json and manifest.sha256 are written whatever the format.

    A text cell of results.csv that starts with = + - or @ is written with one apostrophe in
    front, so a spreadsheet shows it as text and does not run it as a formula. The json files
    hold the exact value.

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
    every Success row Partial. The manifest and the zip are still written over what exists.
    A rename or move of a collector's folder that NTFS refuses is tried three times, 500 ms
    apart, before an arrange: line is written.

.PARAMETER ComputerName
    Targets, as in the collectors: '.', 'localhost', '127.0.0.1', '::1', the local NetBIOS name
    and the local FQDN run in-process without WinRM, everything else goes through WinRM.
    Accepts pipeline input by value and by property name. Duplicates are removed
    case-insensitively and the first-seen order is kept. Defaults to the local computer name.

.PARAMETER Type
    The collectors to run: System, RSOP, ScheduledTask, SecEdit, Service, Firewall, EventLog.
    Defaults to all seven. Duplicates and case differences collapse, and the run order is
    fixed, as listed here, whatever the order given.

.PARAMETER Credential
    Passed to every collector, only when given. The collectors use it for remote targets only.

.PARAMETER UseSSL
    Passed to every collector, only when set: remote targets are contacted over WinRM HTTPS
    (port 5986). Certificate checks are never skipped.

.PARAMETER OutputPath
    Root folder for the run. A value must be given when the parameter is used, and an empty
    value is refused. Leaving the parameter out writes to the current file-system location,
    so a call made from a drive such as HKLM: writes to the last file-system location of the
    session. A given value may be relative. Resolved once against the current location,
    created if missing, and tested for writing before any target is contacted. In Windows
    PowerShell 5.1 the resolved path may be at most 105 characters, because a collection writes
    about 150 characters below it and 5.1 limits a path to 260. A longer path gives a Failed
    row per computer and writes nothing. PowerShell 7 has no such check.

.PARAMETER OutputFormat
    Json, Csv or Both. Defaults to Json. Selects which file of each tabular pair is written:
    the results.csv of this run folder, and in every bundled collector that has the
    parameter its results.csv and its per-computer csv files. Json writes the json files, Csv
    the csv files, Both both. run.json, host.json and manifest.sha256 are written whatever the
    format. A bundled collector without the parameter is called without it and writes both
    kinds of file. Recorded as OutputFormat in run.json.

.PARAMETER ThrottleLimit
    Passed to every collector. From 1 to 256. Defaults to 32.

.PARAMETER SkipDismFeatures
    Passed to the System collector only, which then does not read the DISM feature list: the
    DismState column of its features output stays empty. The read makes Windows append to its
    own dism.log on the target and adds about 4 s per server and 12 to 14 s per Windows 11
    client. The DISM read needs an elevated session. Without elevation, and without
    -SkipDismFeatures, the System row is Partial. Recorded as SkipDismFeatures in run.json.

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
    elevated. Two collectors run, in the order Service then Firewall, and the row carries a
    status for each of them. Both came back Partial because they could not open every item
    without administrative rights, so the umbrella row is Partial too, with the ten error
    lines of the two collectors prefixed Firewall: and Service:.

.EXAMPLE
    PS C:\> 'WS01', 'SRV01.contoso.com' | Get-RemoteBaseline -OutputPath C:\BaselineRuns -UseSSL -Compress

    Runs all seven collectors against two computers over WinRM HTTPS and writes the run folder
    and a zip of it. The names must match the listener certificates, as for any collector.

.EXAMPLE
    PS C:\BaselineRuns> Get-RemoteBaseline -Type Service | Format-Table -Property ComputerName, Status, ServiceStatus

    ComputerName Status  ServiceStatus
    ------------ ------  -------------
    WS01         Success Success

    Without -OutputPath the run folder is created in the current location. The default
    -OutputFormat Json writes no csv file, so the run folder holds run.json, manifest.sha256, the
    collectors folder and the host folder.

.EXAMPLE
    PS C:\> Get-RemoteBaseline -OutputPath C:\BaselineRuns -OutputFormat Both | Select-Object -Property ComputerName, Status

    ComputerName Status
    ------------ ------
    WS01         Success

    Writes the json and the csv file of every pair, so results.csv is written next to
    run.json and every collector writes its csv files next to its json files.

.EXAMPLE
    PS C:\> Get-RemoteBaseline -OutputPath C:\BaselineRuns -Type System -SkipDismFeatures | Select-Object -Property ComputerName, Status, SystemStatus

    ComputerName Status  SystemStatus
    ------------ ------  ------------
    SRV01        Success Success

    Collects the computer without reading the DISM feature list, so nothing is appended to
    dism.log on the target and the run is shorter. The features file is still written, with
    an empty DismState on every row.

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

`Get-RemoteBaseline` is a thin layer over the seven collectors. It collects nothing itself. In order, one call:

1. Resolves `-OutputPath` once against the current location (the current file-system location when it is not given), creates the run folder `RemoteBaseline-<stamp>Z` (and `collectors\` inside it) and proves it can write. A failure here gives one `Failed` row per requested name with the error `output path: <message>`, no files, and the call returns before any target is contacted. On Windows PowerShell 5.1 a resolved path longer than 105 characters fails here too, because the staging layout needs about 150 characters below it and 5.1 limits a path to 260.
2. Reads the identity of the collecting computer for `run.json`.
3. Runs each selected collector once, in the fixed order System, RSOP, ScheduledTask, SecEdit, Service, Firewall, EventLog, for the whole list of computers, with `-OutputPath` set to `collectors\`, the de-duplicated names, `-ThrottleLimit`, `-OutputFormat` when its function has that parameter, `-Credential` and `-UseSSL` only when given, and the collector's own warnings suppressed (their content reaches the caller through the rows). Every collector but the first of the run is also called with `-SkipSidReference`, when its function has that parameter, so the SID reference is read once per host and run. With `-SkipDismFeatures` the System collector, and no other, is also called with `-SkipDismFeatures`, when its function has that parameter. Each collector keeps its own WinRM fan-out. A collector that throws, which is not expected, gives every name a synthetic `Failed` row with the error `host: <message>`. A name a collector returned no row for gets a `Failed` row with `host: no result row returned`. The collector is called from this module's own nested module copy, never by name through your session, so an alias or function of the same name in a profile cannot take its place. The collector's run folder is renamed to `collectors\<Module>`, and only when it sits directly under `collectors\`.
4. Moves every computer folder a row names to `<host folder>\<Module>`, with a single rename on the same volume, so the files are not copied or touched. A computer folder that is not directly inside its collector's run folder is refused, and a rename or move that NTFS refuses is tried three times, 500 ms apart, before it counts as failed. The host folder is `<REPORTED>_<CurrentBuild>_<stamp of the run>Z`, built from the computer folder name by reading its stamp, build and reported name from the right. A name that an earlier collector already placed keeps its host folder, so one host ends in one folder per requested name whatever collectors reached it. A failure adds `arrange: <Module>: <message>` and leaves the folder where it was.
5. Writes `host.json` in every host folder, with the four SID reference values after `MachineGuid` from the first present `system.json`.
6. Builds the result rows, then writes `run.json`, and `results.csv` when `-OutputFormat` is `Csv` or `Both`.
7. Writes `manifest.sha256` and, with `-Compress`, the zip. The manifest hashes every file with `Get-FileHash` and leaves no partial file on a failure. The zip is written with `System.IO.Compression`, with one entry per file in the order of the manifest, forward-slash entry names and no existing file overwritten, and a partial zip is removed.
8. Emits the rows, then one `Write-Warning` per row whose `Status` is not `Success`: `<ComputerName>: <Status>, <ErrorCount> error(s): <Error>`. The warnings come last, so a caller's `-WarningAction Stop` already has the rows and every file.

`Get-RemoteBaseline` never throws once it runs in FullLanguage mode, and the exit code is 0: every failure is a row value, an `Errors` line or a warning. An empty `-ComputerName` list gives one warning and no row. The seven collectors are loaded as nested modules of `RemoteBaseline`, so they resolve to the bundled versions inside it whatever the caller has imported or installed, only `Get-RemoteBaseline` is exported, and removing `RemoteBaseline` leaves the caller's own copies of the collectors as they were. The collectors' files are never read for content except each host's first `system.json`, for `host.json`, and never modified after they were written.

### What to send back

Send the zip `RemoteBaseline-<timestamp>Z.zip`, or the whole `RemoteBaseline-<timestamp>Z` folder, and keep `manifest.sha256` in it. Do not edit any file inside it before sending. The receiver proves that every file is intact and none is missing or added by recomputing the hashes against the manifest. In PowerShell, from the unzipped run folder:

```powershell
$run = 'C:\Path\To\RemoteBaseline-20261015-093000Z'
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

It prints nothing when the run folder is exactly what was hashed. On Linux or macOS, `sha256sum -c manifest.sha256` (or `shasum -a 256 -c manifest.sha256`) from inside the run folder does the first part. The manifest proves the files were not changed after the run. It does not prove who wrote them, and the files are not signed. The `run.json:`, `results.csv:`, `manifest:` and `zip:` lines of the returned rows are not in any file, so a run whose `run.json`, `results.csv`, manifest or zip failed lacks that file, and its rows say why.

## Testing

`tests\Invoke-Tests.ps1` runs `PSScriptAnalyzer` (pinned to 1.25.0) over the module and tests
folder using `PSScriptAnalyzerSettings.psd1`, then runs the Pester suite (pinned to 6.1.0). It exits 1 on any analyzer Error or Warning
result, on any failed test, or when zero tests ran.

The gate needs Pester 6.1.0 and PSScriptAnalyzer 1.25.0 exactly. Windows PowerShell 5.1 ships Pester 3.4, so install both once per engine with `Install-Module Pester -RequiredVersion 6.1.0 -Scope CurrentUser -Force` and `Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser`. Without them the gate exits 1 before any test runs. A few tests that need administrative rights report Inconclusive in an unelevated session, which does not fail the gate. Run the gate once elevated per release to cover them.

Run it under both engines from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-Tests.ps1
pwsh -NoProfile -File tests\Invoke-Tests.ps1
```

Every path inside the test suite is derived from `$PSScriptRoot`, so it also passes from a
relocated copy of the repository, also one below a folder with square brackets or a space in its name.
A folder with square brackets is reached through a junction with a plain name that the gate
creates and removes again, because the module cannot be imported from such a folder (see
Importing the Module). The suite runs the umbrella against a fake of the seven collectors, so the arrangement and the
rows are tested without the bundled copies. The tests that read the bundle itself (the hashes in
`bundle.json`, the nested manifests, the resolver, the release zip) need the bundle to hold all
seven collectors.

## Support and versioning

Versions follow semantic versioning: a patch release changes no output file, column or value. A minor release may add columns, keys or files and may change a value's rule, and the seven bundled collectors make such a change together under one output convention version. A major release would change an existing column or key. Every release is a tagged commit (`v<version>`) and the Version Changes list above is the change log. Report a defect or a question as an issue on the project repository (ProjectUri in the manifest). Report a security concern as described in SECURITY.md. The module is provided under the MIT licence without a support contract. Fixes land in the next release.

## References

- [Get-FileHash - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash)
- [ZipArchive Class - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/system.io.compression.ziparchive)

## License

Tom Stryhn, https://github.com/tomstryhn

Project: https://github.com/tomstryhn/RemoteBaseline

MIT License, see [LICENSE](LICENSE)
