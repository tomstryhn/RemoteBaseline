<#PSScriptInfo

.DESCRIPTION A fake of the seven bundled collector functions: writes a run folder shaped like the real one and returns rows with the columns the collectors write

.VERSION 1.4.0

.GUID eb951ac1-be7d-4e47-852b-0e9638a1dd6f

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

<#
The fake stands in for Get-SystemInventory, Get-RsopInventory, Get-ScheduledTaskInventory, Get-SecEditExport,
Get-ServiceInventory, Get-FirewallInventory and Get-EventLogInventory. The umbrella does not call those by name: it
takes the FunctionInfo from Get-RemoteBaselineCollectorCommand, so the tests mock that resolver in the module's own
scope with a body that calls Get-FakeCollectorResolution. That returns, for a module, the FunctionInfo of one of the
seven wrappers below (one per type, each with the collectors' common parameters, binding its module name for
Invoke-FakeCollector) and the version the state names. None of the bundled copies on disk is needed, so the suite
runs the same before and after the bundle is rebuilt. Use-FakeCollectorState hands the fake the state hashtable it
reads and writes (a script variable of the test, because the body of a mock runs in the test scope). The state is a
plain hashtable:
  Config   what the fake does, see below
  Calls    one entry per call: Module, ComputerName, OutputPath, ThrottleLimit, Bound (parameter name to value)
  Written  one entry per file the fake wrote, with the SHA-256 it had right after the write, so a test can prove the
           files are intact after the umbrella has moved them
  Versions module name to the version the resolver returns
Config keys, all optional:
  Entries      module name, then requested name, then a hashtable with any of: Mode (Success, Partial, Failed,
               FailedWithFolder, Missing. Default Success. FailedWithFolder is a Failed row that carries a full computer
               folder, as the real RSOP and SecEdit collectors write when not elevated), Reported (the name the target
               reports, default the requested name), Build (default 20348), Errors (string[] for Partial and Failed),
               Alias (share the computer folder of an earlier name with the same Reported, the way local aliases do),
               FolderName (a computer folder leaf to use as it is), BadSystemJson (write a system.json that is not
               json), Elevated (default true), Transport (default WinRM), Outside (put the computer folder, and the
               collector run folder it sits in, outside the staging folder, as a misbehaving collector could report)
  Throw        module names whose function throws, with ThrowMessage as the text
  NotBundled   module names the resolver does not find (it throws, as the real one does)
  Warn         module names whose function writes a warning
  BlockRename  module names that get a file where the umbrella will rename the collector's run folder to
  BlockZip     true: a file is put where the umbrella's zip will go
  WithoutSkipSidReference
               module names whose wrapper lacks the -SkipSidReference parameter, as a collector from before output
               convention 1.3 does. Such a collector also writes no SID reference keys in system.json. Every other
               collector accepts the switch and writes the four keys in system.json (MachineSid, DomainSid,
               ComputerAccountSid, DomainNetbiosName, after MachineGuid): values when not skipped, null when skipped
  WithoutOutputFormat
               module names whose wrapper lacks the -OutputFormat parameter, as a collector from before output
               convention 1.4 does (it keeps the SID switch). Such a collector writes results.csv whatever the
               umbrella asks for. Every other collector writes results.csv only when the format it was given is Csv
               or Both, and none when it is Json. A module in WithoutSkipSidReference lacks both parameters.
The fake always uses the stamp 20200101-000102 in its own folder names, so the umbrella's stamp never equals it.
#>

