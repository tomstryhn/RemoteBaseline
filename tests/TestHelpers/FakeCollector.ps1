<#PSScriptInfo

.DESCRIPTION A fake of the five bundled collector functions: writes a run folder shaped like the real one and returns rows with the convention's columns

.VERSION 1.0.0

.GUID eb951ac1-be7d-4e47-852b-0e9638a1dd6f

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

<#
The fake stands in for Get-FirewallInventory, Get-RsopInventory, Get-ScheduledTaskInventory, Get-SecEditExport and
Get-ServiceInventory. The umbrella does not call those by name: it takes the FunctionInfo from
Get-RemoteBaselineCollectorCommand, so the tests mock that resolver in the module's own scope with a body that calls
Get-FakeCollectorResolution. That returns, for a module, the FunctionInfo of one of the five wrappers below (one per
type, each with the collectors' common parameters, binding its module name for Invoke-FakeCollector) and the version the
state names. Use-FakeCollectorState hands the fake the state hashtable it reads and writes (a script variable of the
test, because the body of a mock runs in the test scope). The state is a plain hashtable:
  Config   what the fake does, see below
  Calls    one entry per call: Module, ComputerName, OutputPath, ThrottleLimit, Bound (parameter name to value)
  Written  one entry per file the fake wrote, with the SHA-256 it had right after the write, so a test can prove the
           files are intact after the umbrella has moved them
  Versions module name to the version the resolver returns
Config keys, all optional:
  Entries      module name, then requested name, then a hashtable with any of: Mode (Success, Partial, Failed,
               FailedWithFolder, Missing; default Success; FailedWithFolder is a Failed row that carries a full computer
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
The fake always uses the stamp 20200101-000102 in its own folder names, so the umbrella's stamp never equals it.
#>

function Invoke-FakeCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Module,

        [Parameter(Mandatory = $true)]
        $Bound
    )

    Set-StrictMode -Version Latest
    $state = $script:FakeCollectorState
    $config = $state.Config
    $moduleIndex = @('RemoteFirewall', 'RemoteRSOP', 'RemoteScheduledTask', 'RemoteSecEdit', 'RemoteService').IndexOf($Module)

    $values = @{}
    foreach ($key in @($Bound.Keys)) { $values[[string]$key] = $Bound[$key] }
    $names = @($values['ComputerName'])
    $outputPath = [string]$values['OutputPath']
    [void]$state.Calls.Add(@{
            Module        = $Module
            ComputerName  = $names
            OutputPath    = $outputPath
            ThrottleLimit = $values['ThrottleLimit']
            Bound         = $values
        })

    # The body of a mock does not see the -WarningAction the proxy bound, so the fake applies it itself, the way a real collector does.
    if ($config.ContainsKey('Warn') -and @($config.Warn) -contains $Module) {
        $warningAction = 'Continue'
        if ($values.ContainsKey('WarningAction')) { $warningAction = [string]$values['WarningAction'] }
        Write-Warning "collector noise from $Module" -WarningAction $warningAction
    }
    if ($config.ContainsKey('Throw') -and @($config.Throw) -contains $Module) {
        $text = 'collector exploded'
        if ($config.ContainsKey('ThrowMessage')) { $text = [string]$config.ThrowMessage }
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
    [void](New-Item -Path $runFolder -ItemType Directory -ErrorAction Stop)
    $runId = Split-Path -Path $runFolder -Leaf

    # A misbehaving collector's computer folders: a run folder of the same name in a sibling of the run's own folder, two levels above the staging folder, which is under OutputPath but not under the staging folder.
    $outsideRunFolder = Join-Path -Path (Join-Path -Path (Split-Path -Path (Split-Path -Path $outputPath -Parent) -Parent) -ChildPath 'outside') -ChildPath $runLeaf

    $write = {
        param([string]$Path, [string]$Text, [bool]$Bom, [string]$Kind, [string]$Folder, [string[]]$Name)
        $bytes = $encoding.GetBytes($Text)
        if ($Bom) { $bytes = [byte[]]@(0xEF, 0xBB, 0xBF) + $bytes }
        [System.IO.File]::WriteAllBytes($Path, $bytes)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
        [void]$state.Written.Add(@{ Module = $Module; Kind = $Kind; Folder = $Folder; Name = $Name; File = (Split-Path -Path $Path -Leaf); Sha256 = $hash })
    }

    $entries = @{}
    if ($config.ContainsKey('Entries') -and $config.Entries.ContainsKey($Module)) { $entries = $config.Entries[$Module] }
    $folderByReported = @{}
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($name in $names) {
        $entry = @{}
        if ($entries.ContainsKey($name)) { $entry = $entries[$name] }
        $mode = 'Success'
        if ($entry.ContainsKey('Mode')) { $mode = [string]$entry.Mode }
        if ($mode -eq 'Missing') { continue }
        $reported = $name
        if ($entry.ContainsKey('Reported')) { $reported = [string]$entry.Reported }
        $build = '20348'
        if ($entry.ContainsKey('Build')) { $build = [string]$entry.Build }
        $transport = 'WinRM'
        if ($entry.ContainsKey('Transport')) { $transport = [string]$entry.Transport }
        $elevated = $true
        if ($entry.ContainsKey('Elevated')) { $elevated = [bool]$entry.Elevated }
        $errorList = [string[]]@()
        if ($entry.ContainsKey('Errors')) { $errorList = [string[]]@($entry.Errors) }
        $idBytes = [System.Security.Cryptography.MD5]::Create().ComputeHash($encoding.GetBytes($reported.ToLowerInvariant()))
        $computerId = ([guid]::new($idBytes)).ToString().ToUpperInvariant()

        # The status the collector's row carries: FailedWithFolder is a Failed row.
        $status = $mode
        if ($mode -eq 'FailedWithFolder') { $status = 'Failed' }

        $folder = ''
        if ($mode -in @('Success', 'Partial', 'FailedWithFolder')) {
            $alias = $entry.ContainsKey('Alias') -and [bool]$entry.Alias -and $folderByReported.ContainsKey($reported)
            if ($alias) {
                $folder = $folderByReported[$reported]
                foreach ($record in $state.Written) {
                    if ($record.Module -eq $Module -and $record.Folder -eq $folder) { $record.Name = @($record.Name) + $name }
                }
            } else {
                $safe = ($reported.ToUpperInvariant() -replace '[^A-Za-z0-9_-]', '_')
                $leaf = "${safe}_${build}_${stamp}Z"
                if ($entry.ContainsKey('FolderName')) { $leaf = [string]$entry.FolderName }
                $parentFolder = $runFolder
                if ($entry.ContainsKey('Outside') -and [bool]$entry.Outside) { $parentFolder = $outsideRunFolder }
                $folder = Join-Path -Path $parentFolder -ChildPath $leaf
                $suffix = 1
                while (Test-Path -LiteralPath $folder) {
                    $suffix++
                    $folder = Join-Path -Path $parentFolder -ChildPath ($leaf + '_' + $suffix)
                }
                [void](New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop)
                $folderByReported[$reported] = $folder

                $system = [ordered]@{
                    ComputerName = $reported.ToUpperInvariant(); DnsHostName = $reported.ToLowerInvariant() + '.contoso.example'; Domain = 'contoso.example'
                    OSCaption = 'Microsoft Windows Server 2022 Standard'; OSVersion = '10.0.20348'; CurrentBuild = $build
                    UBR = (5000 + $moduleIndex); DisplayVersion = '21H2'; EditionID = 'ServerStandard'; InstallationType = 'Server'
                    Culture = 'en-US'; TimeZoneId = 'UTC'; PSVersion = '5.1.20348.2110'; CollectedBy = 'CONTOSO\collector'
                    PartOfDomain = $true; IsElevated = $elevated; DomainRole = 3; CollectedUtc = '2020-01-01T00:01:02Z'
                    ComputerId = $computerId; MachineGuid = ($computerId.ToLowerInvariant()); Collector = $Module; CollectorVersion = '0.0.1'; RunId = $runId
                    Errors = $errorList; Transport = $transport; RequestedComputerName = $name; Status = $status
                }
                $systemText = [pscustomobject]$system | ConvertTo-Json -Depth 4
                if ($entry.ContainsKey('BadSystemJson') -and [bool]$entry.BadSystemJson) { $systemText = '{ this is not json' }
                & $write (Join-Path -Path $folder -ChildPath 'system.json') $systemText $false 'computer' $folder @($name)
                & $write (Join-Path -Path $folder -ChildPath 'subject.json') ('{"Module":"' + $Module + '","Name":"' + $reported + '","Payload":"abc 123"}') $false 'computer' $folder @($name)
            }
        }

        # A Failed row that has a folder still knows its computer (id, elevation); one that never reached the target does not.
        $unreached = $mode -eq 'Failed'
        $failedRow = $status -eq 'Failed'
        if ($failedRow -and $errorList.Count -eq 0) { $errorList = [string[]]@('WinRM cannot complete the operation.') }
        $firstError = ''
        if ($errorList.Count -gt 0) { $firstError = $errorList[0] }
        $accountCount = $null
        $accountUnresolved = $null
        if (-not $failedRow) { $accountCount = 3; $accountUnresolved = 0 }
        [void]$rows.Add([pscustomobject][ordered]@{
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
    & $write (Join-Path -Path $runFolder -ChildPath 'results.csv') '"ComputerName","Status"' $true 'run' $runFolder @()

    if ($config.ContainsKey('BlockRename') -and @($config.BlockRename) -contains $Module) {
        [System.IO.File]::WriteAllText((Join-Path -Path $outputPath -ChildPath $Module), 'in the way')
    }
    if ($config.ContainsKey('BlockZip') -and [bool]$config.BlockZip) {
        [System.IO.File]::WriteAllText(((Split-Path -Path $outputPath -Parent) + '.zip'), 'not a zip')
    }

    $rows.ToArray()
}

function Use-FakeCollectorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    # A mock of a command that lives in a nested module runs its body in the session state of the test (Pester cannot
    # find the nested module by name), so the state is a script variable of the test, where Invoke-FakeCollector reads it.
    $script:FakeCollectorState = $State
}
function Get-FakeCollectorState {
    [CmdletBinding()]
    param(
        [hashtable]$Config = @{},
        [hashtable]$Version = @{}
    )

    return @{
        Config   = $Config
        Calls    = [System.Collections.Generic.List[object]]::new()
        Written  = [System.Collections.Generic.List[object]]::new()
        Versions = $Version
    }
}

# One wrapper per collector function, with the common parameter set the five share. The umbrella calls the FunctionInfo of
# one of these (through the mocked resolver), so the module name is bound here and the parameters the umbrella passes bind
# for real: a parameter the collectors do not have would fail the call, as it would on a real collector.
function Invoke-FakeFirewallCollector {
    [CmdletBinding()]
    param([string[]]$ComputerName, [string]$OutputPath, [int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteFirewall' -Bound $PSBoundParameters
}
function Invoke-FakeRsopCollector {
    [CmdletBinding()]
    param([string[]]$ComputerName, [string]$OutputPath, [int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteRSOP' -Bound $PSBoundParameters
}
function Invoke-FakeScheduledTaskCollector {
    [CmdletBinding()]
    param([string[]]$ComputerName, [string]$OutputPath, [int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteScheduledTask' -Bound $PSBoundParameters
}
function Invoke-FakeSecEditCollector {
    [CmdletBinding()]
    param([string[]]$ComputerName, [string]$OutputPath, [int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteSecEdit' -Bound $PSBoundParameters
}
function Invoke-FakeServiceCollector {
    [CmdletBinding()]
    param([string[]]$ComputerName, [string]$OutputPath, [int]$ThrottleLimit, [System.Management.Automation.PSCredential]$Credential, [switch]$UseSSL)
    Invoke-FakeCollector -Module 'RemoteService' -Bound $PSBoundParameters
}

# The body of the mocked resolver: what Get-RemoteBaselineCollectorCommand returns for a module, or its throw.
function Get-FakeCollectorResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Module
    )

    $state = $script:FakeCollectorState
    if ($state.Config.ContainsKey('NotBundled') -and @($state.Config.NotBundled) -contains $Module) {
        throw "collector $Module not bundled"
    }
    $wrapper = @{
        RemoteFirewall      = 'Invoke-FakeFirewallCollector'
        RemoteRSOP          = 'Invoke-FakeRsopCollector'
        RemoteScheduledTask = 'Invoke-FakeScheduledTaskCollector'
        RemoteSecEdit       = 'Invoke-FakeSecEditCollector'
        RemoteService       = 'Invoke-FakeServiceCollector'
    }[$Module]
    $version = '0.0.1'
    if ($state.Versions.ContainsKey($Module)) { $version = [string]$state.Versions[$Module] }
    return [pscustomobject]@{ Command = (Get-Command -Name $wrapper -CommandType Function); Version = $version }
}

function Get-FakeTypeCase {
    [CmdletBinding()]
    param()

    return @(
        @{ Type = 'Firewall'; Module = 'RemoteFirewall'; Function = 'Get-FirewallInventory' }
        @{ Type = 'RSOP'; Module = 'RemoteRSOP'; Function = 'Get-RsopInventory' }
        @{ Type = 'ScheduledTask'; Module = 'RemoteScheduledTask'; Function = 'Get-ScheduledTaskInventory' }
        @{ Type = 'SecEdit'; Module = 'RemoteSecEdit'; Function = 'Get-SecEditExport' }
        @{ Type = 'Service'; Module = 'RemoteService'; Function = 'Get-ServiceInventory' }
    )
}