#region Invoke-FakeCollector
function Invoke-FakeCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String]$Module,

        [Parameter(Mandatory = $true)]
        $Bound
    )

    Set-StrictMode -Version Latest
    $state = $script:FakeCollectorState
    $config = $state.Config
    # The index is the module's place in the run order, so UBR in system.json tells which collector it came from.
    $moduleIndex = @('RemoteSystem', 'RemoteRSOP', 'RemoteScheduledTask', 'RemoteSecEdit', 'RemoteService', 'RemoteFirewall', 'RemoteEventLog').IndexOf($Module)

    $values = @{}
    foreach ($key in @($Bound.Keys)) {
        $values[[String]$key] = $Bound[$key]
    }
    $names = @($values['ComputerName'])
    $outputPath = [String]$values['OutputPath']
    # Whether this collector was told to leave the SID reference unread, and whether it is a pre-1.3 collector
    # (a wrapper without the parameter).
    $skipSid = $values.ContainsKey('SkipSidReference') -and [Bool]$values['SkipSidReference']
    $legacy = $config.ContainsKey('WithoutSkipSidReference') -and @($config.WithoutSkipSidReference) -contains $Module
    # Whether this collector writes results.csv: one without the format parameter always does, as the
    # collectors did before it existed. One with it follows the value it was given, Json when none was bound.
    $withoutFormat = $legacy -or ($config.ContainsKey('WithoutOutputFormat') -and @($config.WithoutOutputFormat) -contains $Module)
    $format = 'Json'
    if ($values.ContainsKey('OutputFormat')) {
        $format = [String]$values['OutputFormat']
    }
    $writeResultsCsv = $withoutFormat -or $format -ne 'Json'
    [Void]$state.Calls.Add(@{
            Module        = $Module
            ComputerName  = $names
            OutputPath    = $outputPath
            ThrottleLimit = $values['ThrottleLimit']
            Bound         = $values
        })

    # The body of a mock does not see the -WarningAction the proxy bound, so the fake applies it itself, the
    # way a real collector does.
    if ($config.ContainsKey('Warn') -and @($config.Warn) -contains $Module) {
        $warningAction = 'Continue'
        if ($values.ContainsKey('WarningAction')) {
            $warningAction = [String]$values['WarningAction']
        }
        Write-Warning "collector noise from $Module" -WarningAction $warningAction
    }
    if ($config.ContainsKey('Throw') -and @($config.Throw) -contains $Module) {
        $text = 'collector exploded'
        if ($config.ContainsKey('ThrowMessage')) {
            $text = [String]$config.ThrowMessage
        }
        throw $text
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stamp = '20200101-000102'
    $runLeaf = "$Module-${stamp}Z"
    $runFolder = Join-Path -Path $outputPath -ChildPath $runLeaf
    $suffix = 1
    while (Test-Path -LiteralPath $runFolder) {
        $suffix++
        $runFolder = Join-Path -Path $outputPath -ChildPath ($runLeaf + '_' + $suffix)
    }
    [Void](New-Item -Path $runFolder -ItemType Directory -ErrorAction Stop)
    $runId = Split-Path -Path $runFolder -Leaf

    # A misbehaving collector's computer folders: a run folder of the same name in a sibling of the run's own
    # folder, two levels above the staging folder, which is under OutputPath but not under the staging folder.
    $outsideRunFolder = Join-Path -Path (Join-Path -Path (Split-Path -Path (Split-Path -Path $outputPath -Parent) -Parent) -ChildPath 'outside') -ChildPath $runLeaf

    $write = {
        param([String]$Path, [String]$Text, [Bool]$Bom, [String]$Kind, [String]$Folder, [String[]]$Name)
        $bytes = $encoding.GetBytes($Text)
        if ($Bom) {
            $bytes = [Byte[]]@(0xEF, 0xBB, 0xBF) + $bytes
        }
        [System.IO.File]::WriteAllBytes($Path, $bytes)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
        [Void]$state.Written.Add(@{ Module = $Module; Kind = $Kind; Folder = $Folder; Name = $Name; File = (Split-Path -Path $Path -Leaf); Sha256 = $hash })
    }

    $entries = @{}
    if ($config.ContainsKey('Entries') -and $config.Entries.ContainsKey($Module)) {
        $entries = $config.Entries[$Module]
    }
    $folderByReported = @{}
    $rows = [System.Collections.Generic.List[Object]]::new()

    foreach ($name in $names) {
        $entry = @{}
        if ($entries.ContainsKey($name)) {
            $entry = $entries[$name]
        }
        $mode = 'Success'
        if ($entry.ContainsKey('Mode')) {
            $mode = [String]$entry.Mode
        }
        if ($mode -eq 'Missing') {
            continue
        }
        $reported = $name
        if ($entry.ContainsKey('Reported')) {
            $reported = [String]$entry.Reported
        }
        $build = '20348'
        if ($entry.ContainsKey('Build')) {
            $build = [String]$entry.Build
        }
        $transport = 'WinRM'
        if ($entry.ContainsKey('Transport')) {
            $transport = [String]$entry.Transport
        }
        $elevated = $true
        if ($entry.ContainsKey('Elevated')) {
            $elevated = [Bool]$entry.Elevated
        }
        $errorList = [String[]]@()
        if ($entry.ContainsKey('Errors')) {
            $errorList = [String[]]@($entry.Errors)
        }
        $idBytes = [System.Security.Cryptography.MD5]::Create().ComputeHash($encoding.GetBytes($reported.ToLowerInvariant()))
        $computerId = ([Guid]::new($idBytes)).ToString().ToUpperInvariant()

        # The status the collector's row carries: FailedWithFolder is a Failed row.
        $status = $mode
        if ($mode -eq 'FailedWithFolder') {
            $status = 'Failed'
        }

        $folder = ''
        if ($mode -in @('Success', 'Partial', 'FailedWithFolder')) {
            $alias = $entry.ContainsKey('Alias') -and [Bool]$entry.Alias -and $folderByReported.ContainsKey($reported)
            if ($alias) {
                $folder = $folderByReported[$reported]
                foreach ($record in $state.Written) {
                    if ($record.Module -eq $Module -and $record.Folder -eq $folder) {
                        $record.Name = @($record.Name) + $name
                    }
                }
            }
            else {
                $safe = ($reported.ToUpperInvariant() -replace '[^A-Za-z0-9_-]', '_')
                $leaf = "${safe}_${build}_${stamp}Z"
                if ($entry.ContainsKey('FolderName')) {
                    $leaf = [String]$entry.FolderName
                }
                $parentFolder = $runFolder
                if ($entry.ContainsKey('Outside') -and [Bool]$entry.Outside) {
                    $parentFolder = $outsideRunFolder
                }
                $folder = Join-Path -Path $parentFolder -ChildPath $leaf
                $suffix = 1
                while (Test-Path -LiteralPath $folder) {
                    $suffix++
                    $folder = Join-Path -Path $parentFolder -ChildPath ($leaf + '_' + $suffix)
                }
                [Void](New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop)
                $folderByReported[$reported] = $folder

                $system = [ordered]@{
                    ComputerName = $reported.ToUpperInvariant(); DnsHostName = $reported.ToLowerInvariant() + '.contoso.example'; Domain = 'contoso.example'
                    OSCaption = 'Microsoft Windows Server 2022 Standard'; OSVersion = '10.0.20348'; CurrentBuild = $build
                    UBR = (5000 + $moduleIndex); DisplayVersion = '21H2'; EditionID = 'ServerStandard'; InstallationType = 'Server'
                    Culture = 'en-US'; TimeZoneId = 'UTC'; PSVersion = '5.1.20348.2110'; CollectedBy = 'CONTOSO\collector'
                    PartOfDomain = $true; IsElevated = $elevated; DomainRole = 3; CollectedUtc = '2020-01-01T00:01:02Z'
                    ComputerId = $computerId; MachineGuid = ($computerId.ToLowerInvariant())
                }
                # The SID reference sits directly after MachineGuid, as in output convention 1.3. A collector
                # without the switch is a pre-1.3 one and writes no such keys. One that was told to skip
                # writes them as null.
                if (-not $legacy) {
                    $machineSid = $null
                    $domainSid = $null
                    $computerAccountSid = $null
                    $domainNetbiosName = $null
                    if (-not $skipSid) {
                        $machineSid = 'S-1-5-21-{0}-{1}-{2}' -f [System.BitConverter]::ToUInt32($idBytes, 0), [System.BitConverter]::ToUInt32($idBytes, 4), [System.BitConverter]::ToUInt32($idBytes, 8)
                        $domainSid = 'S-1-5-21-1111111111-2222222222-3333333333'
                        $computerAccountSid = $domainSid + '-1105'
                        $domainNetbiosName = 'CONTOSO'
                    }
                    $system['MachineSid'] = $machineSid
                    $system['DomainSid'] = $domainSid
                    $system['ComputerAccountSid'] = $computerAccountSid
                    $system['DomainNetbiosName'] = $domainNetbiosName
                }
                $system['Collector'] = $Module
                $system['CollectorVersion'] = '0.0.1'
                $system['RunId'] = $runId
                $system['Errors'] = $errorList
                $system['Transport'] = $transport
                $system['RequestedComputerName'] = $name
                $system['Status'] = $status
                $systemText = [PSCustomObject]$system | ConvertTo-Json -Depth 4
                if ($entry.ContainsKey('BadSystemJson') -and [Bool]$entry.BadSystemJson) {
                    $systemText = '{ this is not json'
                }
                & $write (Join-Path -Path $folder -ChildPath 'system.json') $systemText $false 'computer' $folder @($name)
                & $write (Join-Path -Path $folder -ChildPath 'subject.json') ('{"Module":"' + $Module + '","Name":"' + $reported + '","Payload":"abc 123"}') $false 'computer' $folder @($name)
            }
        }

        # A Failed row that has a folder still knows its computer (id, elevation). One that never reached the
        # target does not.
        $unreached = $mode -eq 'Failed'
        $failedRow = $status -eq 'Failed'
        if ($failedRow -and $errorList.Count -eq 0) {
            $errorList = [String[]]@('WinRM cannot complete the operation.')
        }
        $firstError = ''
        if ($errorList.Count -gt 0) {
            $firstError = $errorList[0]
        }
        $accountCount = $null
        $accountUnresolved = $null
        if (-not $failedRow) {
            $accountCount = 3
            $accountUnresolved = 0
        }
        [Void]$rows.Add([PSCustomObject][ordered]@{
                ComputerName           = $name
                ComputerId             = $(if ($unreached) { $null } else { $computerId })
                Status                 = $status
                Transport              = $transport
                OutputFolder           = $folder
                IsElevated             = $(if ($unreached) { $null } else { $elevated })
                AccountCount           = $accountCount
                AccountUnresolvedCount = $accountUnresolved
                Error                  = $firstError
                ErrorCount             = $errorList.Count
                Errors                 = $errorList
            })
    }

    & $write (Join-Path -Path $runFolder -ChildPath 'run.json') ('{"Collector":"' + $Module + '","RunId":"' + $runId + '","Results":[]}') $false 'run' $runFolder @()
    if ($writeResultsCsv) {
        & $write (Join-Path -Path $runFolder -ChildPath 'results.csv') '"ComputerName","Status"' $true 'run' $runFolder @()
    }

    if ($config.ContainsKey('BlockRename') -and @($config.BlockRename) -contains $Module) {
        [System.IO.File]::WriteAllText((Join-Path -Path $outputPath -ChildPath $Module), 'in the way')
    }
    if ($config.ContainsKey('BlockZip') -and [Bool]$config.BlockZip) {
        [System.IO.File]::WriteAllText(((Split-Path -Path $outputPath -Parent) + '.zip'), 'not a zip')
    }

    $rows.ToArray()
}
#endregion

#region Use-FakeCollectorState
function Use-FakeCollectorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Hashtable]$State
    )

    # A mock of a command that lives in a nested module runs its body in the session state of the test (Pester cannot
    # find the nested module by name), so the state is a script variable of the test, where
    # Invoke-FakeCollector reads it.
    $script:FakeCollectorState = $State
}
#endregion
#region Get-FakeCollectorState
function Get-FakeCollectorState {
    [CmdletBinding()]
    param(
        [Hashtable]$Config = @{},
        [Hashtable]$Version = @{}
    )

    return @{
        Config   = $Config
        Calls    = [System.Collections.Generic.List[Object]]::new()
        Written  = [System.Collections.Generic.List[Object]]::new()
        Versions = $Version
    }
}
#endregion

#region Invoke-FakeFirewallCollector
# One wrapper per collector function, with the common parameter set the seven share, and -SkipDismFeatures on
# the System one only, as in the real collectors. The umbrella calls the
# FunctionInfo of
# one of these (through the mocked resolver), so the module name is bound here and the parameters the umbrella
# passes bind
# for real: a parameter the collectors do not have would fail the call, as it would on a real collector.
function Invoke-FakeFirewallCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference, [ValidateSet('Json', 'Csv', 'Both')][String]$OutputFormat)
    Invoke-FakeCollector -Module 'RemoteFirewall' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeRsopCollector
function Invoke-FakeRsopCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference, [ValidateSet('Json', 'Csv', 'Both')][String]$OutputFormat)
    Invoke-FakeCollector -Module 'RemoteRSOP' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeScheduledTaskCollector
function Invoke-FakeScheduledTaskCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference, [ValidateSet('Json', 'Csv', 'Both')][String]$OutputFormat)
    Invoke-FakeCollector -Module 'RemoteScheduledTask' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeSecEditCollector
function Invoke-FakeSecEditCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference, [ValidateSet('Json', 'Csv', 'Both')][String]$OutputFormat)
    Invoke-FakeCollector -Module 'RemoteSecEdit' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeServiceCollector
function Invoke-FakeServiceCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference, [ValidateSet('Json', 'Csv', 'Both')][String]$OutputFormat)
    Invoke-FakeCollector -Module 'RemoteService' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeSystemCollector
function Invoke-FakeSystemCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference, [Switch]$SkipDismFeatures, [ValidateSet('Json', 'Csv', 'Both')][String]$OutputFormat)
    Invoke-FakeCollector -Module 'RemoteSystem' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeEventLogCollector
function Invoke-FakeEventLogCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference, [ValidateSet('Json', 'Csv', 'Both')][String]$OutputFormat)
    Invoke-FakeCollector -Module 'RemoteEventLog' -Bound $PSBoundParameters
}
#endregion

#region Invoke-FakeUnformattedFirewallCollector
# The same seven without -OutputFormat: a bundled collector from before output convention 1.4, which has the
# SID switch and writes both kinds of file. The resolver returns these for the modules named in
# Config.WithoutOutputFormat, so a call with the parameter would fail to bind.
function Invoke-FakeUnformattedFirewallCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference)
    Invoke-FakeCollector -Module 'RemoteFirewall' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeUnformattedRsopCollector
function Invoke-FakeUnformattedRsopCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference)
    Invoke-FakeCollector -Module 'RemoteRSOP' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeUnformattedScheduledTaskCollector
function Invoke-FakeUnformattedScheduledTaskCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference)
    Invoke-FakeCollector -Module 'RemoteScheduledTask' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeUnformattedSecEditCollector
function Invoke-FakeUnformattedSecEditCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference)
    Invoke-FakeCollector -Module 'RemoteSecEdit' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeUnformattedServiceCollector
function Invoke-FakeUnformattedServiceCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference)
    Invoke-FakeCollector -Module 'RemoteService' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeUnformattedSystemCollector
function Invoke-FakeUnformattedSystemCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference)
    Invoke-FakeCollector -Module 'RemoteSystem' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeUnformattedEventLogCollector
function Invoke-FakeUnformattedEventLogCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL, [Switch]$SkipSidReference)
    Invoke-FakeCollector -Module 'RemoteEventLog' -Bound $PSBoundParameters
}
#endregion

#region Invoke-FakeLegacyFirewallCollector
# The same seven without -SkipSidReference and without -OutputFormat: a bundled collector from before output
# convention 1.3. The resolver returns these for the modules named in Config.WithoutSkipSidReference, so a call
# with either parameter would fail to bind.
function Invoke-FakeLegacyFirewallCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteFirewall' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeLegacyRsopCollector
function Invoke-FakeLegacyRsopCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteRSOP' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeLegacyScheduledTaskCollector
function Invoke-FakeLegacyScheduledTaskCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteScheduledTask' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeLegacySecEditCollector
function Invoke-FakeLegacySecEditCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteSecEdit' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeLegacyServiceCollector
function Invoke-FakeLegacyServiceCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteService' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeLegacySystemCollector
function Invoke-FakeLegacySystemCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteSystem' -Bound $PSBoundParameters
}
#endregion
#region Invoke-FakeLegacyEventLogCollector
function Invoke-FakeLegacyEventLogCollector {
    [CmdletBinding()]
    param([String[]]$ComputerName, [String]$OutputPath, [Int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [Switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteEventLog' -Bound $PSBoundParameters
}
#endregion

#region Get-FakeCollectorResolution
# The body of the mocked resolver: what Get-RemoteBaselineCollectorCommand returns for a module, or its throw.
function Get-FakeCollectorResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String]$Module
    )

    $state = $script:FakeCollectorState
    if ($state.Config.ContainsKey('NotBundled') -and @($state.Config.NotBundled) -contains $Module) {
        throw "collector $Module not bundled"
    }
    $wrapper = @{
        RemoteSystem        = 'Invoke-FakeSystemCollector'
        RemoteRSOP          = 'Invoke-FakeRsopCollector'
        RemoteScheduledTask = 'Invoke-FakeScheduledTaskCollector'
        RemoteSecEdit       = 'Invoke-FakeSecEditCollector'
        RemoteService       = 'Invoke-FakeServiceCollector'
        RemoteFirewall      = 'Invoke-FakeFirewallCollector'
        RemoteEventLog      = 'Invoke-FakeEventLogCollector'
    }[$Module]
    # A collector from before convention 1.3 has neither parameter, one from before 1.4 lacks only the format.
    if ($state.Config.ContainsKey('WithoutSkipSidReference') -and @($state.Config.WithoutSkipSidReference) -contains $Module) {
        $wrapper = $wrapper.Replace('Invoke-Fake', 'Invoke-FakeLegacy')
    }
    elseif ($state.Config.ContainsKey('WithoutOutputFormat') -and @($state.Config.WithoutOutputFormat) -contains $Module) {
        $wrapper = $wrapper.Replace('Invoke-Fake', 'Invoke-FakeUnformatted')
    }
    $version = '0.0.1'
    if ($state.Versions.ContainsKey($Module)) {
        $version = [String]$state.Versions[$Module]
    }
    return [PSCustomObject]@{ Command = (Get-Command -Name $wrapper -CommandType Function); Version = $version }
}
#endregion

#region Get-FakeTypeCase
function Get-FakeTypeCase {
    [CmdletBinding()]
    param()

    # In run order.
    return @(
        @{ Type = 'System'; Module = 'RemoteSystem'; Function = 'Get-SystemInventory' }
        @{ Type = 'RSOP'; Module = 'RemoteRSOP'; Function = 'Get-RsopInventory' }
        @{ Type = 'ScheduledTask'; Module = 'RemoteScheduledTask'; Function = 'Get-ScheduledTaskInventory' }
        @{ Type = 'SecEdit'; Module = 'RemoteSecEdit'; Function = 'Get-SecEditExport' }
        @{ Type = 'Service'; Module = 'RemoteService'; Function = 'Get-ServiceInventory' }
        @{ Type = 'Firewall'; Module = 'RemoteFirewall'; Function = 'Get-FirewallInventory' }
        @{ Type = 'EventLog'; Module = 'RemoteEventLog'; Function = 'Get-EventLogInventory' }
    )
}
#endregion
