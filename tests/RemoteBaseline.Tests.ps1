<#PSScriptInfo

.DESCRIPTION Pester tests for the RemoteBaseline module

.VERSION 1.0.0

.GUID 12be8faa-73f6-4bc1-a25d-e733c0e74ff5

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

<#
Pester tests for the RemoteBaseline module (Pester 6): the proof of docs\DESIGN.md sections 3 to 10 and 13. The module
reaches a collector only through Get-RemoteBaselineCollectorCommand, which is mocked in module scope with
tests\TestHelpers\FakeCollector.ps1: a fake that writes a run folder shaped like a real one and returns rows with the
convention's columns. The bundled collectors are not run here (their repositories carry their tests); this suite proves the
bundle is the released files and resolves from inside the module, and that no alias or function of the caller's session
can take the place of a bundled collector. Start-Sleep is mocked in module scope for every fake run, so the retry of
section 13.6 never waits here. Paths derive from $PSScriptRoot.
#>

# Discovery phase: -ForEach data is bound here, before any BeforeAll runs.
. (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers\FakeCollector.ps1')
$TypeCases = Get-FakeTypeCase
$StatusCases = @(
    @{ Name = 'every selected collector Success and no extra line'; S = @('Success', 'Success', 'Success', 'Success', 'Success'); Extra = @(); Expected = 'Success' }
    @{ Name = 'every collector Success and an arrange line'; S = @('Success', 'Success', 'Success', 'Success', 'Success'); Extra = @('arrange: RemoteRSOP: x'); Expected = 'Partial' }
    @{ Name = 'every collector Success and a host.json line'; S = @('Success', 'Success', 'Success', 'Success', 'Success'); Extra = @('host.json: x'); Expected = 'Partial' }
    @{ Name = 'every collector Success and a manifest line'; S = @('Success', 'Success', 'Success', 'Success', 'Success'); Extra = @('manifest: x'); Expected = 'Partial' }
    @{ Name = 'every collector Success and a zip line'; S = @('Success', 'Success', 'Success', 'Success', 'Success'); Extra = @('zip: x'); Expected = 'Partial' }
    @{ Name = 'one collector Partial, the rest Success'; S = @('Success', 'Partial', 'Success', 'Success', 'Success'); Extra = @(); Expected = 'Partial' }
    @{ Name = 'every collector Partial'; S = @('Partial', 'Partial', 'Partial', 'Partial', 'Partial'); Extra = @(); Expected = 'Partial' }
    @{ Name = 'one collector Failed, the rest Success'; S = @('Success', 'Success', 'Failed', 'Success', 'Success'); Extra = @(); Expected = 'Partial' }
    @{ Name = 'one Failed, one Partial and the rest Failed'; S = @('Failed', 'Failed', 'Partial', 'Failed', 'Failed'); Extra = @(); Expected = 'Partial' }
    @{ Name = 'every collector Failed'; S = @('Failed', 'Failed', 'Failed', 'Failed', 'Failed'); Extra = @(); Expected = 'Failed' }
    @{ Name = 'every collector Failed and an extra line'; S = @('Failed', 'Failed', 'Failed', 'Failed', 'Failed'); Extra = @('manifest: x'); Expected = 'Failed' }
    @{ Name = 'no collector row at all'; S = @($null, $null, $null, $null, $null); Extra = @(); Expected = 'Failed' }
    @{ Name = 'four Success and one selected type without a row'; S = @('Success', 'Success', $null, 'Success', 'Success'); Extra = @(); Expected = 'Partial' }
)

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ModuleFolder = Join-Path -Path $script:RepoRoot -ChildPath 'RemoteBaseline'
    $script:ManifestPath = Join-Path -Path $script:ModuleFolder -ChildPath 'RemoteBaseline.psd1'
    $script:HelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers'
    . (Join-Path -Path $script:HelperPath -ChildPath 'FakeCollector.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    Import-Module $script:ManifestPath -Force
    $script:Module = Get-Module RemoteBaseline
    $script:ModuleVersion = (Import-PowerShellDataFile -LiteralPath $script:ManifestPath).ModuleVersion
    $script:Bundle = Get-Content -LiteralPath (Join-Path -Path $script:ModuleFolder -ChildPath 'Modules\bundle.json') -Raw | ConvertFrom-Json
    $script:TypeCases = Get-FakeTypeCase
    $script:AllTypes = @('Firewall', 'RSOP', 'ScheduledTask', 'SecEdit', 'Service')
    $script:AllModules = @('RemoteFirewall', 'RemoteRSOP', 'RemoteScheduledTask', 'RemoteSecEdit', 'RemoteService')
    $script:RunKeys = 'RunId,Collector,CollectorVersion,SchemaVersion,HostComputer,HostComputerId,HostUser,PSVersion,StartUtc,EndUtc,RequestedComputers,Types,ThrottleLimit,UseSSL,Compress,Archive,Collectors,Results'
    $script:RunCollectorKeys = 'Type,Module,Version,RunId,DurationMs,RowCount,SuccessCount,PartialCount,FailedCount,Error'
    $script:RowKeys = 'ComputerName,ComputerId,Status,Transport,OutputFolder,IsElevated,Types,FirewallStatus,RSOPStatus,ScheduledTaskStatus,SecEditStatus,ServiceStatus,FirewallErrorCount,RSOPErrorCount,ScheduledTaskErrorCount,SecEditErrorCount,ServiceErrorCount,Error,ErrorCount,Errors'
    $script:CsvHeader = '"ComputerName","ComputerId","Status","Transport","OutputFolder","IsElevated","Types","FirewallStatus","RSOPStatus","ScheduledTaskStatus","SecEditStatus","ServiceStatus","FirewallErrorCount","RSOPErrorCount","ScheduledTaskErrorCount","SecEditErrorCount","ServiceErrorCount","Error","ErrorCount"'
    $script:HostKeys = 'ComputerName,RequestedNames,ComputerId,DnsHostName,Domain,OSCaption,OSVersion,CurrentBuild,UBR,DisplayVersion,EditionID,InstallationType,Culture,TimeZoneId,PartOfDomain,DomainRole,IsElevated,MachineGuid,Collector,CollectorVersion,RunId,Types,Collectors,Status,Errors'
    $script:HostCollectorKeys = 'Type,Module,Version,Subfolder,Status,ErrorCount,RunId'
    $script:IsoPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'

    function Get-Sha256Hex {
        param([string]$Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    function Read-JsonFile {
        param([string]$Path)
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }

    function Get-RelativeFile {
        param([string]$Root)
        $rootFull = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
        $list = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($rootFull.Length + 1).Replace('\', '/') })
        $sorted = [string[]]$list
        [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        return $sorted
    }

    function Get-TestCredential {
        $secure = New-Object System.Security.SecureString
        foreach ($ch in 'x'.ToCharArray()) { $secure.AppendChar($ch) }
        $secure.MakeReadOnly()
        return (New-Object System.Management.Automation.PSCredential('someuser', $secure))
    }

    # The same per-name entry for every module, so aliases and two-names-of-one-host hold for all five collectors.
    function Get-EntryForAllModule {
        param([hashtable]$PerName)
        $entries = @{}
        foreach ($moduleName in $script:AllModules) { $entries[$moduleName] = $PerName }
        return $entries
    }

    # Puts the fake in place of the five collectors: the resolver is mocked in the module's scope to return the fake's FunctionInfo and the bundled version, and Start-Sleep to a no-op, so the retry of the arrangement never waits and a test can count its sleeps. Returns the state the fake fills.
    function Register-FakeCollector {
        param([hashtable]$Config = @{})
        $versions = @{}
        foreach ($entry in $script:Bundle.Modules) { $versions[[string]$entry.Module] = [string]$entry.Version }
        $state = Get-FakeCollectorState -Config $Config -Version $versions
        Use-FakeCollectorState -State $state
        Mock -ModuleName RemoteBaseline -CommandName Get-RemoteBaselineCollectorCommand -MockWith { Get-FakeCollectorResolution -Module $Module }
        Mock -ModuleName RemoteBaseline -CommandName Start-Sleep -MockWith { }
        return $state
    }

    # Registers the fake and calls Get-RemoteBaseline once. Extra mocks a test needs go in its own BeforeAll before this call.
    function Invoke-FakeBaseline {
        param(
            [hashtable]$Config = @{},
            [hashtable]$Parameter = @{},
            [string]$OutputPath,
            [object[]]$Pipeline
        )
        if (-not $OutputPath) { $OutputPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N')) }
        $state = Register-FakeCollector -Config $Config
        $warnings = $null
        if ($PSBoundParameters.ContainsKey('Pipeline')) {
            $rows = @($Pipeline | Get-RemoteBaseline @Parameter -OutputPath $OutputPath -WarningVariable warnings -WarningAction SilentlyContinue)
        } else {
            $rows = @(Get-RemoteBaseline @Parameter -OutputPath $OutputPath -WarningVariable warnings -WarningAction SilentlyContinue)
        }
        $runFolder = $null
        $found = @(Get-ChildItem -LiteralPath $OutputPath -Directory -Filter 'RemoteBaseline-*' -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) { $runFolder = $found[0].FullName }
        return [pscustomobject]@{
            Rows       = $rows
            Warnings   = @($warnings | ForEach-Object { $_.Message })
            OutputPath = $OutputPath
            RunFolder  = $runFolder
            State      = $state
        }
    }

    function Get-HostFolderOf {
        param($Run, [string]$Name)
        return (@($Run.Rows | Where-Object { $_.ComputerName -eq $Name })[0]).OutputFolder
    }

    function Get-RowOf {
        param($Run, [string]$Name)
        return @($Run.Rows | Where-Object { $_.ComputerName -eq $Name })[0]
    }

    function Get-RunStamp {
        param([string]$RunFolder)
        return ([regex]::Match((Split-Path -Path $RunFolder -Leaf), '^RemoteBaseline-(\d{8}-\d{6})Z')).Groups[1].Value
    }

    function Get-ExpectedHostLeaf {
        param([string]$Name, [string]$Stamp, [string]$Suffix = '')
        return ('{0}_20348_{1}Z{2}' -f $Name, $Stamp, $Suffix)
    }

    function Get-ChildNameList {
        param([string]$Path)
        $names = @(Get-ChildItem -LiteralPath $Path -Force | ForEach-Object { $_.Name })
        [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
        return ($names -join ',')
    }

    function Get-CollectorRowFake {
        param([AllowNull()]$Status, [string[]]$ErrorLine = @())
        if ($null -eq $Status) { return $null }
        return [pscustomobject]@{ ComputerName = 'WS01'; ComputerId = 'ID1'; Status = $Status; Transport = 'WinRM'; OutputFolder = ''; IsElevated = $true; Error = ''; ErrorCount = $ErrorLine.Count; Errors = $ErrorLine }
    }

    # Mocks Write-RemoteBaselineTextFile in module scope to throw for one file name and to write every other file as the real function does (Pester 6 falls back to nothing when a filter does not match, and host.json and the manifest go through the same writer).
    function Register-TextWriterFailure {
        param([string]$FileName, [string]$Message)
        $script:RealTextWriter = & $script:Module { (Get-Command -Name Write-RemoteBaselineTextFile -CommandType Function).ScriptBlock }
        $script:FailFileName = $FileName
        $script:FailMessage = $Message
        Mock -ModuleName RemoteBaseline -CommandName Write-RemoteBaselineTextFile -MockWith {
            if ((Split-Path -Path $Path -Leaf) -eq $script:FailFileName) { throw $script:FailMessage }
            & $script:RealTextWriter -Path $Path -Content $Content
        }
    }

    $script:MixedConfig = @{
        Warn    = @('RemoteFirewall', 'RemoteService')
        Entries = @{
            RemoteFirewall      = @{ SRV02 = @{ Mode = 'Partial'; Errors = @('rule 5: access denied', "second`r`nline") }; WS03 = @{ Mode = 'Failed' }; NOSUCH = @{ Mode = 'Failed' } }
            RemoteRSOP          = @{ NOSUCH = @{ Mode = 'Failed' } }
            RemoteScheduledTask = @{ SRV02 = @{ Mode = 'Failed'; Errors = @('WinRM cannot connect') }; NOSUCH = @{ Mode = 'Failed' } }
            RemoteSecEdit       = @{ NOSUCH = @{ Mode = 'Failed' } }
            RemoteService       = @{ SRV02 = @{ Mode = 'Partial'; Errors = @('svc err') }; NOSUCH = @{ Mode = 'Failed' } }
        }
    }
    $script:MixedNames = @('WS01', 'SRV02', 'WS03', 'NOSUCH')
}

Describe 'Get-RemoteBaseline - parameter forwarding' {
    Context 'defaults, with duplicate and differently cased names' {
        BeforeAll {
            $script:P = Invoke-FakeBaseline -Parameter @{ ComputerName = @('ws01', 'WS01', 'srv02', ' SRV02 ', 'Ws01') }
        }

        It 'calls every collector exactly once, in the fixed order Firewall, RSOP, ScheduledTask, SecEdit, Service' {
            $script:P.State.Calls.Count | Should -Be 5
            (@($script:P.State.Calls | ForEach-Object { $_.Module }) -join ',') | Should -BeExactly ($script:AllModules -join ',')
            # The umbrella reaches a collector only through the resolver: once per selected collector, by module and function.
            Should -Invoke -ModuleName RemoteBaseline -CommandName Get-RemoteBaselineCollectorCommand -Scope Context -Exactly -Times 5
            foreach ($case in $script:TypeCases) {
                Should -Invoke -ModuleName RemoteBaseline -CommandName Get-RemoteBaselineCollectorCommand -Scope Context -Exactly -Times 1 -ParameterFilter { $Module -eq $case.Module -and $Function -eq $case.Function }
            }
        }

        It 'passes the de-duplicated names, first spelling and order kept' {
            foreach ($call in $script:P.State.Calls) {
                (@($call.ComputerName) -join ',') | Should -BeExactly 'ws01,srv02'
            }
        }

        It 'passes -OutputPath as the run folder plus collectors, -ThrottleLimit 32 and -WarningAction SilentlyContinue' {
            $expected = Join-Path -Path $script:P.RunFolder -ChildPath 'collectors'
            foreach ($call in $script:P.State.Calls) {
                $call.OutputPath | Should -BeExactly $expected
                $call.ThrottleLimit | Should -BeExactly 32
                $call.Bound['WarningAction'] | Should -BeExactly 'SilentlyContinue'
            }
        }

        It 'does not bind -Credential or -UseSSL when the caller gave neither' {
            $script:P.State.Calls.Count | Should -Be 5
            foreach ($call in $script:P.State.Calls) {
                $call.Bound.ContainsKey('Credential') | Should -BeFalse -Because $call.Module
                $call.Bound.ContainsKey('UseSSL') | Should -BeFalse -Because $call.Module
            }
        }

        It 'selects all five types in run order by default' {
            (@($script:P.Rows[0].Types) -join ',') | Should -BeExactly ($script:AllTypes -join ',')
            ((Read-JsonFile -Path (Join-Path -Path $script:P.RunFolder -ChildPath 'run.json')).Types -join ',') | Should -BeExactly ($script:AllTypes -join ',')
        }

        It 'returns one row per de-duplicated name' {
            $script:P.Rows.Count | Should -Be 2
            (@($script:P.Rows | ForEach-Object { $_.ComputerName }) -join ',') | Should -BeExactly 'ws01,srv02'
        }
    }

    Context '-Credential, -UseSSL and -ThrottleLimit given' {
        BeforeAll {
            $script:P = Invoke-FakeBaseline -Parameter @{ ComputerName = @('ws01'); Credential = (Get-TestCredential); UseSSL = $true; ThrottleLimit = 5 }
        }

        It 'forwards them unchanged to every collector' {
            $script:P.State.Calls.Count | Should -Be 5
            foreach ($call in $script:P.State.Calls) {
                $call.ThrottleLimit | Should -BeExactly 5
                $call.Bound['UseSSL'] | Should -BeTrue
                $call.Bound['Credential'].UserName | Should -BeExactly 'someuser'
            }

        }

        It 'records ThrottleLimit and UseSSL in run.json' {
            $runJson = Read-JsonFile -Path (Join-Path -Path $script:P.RunFolder -ChildPath 'run.json')
            $runJson.ThrottleLimit | Should -BeExactly 5
            $runJson.UseSSL | Should -BeTrue
        }
    }

    Context '-Type Firewall, Service with duplicates and case differences' {
        BeforeAll {
            $script:P = Invoke-FakeBaseline -Parameter @{ ComputerName = @('ws01'); Type = @('service', 'Firewall', 'SERVICE', 'firewall') }
        }

        It 'calls exactly Firewall and Service, in run order, and no other collector' {
            (@($script:P.State.Calls | ForEach-Object { $_.Module }) -join ',') | Should -BeExactly 'RemoteFirewall,RemoteService'
            foreach ($functionName in @('Get-FirewallInventory', 'Get-ServiceInventory')) {
                Should -Invoke -ModuleName RemoteBaseline -CommandName Get-RemoteBaselineCollectorCommand -Scope Context -Exactly -Times 1 -ParameterFilter { $Function -eq $functionName }
            }
            foreach ($functionName in @('Get-RsopInventory', 'Get-ScheduledTaskInventory', 'Get-SecEditExport')) {
                Should -Invoke -ModuleName RemoteBaseline -CommandName Get-RemoteBaselineCollectorCommand -Scope Context -Exactly -Times 0 -ParameterFilter { $Function -eq $functionName }
            }
        }

        It 'gives the unselected types null status and count columns and the selected ones their values' {
            $row = $script:P.Rows[0]
            (@($row.Types) -join ',') | Should -BeExactly 'Firewall,Service'
            $row.FirewallStatus | Should -BeExactly 'Success'
            $row.ServiceStatus | Should -BeExactly 'Success'
            $row.FirewallErrorCount | Should -BeExactly 0
            foreach ($column in @('RSOPStatus', 'ScheduledTaskStatus', 'SecEditStatus', 'RSOPErrorCount', 'ScheduledTaskErrorCount', 'SecEditErrorCount')) {
                $row.$column | Should -BeNull -Because $column
            }
            $row.Status | Should -BeExactly 'Success'
        }

        It 'has no subfolder for an unselected collector' {
            (Get-ChildNameList -Path $script:P.Rows[0].OutputFolder) | Should -BeExactly 'RemoteFirewall,RemoteService,host.json'
            (Get-ChildNameList -Path (Join-Path -Path $script:P.RunFolder -ChildPath 'collectors')) | Should -BeExactly 'RemoteFirewall,RemoteService'
        }
    }

    Context 'an empty -Type means all five' {
        It 'runs all five collectors' {
            $run = Invoke-FakeBaseline -Parameter @{ ComputerName = @('ws01'); Type = @() }
            $run.State.Calls.Count | Should -Be 5
        }
    }

    Context 'pipeline input and the default name' {
        It 'takes names by value' {
            $run = Invoke-FakeBaseline -Pipeline @('a1', 'b2', 'A1')
            (@($run.State.Calls[0].ComputerName) -join ',') | Should -BeExactly 'a1,b2'
            $run.Rows.Count | Should -Be 2
        }

        It 'takes names by property name ComputerName' {
            $run = Invoke-FakeBaseline -Pipeline @([pscustomobject]@{ ComputerName = 'c3' }, [pscustomobject]@{ ComputerName = 'd4' })
            (@($run.State.Calls[0].ComputerName) -join ',') | Should -BeExactly 'c3,d4'
        }

        It 'defaults ComputerName to the local computer name' {
            $run = Invoke-FakeBaseline
            (@($run.State.Calls[0].ComputerName) -join ',') | Should -BeExactly $env:COMPUTERNAME
            $run.Rows.Count | Should -Be 1
            $run.Rows[0].ComputerName | Should -BeExactly $env:COMPUTERNAME
        }
    }

    Context 'an empty name list' {
        It 'gives one warning, no row and no collector call' {
            $run = Invoke-FakeBaseline -Parameter @{ ComputerName = @('', '   ') }
            $run.Rows.Count | Should -Be 0
            $run.Warnings.Count | Should -Be 1
            $run.State.Calls.Count | Should -Be 0
        }
    }

    Context 'parameter validation' {
        It 'refuses a type outside the set and a throttle limit outside 1..256 at binding' {
            { Get-RemoteBaseline -OutputPath (Join-Path -Path $TestDrive -ChildPath 'v1') -Type 'Bogus' } | Should -Throw
            { Get-RemoteBaseline -OutputPath (Join-Path -Path $TestDrive -ChildPath 'v2') -ThrottleLimit 0 } | Should -Throw
            { Get-RemoteBaseline -OutputPath (Join-Path -Path $TestDrive -ChildPath 'v3') -ThrottleLimit 257 } | Should -Throw
        }
    }
}

Describe 'Get-RemoteBaseline - a mixed run of five collectors and four names' {
    BeforeAll {
        $script:A = Invoke-FakeBaseline -Config $script:MixedConfig -Parameter @{ ComputerName = $script:MixedNames; ThrottleLimit = 7 }
        $script:AStamp = Get-RunStamp -RunFolder $script:A.RunFolder
    }

    Context 'layout' {
        It 'creates one run folder named RemoteBaseline-yyyyMMdd-HHmmssZ under OutputPath' {
            @(Get-ChildItem -LiteralPath $script:A.OutputPath -Force).Count | Should -Be 1
            (Split-Path -Path $script:A.RunFolder -Leaf) | Should -Match '^RemoteBaseline-\d{8}-\d{6}Z$'
        }

        It 'holds exactly run.json, results.csv, manifest.sha256, collectors and the host folders' {
            $expected = @((Get-ExpectedHostLeaf -Name 'SRV02' -Stamp $script:AStamp), (Get-ExpectedHostLeaf -Name 'WS01' -Stamp $script:AStamp), (Get-ExpectedHostLeaf -Name 'WS03' -Stamp $script:AStamp), 'collectors', 'manifest.sha256', 'results.csv', 'run.json') -join ','
            (Get-ChildNameList -Path $script:A.RunFolder) | Should -BeExactly $expected
        }

        It 'names the host folder from the computer folder leaf and the umbrella stamp, not the collector stamp' {
            foreach ($name in @('WS01', 'SRV02', 'WS03')) {
                $folder = Get-HostFolderOf -Run $script:A -Name $name
                $leaf = Split-Path -Path $folder -Leaf
                $parsed = [regex]::Match($leaf, '^(?<name>.+)_(?<build>[^_]+)_(?<stamp>\d{8}-\d{6})Z$')
                $parsed.Success | Should -BeTrue
                $parsed.Groups['name'].Value | Should -BeExactly $name
                $parsed.Groups['build'].Value | Should -BeExactly '20348'
                $parsed.Groups['stamp'].Value | Should -BeExactly $script:AStamp
                $parsed.Groups['stamp'].Value | Should -Not -BeExactly '20200101-000102'
                (Split-Path -Path $folder -Parent) | Should -BeExactly $script:A.RunFolder
            }
        }

        It 'names every subfolder after its module, with the computer folder files inside' {
            $host1 = Get-HostFolderOf -Run $script:A -Name 'WS01'
            (Get-ChildNameList -Path $host1) | Should -BeExactly 'RemoteFirewall,RemoteRSOP,RemoteScheduledTask,RemoteSecEdit,RemoteService,host.json'
            foreach ($moduleName in $script:AllModules) {
                (Get-ChildNameList -Path (Join-Path -Path $host1 -ChildPath $moduleName)) | Should -BeExactly 'subject.json,system.json'
            }
        }

        It 'keeps only the reaching collectors as subfolders of a partly reached host' {
            (Get-ChildNameList -Path (Get-HostFolderOf -Run $script:A -Name 'SRV02')) | Should -BeExactly 'RemoteFirewall,RemoteRSOP,RemoteSecEdit,RemoteService,host.json'
            (Get-ChildNameList -Path (Get-HostFolderOf -Run $script:A -Name 'WS03')) | Should -BeExactly 'RemoteRSOP,RemoteScheduledTask,RemoteSecEdit,RemoteService,host.json'
        }

        It 'gives a host that no collector reached no folder and an empty OutputFolder' {
            (Get-RowOf -Run $script:A -Name 'NOSUCH').OutputFolder | Should -BeExactly ''
            @(Get-ChildItem -LiteralPath $script:A.RunFolder -Directory | Where-Object { $_.Name -like 'NOSUCH*' }).Count | Should -Be 0
        }

        It 'keeps run.json and results.csv of each collector in collectors\ModuleName\ and no computer folder' {
            foreach ($moduleName in $script:AllModules) {
                (Get-ChildNameList -Path (Join-Path -Path (Join-Path -Path $script:A.RunFolder -ChildPath 'collectors') -ChildPath $moduleName)) | Should -BeExactly 'results.csv,run.json'
            }
            (Get-ChildNameList -Path (Join-Path -Path $script:A.RunFolder -ChildPath 'collectors')) | Should -BeExactly ($script:AllModules -join ',')
        }

        It 'leaves the collector files byte for byte as written (hash after equals hash at write time)' {
            $computerRecords = @($script:A.State.Written | Where-Object { $_.Kind -eq 'computer' })
            # WS01 five collectors, SRV02 four, WS03 four, two files each: the loop below covers every one.
            $computerRecords.Count | Should -Be 26
            foreach ($record in $computerRecords) {
                $path = Join-Path -Path (Join-Path -Path (Get-HostFolderOf -Run $script:A -Name $record.Name[0]) -ChildPath $record.Module) -ChildPath $record.File
                Get-Sha256Hex -Path $path | Should -BeExactly $record.Sha256 -Because $path
            }
            $runRecords = @($script:A.State.Written | Where-Object { $_.Kind -eq 'run' })
            $runRecords.Count | Should -Be 10
            foreach ($record in $runRecords) {
                $path = Join-Path -Path (Join-Path -Path (Join-Path -Path $script:A.RunFolder -ChildPath 'collectors') -ChildPath $record.Module) -ChildPath $record.File
                Get-Sha256Hex -Path $path | Should -BeExactly $record.Sha256 -Because $path
            }
        }
    }

    Context 'rows' {
        It 'returns one row per requested name in requested order, typed RemoteBaseline.Result, columns in the contract order' {
            $script:A.Rows.Count | Should -Be 4
            (@($script:A.Rows | ForEach-Object { $_.ComputerName }) -join ',') | Should -BeExactly 'WS01,SRV02,WS03,NOSUCH'
            foreach ($row in $script:A.Rows) {
                $row.PSObject.TypeNames[0] | Should -BeExactly 'RemoteBaseline.Result'
                (@($row.PSObject.Properties.Name) -join ',') | Should -BeExactly $script:RowKeys
            }
        }

        It 'gives the all-Success host Success, empty Error, count 0 and no Errors' {
            $row = Get-RowOf -Run $script:A -Name 'WS01'
            $row.Status | Should -BeExactly 'Success'
            $row.Error | Should -BeExactly ''
            $row.ErrorCount | Should -BeExactly 0
            @($row.Errors).Count | Should -Be 0
            $row.Transport | Should -BeExactly 'WinRM'
            $row.IsElevated | Should -BeTrue
            $row.ComputerId | Should -Match '^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$'
            $row.OutputFolder | Should -BeExactly (Join-Path -Path $script:A.RunFolder -ChildPath ('WS01_20348_' + $script:AStamp + 'Z'))
            foreach ($typeName in $script:AllTypes) {
                $row.PSObject.Properties[$typeName + 'Status'].Value | Should -BeExactly 'Success'
                $row.PSObject.Properties[$typeName + 'ErrorCount'].Value | Should -BeExactly 0
            }
        }

        It 'gives the mixed host Partial with the per-type statuses and counts of its collectors' {
            $row = Get-RowOf -Run $script:A -Name 'SRV02'
            $row.Status | Should -BeExactly 'Partial'
            (@('FirewallStatus', 'RSOPStatus', 'ScheduledTaskStatus', 'SecEditStatus', 'ServiceStatus') | ForEach-Object { $row.$_ }) -join ',' | Should -BeExactly 'Partial,Success,Failed,Success,Partial'
            (@('FirewallErrorCount', 'RSOPErrorCount', 'ScheduledTaskErrorCount', 'SecEditErrorCount', 'ServiceErrorCount') | ForEach-Object { $row.$_ }) -join ',' | Should -BeExactly '2,0,1,0,1'
        }

        It 'gives a host that one collector could not reach, with the rest Success, Partial' {
            $row = Get-RowOf -Run $script:A -Name 'WS03'
            $row.Status | Should -BeExactly 'Partial'
            $row.FirewallStatus | Should -BeExactly 'Failed'
            $row.ComputerId | Should -Not -BeNullOrEmpty
        }

        It 'gives the host that no collector reached Failed with null id and elevation and the Failed collector statuses' {
            $row = Get-RowOf -Run $script:A -Name 'NOSUCH'
            $row.Status | Should -BeExactly 'Failed'
            $row.ComputerId | Should -BeNull
            $row.IsElevated | Should -BeNull
            $row.Transport | Should -BeExactly 'WinRM'
            $row.ErrorCount | Should -BeExactly 5
            foreach ($typeName in $script:AllTypes) { $row.PSObject.Properties[$typeName + 'Status'].Value | Should -BeExactly 'Failed' }
        }
    }

    Context 'Errors, Error and one line per entry' {
        It 'prefixes every collector error with its type, in run order and in the collector''s own order' {
            $row = Get-RowOf -Run $script:A -Name 'SRV02'
            (@($row.Errors) -join '|') | Should -BeExactly 'Firewall: rule 5: access denied|Firewall: second line|ScheduledTask: WinRM cannot connect|Service: svc err'
            $row.Error | Should -BeExactly 'Firewall: rule 5: access denied'
            $row.ErrorCount | Should -BeExactly 4
        }

        It 'collapses a multi-line collector error to one trimmed line in Errors and Error' {
            foreach ($row in $script:A.Rows) {
                foreach ($line in @($row.Errors) + @($row.Error)) {
                    $line | Should -Not -Match '[\r\n]'
                    $line | Should -BeExactly $line.Trim()
                }
            }
        }

        It 'keeps the same list in run.json' {
            $runJson = Read-JsonFile -Path (Join-Path -Path $script:A.RunFolder -ChildPath 'run.json')
            (@($runJson.Results[1].Errors) -join '|') | Should -BeExactly 'Firewall: rule 5: access denied|Firewall: second line|ScheduledTask: WinRM cannot connect|Service: svc err'
        }
    }

    Context 'warnings' {
        It 'writes one warning per row that is not Success, with the row text, and none for the collectors'' own warnings' {
            $script:A.Warnings.Count | Should -Be 3
            $script:A.Warnings[0] | Should -BeExactly 'SRV02: Partial, 4 error(s): Firewall: rule 5: access denied'
            $script:A.Warnings[1] | Should -BeExactly 'WS03: Partial, 1 error(s): Firewall: WinRM cannot complete the operation.'
            $script:A.Warnings[2] | Should -BeExactly 'NOSUCH: Failed, 5 error(s): Firewall: WinRM cannot complete the operation.'
        }
    }

    Context 'host.json' {
        BeforeAll {
            $script:H1 = Read-JsonFile -Path (Join-Path -Path (Get-HostFolderOf -Run $script:A -Name 'WS01') -ChildPath 'host.json')
            $script:H2 = Read-JsonFile -Path (Join-Path -Path (Get-HostFolderOf -Run $script:A -Name 'SRV02') -ChildPath 'host.json')
            $script:H3 = Read-JsonFile -Path (Join-Path -Path (Get-HostFolderOf -Run $script:A -Name 'WS03') -ChildPath 'host.json')
        }

        It 'has the contract keys in the contract order, written without a byte order mark' {
            foreach ($hostJson in @($script:H1, $script:H2, $script:H3)) {
                (@($hostJson.PSObject.Properties.Name) -join ',') | Should -BeExactly $script:HostKeys
            }
            [System.IO.File]::ReadAllBytes((Join-Path -Path (Get-HostFolderOf -Run $script:A -Name 'WS01') -ChildPath 'host.json'))[0] | Should -Be 0x7B
        }

        It 'carries the requested name, the umbrella identity and the selected types' {
            $script:H1.ComputerName | Should -BeExactly 'WS01'
            $script:H1.Collector | Should -BeExactly 'RemoteBaseline'
            $script:H1.CollectorVersion | Should -BeExactly $script:ModuleVersion
            $script:H1.RunId | Should -BeExactly (Split-Path -Path $script:A.RunFolder -Leaf)
            ($script:H1.Types -join ',') | Should -BeExactly ($script:AllTypes -join ',')
        }

        It 'keeps RequestedNames an array of one in the file' {
            $text = Get-Content -LiteralPath (Join-Path -Path (Get-HostFolderOf -Run $script:A -Name 'WS01') -ChildPath 'host.json') -Raw
            $text | Should -Match '"RequestedNames":\s*\[\s*"WS01"\s*\]'
            @($script:H1.RequestedNames).Count | Should -Be 1
        }

        It 'copies the identity values from the first present subfolder''s system.json' {
            $script:H1.ComputerId | Should -BeExactly (Get-RowOf -Run $script:A -Name 'WS01').ComputerId
            $script:H1.DnsHostName | Should -BeExactly 'ws01.contoso.example'
            $script:H1.Domain | Should -BeExactly 'contoso.example'
            $script:H1.OSCaption | Should -BeExactly 'Microsoft Windows Server 2022 Standard'
            $script:H1.OSVersion | Should -BeExactly '10.0.20348'
            $script:H1.CurrentBuild | Should -BeExactly '20348'
            $script:H1.DisplayVersion | Should -BeExactly '21H2'
            $script:H1.EditionID | Should -BeExactly 'ServerStandard'
            $script:H1.InstallationType | Should -BeExactly 'Server'
            $script:H1.Culture | Should -BeExactly 'en-US'
            $script:H1.TimeZoneId | Should -BeExactly 'UTC'
            $script:H1.PartOfDomain | Should -BeTrue
            $script:H1.DomainRole | Should -BeExactly 3
            $script:H1.IsElevated | Should -BeTrue
            $script:H1.MachineGuid | Should -BeExactly $script:H1.ComputerId.ToLowerInvariant()
            # UBR is 5000 plus the collector's index in the fake: Firewall (5000) for WS01 and SRV02, RSOP (5001) for WS03, whose Firewall had no folder.
            $script:H1.UBR | Should -BeExactly 5000
            $script:H2.UBR | Should -BeExactly 5000
            $script:H3.UBR | Should -BeExactly 5001
        }

        It 'lists one Collectors entry per selected type in run order with the contract keys' {
            @($script:H1.Collectors).Count | Should -Be 5
            (@($script:H1.Collectors | ForEach-Object { $_.Type }) -join ',') | Should -BeExactly ($script:AllTypes -join ',')
            foreach ($entry in $script:H1.Collectors) {
                (@($entry.PSObject.Properties.Name) -join ',') | Should -BeExactly $script:HostCollectorKeys
            }
            $firewall = $script:H1.Collectors[0]
            $firewall.Module | Should -BeExactly 'RemoteFirewall'
            $firewall.Version | Should -BeExactly (@($script:Bundle.Modules | Where-Object { $_.Module -eq 'RemoteFirewall' })[0]).Version
            $firewall.Subfolder | Should -BeExactly 'RemoteFirewall'
            $firewall.Status | Should -BeExactly 'Success'
            $firewall.ErrorCount | Should -BeExactly 0
            $firewall.RunId | Should -BeExactly 'RemoteFirewall-20200101-000102Z'
        }

        It 'gives a collector without a folder a null Subfolder and keeps its status and error count' {
            $scheduled = $script:H2.Collectors[2]
            $scheduled.Subfolder | Should -BeNull
            $scheduled.Status | Should -BeExactly 'Failed'
            $scheduled.ErrorCount | Should -BeExactly 1
            $script:H3.Collectors[0].Subfolder | Should -BeNull
        }

        It 'carries the row Status and the same Errors as the result row' {
            $script:H1.Status | Should -BeExactly 'Success'
            @($script:H1.Errors).Count | Should -Be 0
            $script:H2.Status | Should -BeExactly 'Partial'
            (@($script:H2.Errors) -join '|') | Should -BeExactly (@((Get-RowOf -Run $script:A -Name 'SRV02').Errors) -join '|')
        }
    }

    Context 'run.json' {
        BeforeAll {
            $script:RunText = Get-Content -LiteralPath (Join-Path -Path $script:A.RunFolder -ChildPath 'run.json') -Raw
            $script:RunJson = $script:RunText | ConvertFrom-Json
        }

        It 'has the contract keys in the contract order, written without a byte order mark' {
            (@($script:RunJson.PSObject.Properties.Name) -join ',') | Should -BeExactly $script:RunKeys
            [System.IO.File]::ReadAllBytes((Join-Path -Path $script:A.RunFolder -ChildPath 'run.json'))[0] | Should -Be 0x7B
        }

        It 'carries the run identity and the call parameters' {
            $script:RunJson.RunId | Should -BeExactly (Split-Path -Path $script:A.RunFolder -Leaf)
            $script:RunJson.Collector | Should -BeExactly 'RemoteBaseline'
            $script:RunJson.CollectorVersion | Should -BeExactly $script:ModuleVersion
            $script:RunJson.SchemaVersion | Should -BeExactly '1.2'
            $script:RunJson.HostComputer | Should -BeExactly $env:COMPUTERNAME
            $script:RunJson.HostUser | Should -BeExactly "$env:USERDOMAIN\$env:USERNAME"
            $script:RunJson.PSVersion | Should -BeExactly $PSVersionTable.PSVersion.ToString()
            $script:RunJson.ThrottleLimit | Should -BeExactly 7
            $script:RunJson.UseSSL | Should -BeFalse
            $script:RunJson.Compress | Should -BeFalse
            $script:RunJson.Archive | Should -BeNull
            (@($script:RunJson.RequestedComputers) -join ',') | Should -BeExactly 'WS01,SRV02,WS03,NOSUCH'
            (@($script:RunJson.Types) -join ',') | Should -BeExactly ($script:AllTypes -join ',')
        }

        It 'writes StartUtc and EndUtc as ISO 8601 UTC text' {
            # PowerShell 7 turns an ISO looking string into a DateTime in ConvertFrom-Json, so the raw text is matched.
            foreach ($key in @('StartUtc', 'EndUtc')) {
                $match = [regex]::Match($script:RunText, '"' + $key + '":\s*"([^"]*)"')
                $match.Success | Should -BeTrue
                $match.Groups[1].Value | Should -Match $script:IsoPattern
            }
        }

        It 'has one Collectors object per selected type with the contract keys and counts' {
            @($script:RunJson.Collectors).Count | Should -Be 5
            foreach ($entry in $script:RunJson.Collectors) {
                (@($entry.PSObject.Properties.Name) -join ',') | Should -BeExactly $script:RunCollectorKeys
                $entry.RunId | Should -BeExactly ($entry.Module + '-20200101-000102Z')
                $entry.DurationMs | Should -BeGreaterOrEqual 0
                $entry.RowCount | Should -BeExactly 4
                $entry.Error | Should -BeNull
                $entry.Version | Should -BeExactly (@($script:Bundle.Modules | Where-Object { $_.Module -eq $entry.Module })[0]).Version
            }
            $firewall = $script:RunJson.Collectors[0]
            ($firewall.SuccessCount, $firewall.PartialCount, $firewall.FailedCount) -join ',' | Should -BeExactly '1,1,2'
            $scheduled = $script:RunJson.Collectors[2]
            ($scheduled.SuccessCount, $scheduled.PartialCount, $scheduled.FailedCount) -join ',' | Should -BeExactly '2,0,2'
        }

        It 'holds the result rows as an array with every column, Errors included, in order' {
            @($script:RunJson.Results).Count | Should -Be 4
            foreach ($result in $script:RunJson.Results) {
                (@($result.PSObject.Properties.Name) -join ',') | Should -BeExactly $script:RowKeys
                @($result.Types).Count | Should -Be 5
            }
            $script:RunJson.Results[3].ComputerId | Should -BeNull
            $script:RunJson.Results[0].Errors.Count | Should -Be 0
        }

        It 'keeps a one-row Results and an empty Errors as arrays in the file' {
            $run = Invoke-FakeBaseline -Parameter @{ ComputerName = @('ws01'); Type = @('Service') }
            $text = Get-Content -LiteralPath (Join-Path -Path $run.RunFolder -ChildPath 'run.json') -Raw
            $text | Should -Match '"Results":\s*\[\s*\{'
            $text | Should -Match '"Errors":\s*\[\s*\]'
            $text | Should -Match '"Collectors":\s*\[\s*\{'
        }
    }

    Context 'results.csv' {
        BeforeAll {
            $script:CsvPath = Join-Path -Path $script:A.RunFolder -ChildPath 'results.csv'
            $script:CsvBytes = [System.IO.File]::ReadAllBytes($script:CsvPath)
            $script:CsvLines = [System.IO.File]::ReadAllLines($script:CsvPath)
        }

        It 'starts with a utf-8 byte order mark followed by the opening quote of the header' {
            $script:CsvBytes[0] | Should -Be 0xEF
            $script:CsvBytes[1] | Should -Be 0xBB
            $script:CsvBytes[2] | Should -Be 0xBF
            $script:CsvBytes[3] | Should -Be 0x22
        }

        It 'has the contract columns, every one but Errors, in order' {
            $script:CsvLines[0].TrimStart([char]0xFEFF) | Should -BeExactly $script:CsvHeader
        }

        It 'has one line per row and no line break inside a cell' {
            $script:CsvLines.Count | Should -Be 5
            @(Import-Csv -LiteralPath $script:CsvPath).Count | Should -Be 4
        }

        It 'joins Types with a comma and a space and leaves the unselected-type cells to the selected run' {
            foreach ($csvRow in @(Import-Csv -LiteralPath $script:CsvPath)) {
                $csvRow.Types | Should -BeExactly 'Firewall, RSOP, ScheduledTask, SecEdit, Service'
            }
        }

        It 'writes a null as a bare cell and a number and an empty string as quoted cells, exactly, for an unreached host' {
            $expected = '"NOSUCH",,"Failed","WinRM","",,"Firewall, RSOP, ScheduledTask, SecEdit, Service","Failed","Failed","Failed","Failed","Failed","1","1","1","1","1","Firewall: WinRM cannot complete the operation.","5"'
            $script:CsvLines[4] | Should -BeExactly $expected
        }

        It 'matches the result rows cell for cell' {
            $csvRows = @(Import-Csv -LiteralPath $script:CsvPath)
            for ($i = 0; $i -lt 4; $i++) {
                $csvRows[$i].ComputerName | Should -BeExactly $script:A.Rows[$i].ComputerName
                $csvRows[$i].Status | Should -BeExactly $script:A.Rows[$i].Status
                $csvRows[$i].OutputFolder | Should -BeExactly $script:A.Rows[$i].OutputFolder
                $csvRows[$i].Error | Should -BeExactly $script:A.Rows[$i].Error
                $csvRows[$i].ErrorCount | Should -BeExactly ([string]$script:A.Rows[$i].ErrorCount)
            }
        }
    }

    Context 'manifest.sha256' {
        BeforeAll {
            $script:ManifestFile = Join-Path -Path $script:A.RunFolder -ChildPath 'manifest.sha256'
            $script:ManifestBytes = [System.IO.File]::ReadAllBytes($script:ManifestFile)
            $script:ManifestText = [System.Text.Encoding]::UTF8.GetString($script:ManifestBytes)
            $script:ManifestLines = @($script:ManifestText.Split("`n") | Where-Object { $_ -ne '' })
        }

        It 'is utf-8 without a byte order mark, with LF line endings only and a final LF' {
            $script:ManifestBytes[0] | Should -Not -Be 0xEF
            $script:ManifestBytes -contains 0x0D | Should -BeFalse
            $script:ManifestBytes[$script:ManifestBytes.Count - 1] | Should -Be 0x0A
        }

        It 'lists every file of the run folder once and itself never, as lower-case sha256, two spaces and the forward-slash relative path' {
            $all = Get-RelativeFile -Root $script:A.RunFolder
            $listed = @($script:ManifestLines | ForEach-Object { $_.Substring(66) })
            foreach ($line in $script:ManifestLines) { $line | Should -Match '^[0-9a-f]{64}  [^\\]+$' }
            $listed | Should -Not -Contain 'manifest.sha256'
            (@($listed) -join "`n") | Should -BeExactly ((@($all | Where-Object { $_ -ne 'manifest.sha256' })) -join "`n")
            @($listed | Select-Object -Unique).Count | Should -Be $listed.Count
        }

        It 'records the right hash for every file, run.json and results.csv included' {
            foreach ($line in $script:ManifestLines) {
                $relative = $line.Substring(66)
                $line.Substring(0, 64) | Should -BeExactly (Get-Sha256Hex -Path (Join-Path -Path $script:A.RunFolder -ChildPath $relative.Replace('/', '\'))) -Because $relative
            }
        }

        It 'sorts by ordinal comparison, which puts the upper-case host folders before collectors/' {
            $listed = @($script:ManifestLines | ForEach-Object { $_.Substring(66) })
            $sorted = [string[]]$listed
            [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
            ($listed -join "`n") | Should -BeExactly ($sorted -join "`n")
            $ignoreCase = [string[]]$listed
            [System.Array]::Sort($ignoreCase, [System.StringComparer]::OrdinalIgnoreCase)
            ($listed -join "`n") | Should -Not -BeExactly ($ignoreCase -join "`n")
            $listed[0] | Should -Match '^SRV02_20348_'
            $listed[$listed.Count - 1] | Should -BeExactly 'run.json'
        }
    }
}

Describe 'Get-RemoteBaseline - local aliases and two names of one host' {
    Context 'localhost and the local name, both reported as WS01' {
        BeforeAll {
            $entry = @{ 'localhost' = @{ Reported = 'WS01'; Transport = 'Local' }; 'WS01' = @{ Reported = 'WS01'; Transport = 'Local'; Alias = $true } }
            $script:Al = Invoke-FakeBaseline -Config @{ Entries = (Get-EntryForAllModule -PerName $entry) } -Parameter @{ ComputerName = @('localhost', 'WS01') }
        }

        It 'shares one host folder, with one subfolder per collector' {
            $script:Al.Rows.Count | Should -Be 2
            $script:Al.Rows[0].OutputFolder | Should -BeExactly $script:Al.Rows[1].OutputFolder
            @(Get-ChildItem -LiteralPath $script:Al.RunFolder -Directory | Where-Object { $_.Name -ne 'collectors' }).Count | Should -Be 1
            $script:Al.Rows[0].OutputFolder | Should -BeExactly (Join-Path -Path $script:Al.RunFolder -ChildPath ('WS01_20348_' + (Get-RunStamp -RunFolder $script:Al.RunFolder) + 'Z'))
            (Get-ChildNameList -Path $script:Al.Rows[0].OutputFolder) | Should -BeExactly 'RemoteFirewall,RemoteRSOP,RemoteScheduledTask,RemoteSecEdit,RemoteService,host.json'
        }

        It 'records both requested names in host.json, the first as ComputerName' {
            $hostJson = Read-JsonFile -Path (Join-Path -Path $script:Al.Rows[0].OutputFolder -ChildPath 'host.json')
            $hostJson.ComputerName | Should -BeExactly 'localhost'
            (@($hostJson.RequestedNames) -join ',') | Should -BeExactly 'localhost,WS01'
            $script:Al.Rows[0].Transport | Should -BeExactly 'Local'
        }
    }

    Context 'a short name and a fully qualified name of one host, both reported as WS01' {
        BeforeAll {
            $entry = @{ 'ws01' = @{ Reported = 'WS01' }; 'ws01.contoso.example' = @{ Reported = 'WS01' } }
            $script:Tw = Invoke-FakeBaseline -Config @{ Entries = (Get-EntryForAllModule -PerName $entry) } -Parameter @{ ComputerName = @('ws01', 'ws01.contoso.example') }
            $script:TwStamp = Get-RunStamp -RunFolder $script:Tw.RunFolder
        }

        It 'gives the second name a host folder with the _2 suffix, and keeps the pairing for every collector' {
            $script:Tw.Rows[0].OutputFolder | Should -BeExactly (Join-Path -Path $script:Tw.RunFolder -ChildPath ('WS01_20348_' + $script:TwStamp + 'Z'))
            $script:Tw.Rows[1].OutputFolder | Should -BeExactly (Join-Path -Path $script:Tw.RunFolder -ChildPath ('WS01_20348_' + $script:TwStamp + 'Z_2'))
            foreach ($index in 0, 1) {
                (Get-ChildNameList -Path $script:Tw.Rows[$index].OutputFolder) | Should -BeExactly 'RemoteFirewall,RemoteRSOP,RemoteScheduledTask,RemoteSecEdit,RemoteService,host.json'
                foreach ($moduleName in $script:AllModules) {
                    $system = Read-JsonFile -Path (Join-Path -Path (Join-Path -Path $script:Tw.Rows[$index].OutputFolder -ChildPath $moduleName) -ChildPath 'system.json')
                    $system.RequestedComputerName | Should -BeExactly @('ws01', 'ws01.contoso.example')[$index] -Because $moduleName
                }
            }
        }

        It 'writes one host.json per host folder naming its own requested name' {
            (Read-JsonFile -Path (Join-Path -Path $script:Tw.Rows[0].OutputFolder -ChildPath 'host.json')).ComputerName | Should -BeExactly 'ws01'
            (Read-JsonFile -Path (Join-Path -Path $script:Tw.Rows[1].OutputFolder -ChildPath 'host.json')).ComputerName | Should -BeExactly 'ws01.contoso.example'
        }
    }
}

Describe 'Get-RemoteBaseline - Status rules end to end' {
    Context 'every host reached by every collector' {
        It 'gives Success for all, and Partial when one collector is Partial' {
            $run = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1', 'b2') }
            @($run.Rows | ForEach-Object { $_.Status }) -join ',' | Should -BeExactly 'Success,Success'
            $run.Warnings.Count | Should -Be 0
            $partial = Invoke-FakeBaseline -Config @{ Entries = @{ RemoteSecEdit = @{ b2 = @{ Mode = 'Partial'; Errors = @('x') } } } } -Parameter @{ ComputerName = @('a1', 'b2') }
            @($partial.Rows | ForEach-Object { $_.Status }) -join ',' | Should -BeExactly 'Success,Partial'
        }
    }

    Context 'a name the collectors returned no row for' {
        BeforeAll {
            $script:G = Invoke-FakeBaseline -Config @{ Entries = (Get-EntryForAllModule -PerName @{ GHOST = @{ Mode = 'Missing' } }) } -Parameter @{ ComputerName = @('a1', 'GHOST') }
        }

        It 'gives it a synthetic Failed row per collector, so the host is Failed' {
            $row = Get-RowOf -Run $script:G -Name 'GHOST'
            $row.Status | Should -BeExactly 'Failed'
            $row.OutputFolder | Should -BeExactly ''
            $row.ErrorCount | Should -BeExactly 5
            $row.Error | Should -BeExactly 'Firewall: host: no result row returned'
            (Get-RowOf -Run $script:G -Name 'a1').Status | Should -BeExactly 'Success'
        }
    }

    Context 'a name missing in one collector only' {
        It 'gives the host Partial with the line of that collector' {
            $run = Invoke-FakeBaseline -Config @{ Entries = @{ RemoteRSOP = @{ GHOST = @{ Mode = 'Missing' } } } } -Parameter @{ ComputerName = @('GHOST') }
            $run.Rows[0].Status | Should -BeExactly 'Partial'
            (@($run.Rows[0].Errors) -join '|') | Should -BeExactly 'RSOP: host: no result row returned'
            $run.Rows[0].RSOPStatus | Should -BeExactly 'Failed'
        }
    }

    Context 'one collector throws' {
        BeforeAll {
            $script:Th = Invoke-FakeBaseline -Config @{ Throw = @('RemoteService'); ThrowMessage = "boom`r`nsecond line" } -Parameter @{ ComputerName = @('a1', 'b2') }
        }

        It 'gives synthetic Failed rows for that collector, Partial hosts and a completed run' {
            @($script:Th.Rows | ForEach-Object { $_.Status }) -join ',' | Should -BeExactly 'Partial,Partial'
            $script:Th.Rows[0].ServiceStatus | Should -BeExactly 'Failed'
            $script:Th.Rows[0].FirewallStatus | Should -BeExactly 'Success'
            (@($script:Th.Rows[0].Errors) -join '|') | Should -BeExactly 'Service: host: boom second line'
            (Test-Path -LiteralPath (Join-Path -Path $script:Th.RunFolder -ChildPath 'manifest.sha256')) | Should -BeTrue
        }

        It 'records the throw message, one line, in run.json and leaves no collectors\RemoteService folder' {
            $runJson = Read-JsonFile -Path (Join-Path -Path $script:Th.RunFolder -ChildPath 'run.json')
            $service = $runJson.Collectors[4]
            $service.Error | Should -BeExactly 'boom second line'
            $service.RunId | Should -BeNull
            $service.FailedCount | Should -Be 2
            $service.RowCount | Should -Be 2
            (Get-ChildNameList -Path (Join-Path -Path $script:Th.RunFolder -ChildPath 'collectors')) | Should -BeExactly 'RemoteFirewall,RemoteRSOP,RemoteScheduledTask,RemoteSecEdit'
            (Read-JsonFile -Path (Join-Path -Path $script:Th.Rows[0].OutputFolder -ChildPath 'host.json')).Collectors[4].Subfolder | Should -BeNull
        }
    }

    Context 'every collector throws, or every row is Failed' {
        It 'never throws, gives Failed rows and no host folder when every collector throws' {
            $run = Invoke-FakeBaseline -Config @{ Throw = $script:AllModules } -Parameter @{ ComputerName = @('a1', 'b2') }
            @($run.Rows | ForEach-Object { $_.Status }) -join ',' | Should -BeExactly 'Failed,Failed'
            $run.Rows[0].ErrorCount | Should -BeExactly 5
            (Get-ChildNameList -Path $run.RunFolder) | Should -BeExactly 'collectors,manifest.sha256,results.csv,run.json'
            $run.Warnings.Count | Should -Be 2
        }

        It 'finds and renames the collector run folder when every row is Failed (no OutputFolder to follow)' {
            $run = Invoke-FakeBaseline -Config @{ Entries = (Get-EntryForAllModule -PerName @{ NOSUCH = @{ Mode = 'Failed' } }) } -Parameter @{ ComputerName = @('NOSUCH') }
            $run.Rows[0].Status | Should -BeExactly 'Failed'
            foreach ($moduleName in $script:AllModules) {
                (Get-ChildNameList -Path (Join-Path -Path (Join-Path -Path $run.RunFolder -ChildPath 'collectors') -ChildPath $moduleName)) | Should -BeExactly 'results.csv,run.json'
            }
            (Read-JsonFile -Path (Join-Path -Path $run.RunFolder -ChildPath 'run.json')).Collectors[0].RunId | Should -BeExactly 'RemoteFirewall-20200101-000102Z'
        }
    }

    Context 'arrange failures' {
        BeforeAll {
            $config = @{
                Entries     = @{
                    RemoteFirewall = @{ a1 = @{ FolderName = 'garbage' } }
                    RemoteService  = @{ a1 = @{ Mode = 'Partial'; Errors = @('s1') } }
                }
                BlockRename = @('RemoteRSOP')
            }
            $script:Ar = Invoke-FakeBaseline -Config $config -Parameter @{ ComputerName = @('a1') }
            $script:ArCollectors = Join-Path -Path $script:Ar.RunFolder -ChildPath 'collectors'
        }

        It 'adds an arrange line for a computer folder that cannot be placed and leaves the folder where it was' {
            @($script:Ar.Rows[0].Errors | Where-Object { $_ -like 'arrange: RemoteFirewall: *' }).Count | Should -Be 1
            (Test-Path -LiteralPath (Join-Path -Path (Join-Path -Path $script:ArCollectors -ChildPath 'RemoteFirewall') -ChildPath 'garbage')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path -Path $script:Ar.Rows[0].OutputFolder -ChildPath 'RemoteFirewall')) | Should -BeFalse
        }

        It 'adds an arrange line for a collector run folder that cannot be renamed, leaves it, and still moves its computer folder' {
            @($script:Ar.Rows[0].Errors | Where-Object { $_ -like 'arrange: RemoteRSOP: *' }).Count | Should -Be 1
            (Test-Path -LiteralPath (Join-Path -Path $script:ArCollectors -ChildPath 'RemoteRSOP-20200101-000102Z') -PathType Container) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path -Path (Join-Path -Path $script:Ar.Rows[0].OutputFolder -ChildPath 'RemoteRSOP') -ChildPath 'system.json')) | Should -BeTrue
        }

        It 'lists the collector lines first and the arrange lines after them in collector order, and makes the row Partial' {
            $script:Ar.Rows[0].Status | Should -BeExactly 'Partial'
            $script:Ar.Rows[0].FirewallStatus | Should -BeExactly 'Success'
            $script:Ar.Rows[0].ErrorCount | Should -BeExactly 3
            $script:Ar.Rows[0].Errors[0] | Should -BeExactly 'Service: s1'
            $script:Ar.Rows[0].Errors[1] | Should -Match '^arrange: RemoteFirewall: \S'
            $script:Ar.Rows[0].Errors[2] | Should -Match '^arrange: RemoteRSOP: \S'
            $script:Ar.Rows[0].Error | Should -BeExactly 'Service: s1'
        }

        It 'lists the subfolder of a collector that could not be placed as null in host.json' {
            $hostJson = Read-JsonFile -Path (Join-Path -Path $script:Ar.Rows[0].OutputFolder -ChildPath 'host.json')
            $hostJson.Collectors[0].Subfolder | Should -BeNull
            $hostJson.Collectors[1].Subfolder | Should -BeExactly 'RemoteRSOP'
            $hostJson.Status | Should -BeExactly 'Partial'
        }
    }

    Context 'a host with no placeable folder at all' {
        It 'creates no host folder when the only computer folder cannot be placed' {
            $run = Invoke-FakeBaseline -Config @{ Entries = @{ RemoteService = @{ a1 = @{ FolderName = 'garbage' } } } } -Parameter @{ ComputerName = @('a1'); Type = @('Service') }
            $run.Rows[0].OutputFolder | Should -BeExactly ''
            (Get-ChildNameList -Path $run.RunFolder) | Should -BeExactly 'collectors,manifest.sha256,results.csv,run.json'
            $run.Rows[0].Errors[0] | Should -Match '^arrange: RemoteService: '
        }
    }

    Context 'host.json problems' {
        It 'adds a host.json line and keeps the identity from the next collector when the first system.json is not json' {
            $run = Invoke-FakeBaseline -Config @{ Entries = @{ RemoteFirewall = @{ a1 = @{ BadSystemJson = $true } } } } -Parameter @{ ComputerName = @('a1') }
            $run.Rows[0].Status | Should -BeExactly 'Partial'
            $run.Rows[0].Errors[0] | Should -Match '^host\.json: RemoteFirewall: system\.json: '
            (Read-JsonFile -Path (Join-Path -Path $run.Rows[0].OutputFolder -ChildPath 'host.json')).UBR | Should -BeExactly 5001
        }

        Context 'a host.json that cannot be written' {
            BeforeAll {
                Mock -ModuleName RemoteBaseline -CommandName Write-RemoteBaselineHostFile -MockWith { throw "cannot write`r`nthe host file" }
                $script:Hw = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1') }
            }

            It 'adds a one-line host.json line and makes the Success row Partial' {
                $script:Hw.Rows[0].Status | Should -BeExactly 'Partial'
                (@($script:Hw.Rows[0].Errors) -join '|') | Should -BeExactly 'host.json: cannot write the host file'
                (Test-Path -LiteralPath (Join-Path -Path $script:Hw.Rows[0].OutputFolder -ChildPath 'host.json')) | Should -BeFalse
            }
        }
    }

    Context 'a manifest that cannot be written' {
        BeforeAll {
            Mock -ModuleName RemoteBaseline -CommandName Write-RemoteBaselineManifest -MockWith { throw "disk full`r`nsecond" }
            $script:Mf = Invoke-FakeBaseline -Config @{ Entries = (Get-EntryForAllModule -PerName @{ NOSUCH = @{ Mode = 'Failed' } }) } -Parameter @{ ComputerName = @('a1', 'NOSUCH') }
        }

        It 'puts a manifest line in every row of the returned rows and makes every Success row Partial' {
            $script:Mf.Rows[0].Status | Should -BeExactly 'Partial'
            $script:Mf.Rows[0].Error | Should -BeExactly 'manifest: disk full second'
            $script:Mf.Rows[0].ErrorCount | Should -BeExactly 1
            $script:Mf.Rows[1].Errors[$script:Mf.Rows[1].Errors.Count - 1] | Should -BeExactly 'manifest: disk full second'
        }

        It 'leaves a Failed row Failed' {
            $script:Mf.Rows[1].Status | Should -BeExactly 'Failed'
        }

        It 'keeps the manifest line out of run.json, results.csv and host.json, which are inside the manifest' {
            foreach ($path in @((Join-Path -Path $script:Mf.RunFolder -ChildPath 'run.json'), (Join-Path -Path $script:Mf.RunFolder -ChildPath 'results.csv'), (Join-Path -Path $script:Mf.Rows[0].OutputFolder -ChildPath 'host.json'))) {
                (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'manifest:'
            }
            (Read-JsonFile -Path (Join-Path -Path $script:Mf.RunFolder -ChildPath 'run.json')).Results[0].Status | Should -BeExactly 'Success'
            (Test-Path -LiteralPath (Join-Path -Path $script:Mf.RunFolder -ChildPath 'manifest.sha256')) | Should -BeFalse
        }
    }
}

Describe 'ConvertTo-RemoteBaselineResultRow - Status rules' {
    It 'gives <Expected> for: <Name>' -ForEach $StatusCases {
        $collectorRow = @{}
        for ($i = 0; $i -lt 5; $i++) {
            $built = Get-CollectorRowFake -Status $S[$i]
            if ($null -ne $built) { $collectorRow[$script:AllTypes[$i]] = $built }
        }
        $row = & $script:Module {
            param($Types, $CollectorRow, $Extra)
            $hostName = 'WS01'
            ConvertTo-RemoteBaselineResultRow -ComputerName $hostName -Type $Types -CollectorRow $CollectorRow -OutputFolder '' -ExtraError $Extra
        } $script:AllTypes $collectorRow $Extra
        $row.Status | Should -BeExactly $Expected
    }

    It 'prefixes collector errors with the type in run order, then the umbrella lines, trimmed to one line each' {
        $collectorRow = @{
            Service  = Get-CollectorRowFake -Status 'Partial' -ErrorLine @('s1')
            Firewall = Get-CollectorRowFake -Status 'Partial' -ErrorLine @("f1`r`n  f1b ", 'f2')
        }
        $row = & $script:Module {
            param($CollectorRow)
            $hostName = 'WS01'
            ConvertTo-RemoteBaselineResultRow -ComputerName $hostName -Type @('Firewall', 'Service') -CollectorRow $CollectorRow -OutputFolder 'C:\x' -ExtraError @("arrange: M: a`r`nb", '  host.json: c  ')
        } $collectorRow
        (@($row.Errors) -join '|') | Should -BeExactly 'Firewall: f1 f1b|Firewall: f2|Service: s1|arrange: M: a b|host.json: c'
        $row.Error | Should -BeExactly 'Firewall: f1 f1b'
        $row.ErrorCount | Should -BeExactly 5
        $row.OutputFolder | Should -BeExactly 'C:\x'
        $row.RSOPStatus | Should -BeNull
    }
}

Describe 'Get-RemoteBaseline - warnings come after the rows and the files' {
    Context 'a caller with -WarningAction Stop' {
        BeforeAll {
            $script:W = [System.Collections.Generic.List[object]]::new()
            $script:WOut = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $script:WThrown = $null
            $config = @{ Entries = (Get-EntryForAllModule -PerName @{ NOSUCH = @{ Mode = 'Failed' } }) }
            [void](Register-FakeCollector -Config $config)
            try {
                Get-RemoteBaseline -ComputerName @('a1', 'NOSUCH', 'b2') -OutputPath $script:WOut -WarningAction Stop | ForEach-Object { [void]$script:W.Add($_) }
            } catch {
                $script:WThrown = $_
            }
        }

        It 'has every row before the first warning stops the call' {
            $script:WThrown | Should -Not -BeNull
            $script:WThrown.Exception.GetType().Name | Should -BeExactly 'ActionPreferenceStopException'
            $script:W.Count | Should -Be 3
            (@($script:W | ForEach-Object { $_.Status }) -join ',') | Should -BeExactly 'Success,Failed,Success'
        }

        It 'has run.json, results.csv and the manifest on disk by then' {
            $runFolder = @(Get-ChildItem -LiteralPath $script:WOut -Directory)[0].FullName
            (Get-ChildNameList -Path $runFolder) | Should -Match 'collectors,manifest\.sha256,results\.csv,run\.json$'
        }
    }
}

Describe 'Get-RemoteBaseline - -Compress' {
    Context 'a successful run' {
        BeforeAll {
            $script:Z = Invoke-FakeBaseline -Config $script:MixedConfig -Parameter @{ ComputerName = $script:MixedNames; Compress = $true }
            $script:ZipPath = $script:Z.RunFolder + '.zip'
            $script:Zip = [System.IO.Compression.ZipFile]::OpenRead($script:ZipPath)
        }

        AfterAll {
            if ($null -ne $script:Zip) { $script:Zip.Dispose() }
        }

        It 'writes the run folder name plus .zip beside the run folder' {
            (Test-Path -LiteralPath $script:ZipPath) | Should -BeTrue
            (Split-Path -Path $script:ZipPath -Parent) | Should -BeExactly $script:Z.OutputPath
            (Get-ChildNameList -Path $script:Z.OutputPath) | Should -BeExactly ((Split-Path -Path $script:Z.RunFolder -Leaf) + ',' + (Split-Path -Path $script:ZipPath -Leaf))
        }

        It 'contains run.json, with forward-slash entry names only' {
            $names = @($script:Zip.Entries | ForEach-Object { $_.FullName })
            $names | Should -Contain 'run.json'
            $names | Should -Contain 'manifest.sha256'
            @($names | Where-Object { $_ -match '\\' }).Count | Should -Be 0
            @($names | Where-Object { $_ -like 'collectors/RemoteFirewall/run.json' }).Count | Should -Be 1
        }

        It 'has one entry per file of the run folder, in the manifest sort order, with the files'' content' {
            $names = @($script:Zip.Entries | ForEach-Object { $_.FullName })
            (Get-RelativeFile -Root $script:Z.RunFolder) -join "`n" | Should -BeExactly ($names -join "`n")
            $sha = [System.Security.Cryptography.SHA256]::Create()
            foreach ($entry in $script:Zip.Entries) {
                $stream = $entry.Open()
                try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLowerInvariant() } finally { $stream.Dispose() }
                $hash | Should -BeExactly (Get-Sha256Hex -Path (Join-Path -Path $script:Z.RunFolder -ChildPath $entry.FullName.Replace('/', '\'))) -Because $entry.FullName
            }
        }

        It 'records the planned archive name in run.json, and no zip without -Compress' {
            $runJson = Read-JsonFile -Path (Join-Path -Path $script:Z.RunFolder -ChildPath 'run.json')
            $runJson.Compress | Should -BeTrue
            $runJson.Archive | Should -BeExactly ((Split-Path -Path $script:Z.RunFolder -Leaf) + '.zip')
            $plain = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1') }
            (Test-Path -LiteralPath ($plain.RunFolder + '.zip')) | Should -BeFalse
        }

        It 'does not list the zip in the manifest' {
            (Get-Content -LiteralPath (Join-Path -Path $script:Z.RunFolder -ChildPath 'manifest.sha256') -Raw) | Should -Not -Match '\.zip'
        }
    }

    Context 'the zip fails' {
        BeforeAll {
            Mock -ModuleName RemoteBaseline -CommandName Compress-RemoteBaselineRunFolder -MockWith { throw "no space`r`nleft" }
            $script:Zf = Invoke-FakeBaseline -Config @{ Entries = (Get-EntryForAllModule -PerName @{ NOSUCH = @{ Mode = 'Failed' } }) } -Parameter @{ ComputerName = @('a1', 'NOSUCH'); Compress = $true }
        }

        It 'puts a zip line in every row, makes the Success row Partial and leaves the run folder and no zip' {
            $script:Zf.Rows[0].Status | Should -BeExactly 'Partial'
            $script:Zf.Rows[0].Errors[$script:Zf.Rows[0].Errors.Count - 1] | Should -BeExactly 'zip: no space left'
            $script:Zf.Rows[1].Status | Should -BeExactly 'Failed'
            $script:Zf.Rows[1].Errors[$script:Zf.Rows[1].Errors.Count - 1] | Should -BeExactly 'zip: no space left'
            (Test-Path -LiteralPath ($script:Zf.RunFolder + '.zip')) | Should -BeFalse
            (Test-Path -LiteralPath (Join-Path -Path $script:Zf.RunFolder -ChildPath 'manifest.sha256')) | Should -BeTrue
        }

        It 'keeps the zip line out of run.json' {
            (Get-Content -LiteralPath (Join-Path -Path $script:Zf.RunFolder -ChildPath 'run.json') -Raw) | Should -Not -Match 'zip:'
        }
    }

    Context 'a zip that is already there' {
        It 'is never replaced or removed, and the rows carry a zip line' {
            $run = Invoke-FakeBaseline -Config @{ BlockZip = $true } -Parameter @{ ComputerName = @('a1'); Compress = $true }
            $run.Rows[0].Status | Should -BeExactly 'Partial'
            $run.Rows[0].Error | Should -Match '^zip: .*already exists'
            [System.IO.File]::ReadAllText($run.RunFolder + '.zip') | Should -BeExactly 'not a zip'
        }
    }
}

Describe 'Compress-RemoteBaselineRunFolder' {
    It 'removes the partial zip when a file cannot be read, and throws' {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path $folder -ItemType Directory | Out-Null
        [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'a.txt'), 'first')
        $locked = Join-Path -Path $folder -ChildPath 'b.txt'
        [System.IO.File]::WriteAllText($locked, 'second')
        $lock = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            { & $script:Module { param($Folder) Compress-RemoteBaselineRunFolder -RunFolder $Folder } $folder } | Should -Throw
        } finally {
            $lock.Dispose()
        }
        (Test-Path -LiteralPath ($folder + '.zip')) | Should -BeFalse
    }

    It 'gives every entry the file''s local last write time, to the two-second precision of a zip (section 13.4)' {
        # An even second, so the zip's two-second DOS time holds it exactly. On a computer whose UTC offset is zero this cannot tell local from UTC; elsewhere a UTC based entry time would differ by the offset.
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path (Join-Path -Path $folder -ChildPath 'sub') -ItemType Directory -Force | Out-Null
        $expected = @{
            'a.txt'     = [datetime]::new(2021, 3, 4, 13, 14, 16, [System.DateTimeKind]::Local)
            'sub/b.txt' = [datetime]::new(2022, 7, 21, 23, 59, 58, [System.DateTimeKind]::Local)
        }
        foreach ($relative in $expected.Keys) {
            $path = Join-Path -Path $folder -ChildPath $relative.Replace('/', '\')
            [System.IO.File]::WriteAllText($path, 'content')
            [System.IO.File]::SetLastWriteTime($path, $expected[$relative])
        }
        & $script:Module { param($Folder) Compress-RemoteBaselineRunFolder -RunFolder $Folder } $folder
        $zip = [System.IO.Compression.ZipFile]::OpenRead($folder + '.zip')
        try {
            @($zip.Entries).Count | Should -Be 2
            foreach ($entry in $zip.Entries) {
                $entry.LastWriteTime.DateTime | Should -Be $expected[$entry.FullName] -Because $entry.FullName
            }
        } finally {
            $zip.Dispose()
        }
    }
}

Describe 'Get-RemoteBaseline - output path' {
    It 'gives one Failed row per name with an output path line, no files and no collector call, when the path cannot be created' {
        $blocker = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($blocker, 'a file where a folder is needed')
        $run = Invoke-FakeBaseline -OutputPath (Join-Path -Path $blocker -ChildPath 'sub') -Parameter @{ ComputerName = @('a1', 'b2'); Compress = $true }
        $run.Rows.Count | Should -Be 2
        foreach ($row in $run.Rows) {
            $row.Status | Should -BeExactly 'Failed'
            $row.Error | Should -Match '^output path: \S'
            $row.Error | Should -Not -Match '[\r\n]'
            $row.ErrorCount | Should -BeExactly 1
            $row.OutputFolder | Should -BeExactly ''
            # Section 13.5: every selected type is Failed with 0 errors of its own, Transport is empty; null is for types that were not selected.
            $row.Transport | Should -BeExactly ''
            foreach ($typeName in $script:AllTypes) {
                $row.PSObject.Properties[$typeName + 'Status'].Value | Should -BeExactly 'Failed' -Because $typeName
                $row.PSObject.Properties[$typeName + 'ErrorCount'].Value | Should -BeExactly 0 -Because $typeName
            }
        }
        $run.State.Calls.Count | Should -Be 0
        $run.Warnings.Count | Should -Be 2
    }

    It 'gives only the selected types Failed and 0 on the output path failure, and null for the others' {
        $blocker = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($blocker, 'a file where a folder is needed')
        $run = Invoke-FakeBaseline -OutputPath (Join-Path -Path $blocker -ChildPath 'sub') -Parameter @{ ComputerName = @('a1'); Type = @('Service', 'Firewall') }
        $row = $run.Rows[0]
        $row.FirewallStatus | Should -BeExactly 'Failed'
        $row.ServiceStatus | Should -BeExactly 'Failed'
        $row.FirewallErrorCount | Should -BeExactly 0
        $row.ServiceErrorCount | Should -BeExactly 0
        foreach ($column in @('RSOPStatus', 'ScheduledTaskStatus', 'SecEditStatus', 'RSOPErrorCount', 'ScheduledTaskErrorCount', 'SecEditErrorCount')) {
            $row.$column | Should -BeNull -Because $column
        }
        $row.Status | Should -BeExactly 'Failed'
        $row.ErrorCount | Should -BeExactly 1
    }

    It 'gives the same Failed and 0 columns in the last-resort catch, with the host line as the only error' {
        Mock -ModuleName RemoteBaseline -CommandName Get-RemoteBaselineHostIdentity -MockWith { throw "identity gone`r`nsecond line" }
        $run = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1', 'b2') }
        $run.Rows.Count | Should -Be 2
        foreach ($row in $run.Rows) {
            $row.Status | Should -BeExactly 'Failed'
            $row.Transport | Should -BeExactly ''
            $row.OutputFolder | Should -BeExactly ''
            $row.Error | Should -BeExactly 'host: identity gone second line'
            $row.ErrorCount | Should -BeExactly 1
            foreach ($typeName in $script:AllTypes) {
                $row.PSObject.Properties[$typeName + 'Status'].Value | Should -BeExactly 'Failed' -Because $typeName
                $row.PSObject.Properties[$typeName + 'ErrorCount'].Value | Should -BeExactly 0 -Because $typeName
            }
        }
        $run.State.Calls.Count | Should -Be 0
    }

    It 'resolves a relative OutputPath against the current location' {
        Push-Location -LiteralPath $TestDrive
        try {
            $run = Invoke-FakeBaseline -OutputPath '.\relative-out' -Parameter @{ ComputerName = @('a1') }
        } finally {
            Pop-Location
        }
        $run.Rows[0].OutputFolder | Should -BeLike ((Join-Path -Path $TestDrive -ChildPath 'relative-out') + '\RemoteBaseline-*')
        $run.State.Calls[0].OutputPath | Should -BeLike ((Join-Path -Path $TestDrive -ChildPath 'relative-out') + '\RemoteBaseline-*\collectors')
    }

    Context 'the path budget of Windows PowerShell 5.1' {
        BeforeAll {
            # An output path of an exact length under TestDrive, so the length in the message is known.
            function Get-PathOfLength {
                param([int]$Length)
                return ($TestDrive + '\' + ('p' * ($Length - $TestDrive.Length - 1)))
            }
            function Get-BudgetMessage {
                param([int]$Length)
                return ('output path: {0} characters; Windows PowerShell 5.1 limits a path to 260 and the collection needs about 150 below the output path, use a path of at most 105 characters' -f $Length)
            }
        }

        It 'gives every name a Failed row with the exact message and writes nothing for a path of 106 or 120 characters on the Desktop edition' {
            Mock -ModuleName RemoteBaseline -CommandName Test-RemoteBaselineDesktopEdition -MockWith { $true }
            foreach ($length in 106, 120) {
                $out = Get-PathOfLength -Length $length
                $run = Invoke-FakeBaseline -OutputPath $out -Parameter @{ ComputerName = @('a1', 'b2'); Compress = $true }
                $run.Rows.Count | Should -Be 2
                foreach ($row in $run.Rows) {
                    $row.Status | Should -BeExactly 'Failed'
                    $row.Error | Should -BeExactly (Get-BudgetMessage -Length $length)
                    $row.ErrorCount | Should -BeExactly 1
                    $row.OutputFolder | Should -BeExactly ''
                }
                (Test-Path -LiteralPath $out) | Should -BeFalse
                $run.State.Calls.Count | Should -Be 0
            }
        }

        It 'lets a path of exactly 105 characters through on the Desktop edition' {
            Mock -ModuleName RemoteBaseline -CommandName Test-RemoteBaselineDesktopEdition -MockWith { $true }
            $run = Invoke-FakeBaseline -OutputPath (Get-PathOfLength -Length 105) -Parameter @{ ComputerName = @('a1') }
            $run.Rows[0].Status | Should -BeExactly 'Success'
        }

        It 'gives the same row for 120 characters on the real Desktop edition, no mock' {
            if ($PSVersionTable.PSEdition -eq 'Core') { Set-ItResult -Skipped -Because 'Desktop edition only'; return }
            $run = Invoke-FakeBaseline -OutputPath (Get-PathOfLength -Length 120) -Parameter @{ ComputerName = @('a1') }
            $run.Rows[0].Error | Should -BeExactly (Get-BudgetMessage -Length 120)
        }

        It 'lets a 120 character path proceed on the real Core edition, no mock' {
            if ($PSVersionTable.PSEdition -ne 'Core') { Set-ItResult -Skipped -Because 'Core edition only'; return }
            $run = Invoke-FakeBaseline -OutputPath (Get-PathOfLength -Length 120) -Parameter @{ ComputerName = @('a1') }
            $run.Rows[0].Status | Should -BeExactly 'Success'
        }
    }

    It 'gives a second run in the same second its own folder with a _2 suffix' {
        $out = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $path = & $script:Module {
            param($Out)
            $first = Initialize-RemoteBaselineRunFolder -OutputPath $Out
            $second = Initialize-RemoteBaselineRunFolder -OutputPath $Out
            @($first, $second)
        } $out
        $path[1] | Should -BeExactly ($path[0] + '_2')
        (Test-Path -LiteralPath (Join-Path -Path $path[1] -ChildPath 'collectors')) | Should -BeTrue
        (Get-ChildNameList -Path $path[0]) | Should -BeExactly 'collectors'
    }
}

Describe 'The module''s helpers' {
    It 'Resolve-RemoteBaselineUniqueFolder creates the folder, then _2 and _3, without overwriting' {
        $base = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $made = & $script:Module { param($Base) @((Resolve-RemoteBaselineUniqueFolder -Path $Base), (Resolve-RemoteBaselineUniqueFolder -Path $Base), (Resolve-RemoteBaselineUniqueFolder -Path $Base)) } $base
        ($made -join '|') | Should -BeExactly ($base + '|' + $base + '_2|' + $base + '_3')
    }

    It 'Get-RemoteBaselineCollectorInfo maps type to module, function and subfolder in run order, collapsing duplicates and case' {
        $info = @(& $script:Module { Get-RemoteBaselineCollectorInfo -Type @('service', 'FIREWALL', 'Service', 'secedit') })
        (@($info | ForEach-Object { $_.Type }) -join ',') | Should -BeExactly 'Firewall,SecEdit,Service'
        $all = @(& $script:Module { Get-RemoteBaselineCollectorInfo -Type @() })
        $all.Count | Should -Be 5
        foreach ($case in $script:TypeCases) {
            $entry = @($all | Where-Object { $_.Type -eq $case.Type })[0]
            $entry.Module | Should -BeExactly $case.Module
            $entry.Function | Should -BeExactly $case.Function
            $entry.Subfolder | Should -BeExactly $case.Module
        }
        (@($all | ForEach-Object { $_.Type }) -join ',') | Should -BeExactly ($script:AllTypes -join ',')
    }

    It 'Move-RemoteBaselineComputerFolder parses the leaf from the right (name with underscores, build, stamp, suffix)' {
        $run = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $runFolder = Join-Path -Path $run -ChildPath 'RemoteBaseline-20261001-101112Z'
        $source = Join-Path -Path (Join-Path -Path (Join-Path -Path $runFolder -ChildPath 'collectors') -ChildPath 'RemoteService') -ChildPath 'MY_HOST_20348_20200101-000102Z_2'
        New-Item -Path $source -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path -Path $source -ChildPath 'system.json'), '{}')
        $outcome = @(& $script:Module {
                param($Source, $RunFolder)
                $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
                Move-RemoteBaselineComputerFolder -Module 'RemoteService' -Row @([pscustomobject]@{ ComputerName = 'my_host'; OutputFolder = $Source }) -RunFolder $RunFolder -CollectorFolder (Split-Path -Path $Source -Parent) -HostMap $map
            } $source $runFolder)
        $expected = Join-Path -Path $runFolder -ChildPath 'MY_HOST_20348_20261001-101112Z'
        $outcome[0].HostFolder | Should -BeExactly $expected
        $outcome[0].Error | Should -BeNull
        (Test-Path -LiteralPath (Join-Path -Path (Join-Path -Path $expected -ChildPath 'RemoteService') -ChildPath 'system.json')) | Should -BeTrue
        (Test-Path -LiteralPath $source) | Should -BeFalse
    }

    It 'Get-RemoteBaselineHostIdentity returns the upper-case CIM UUID, and null when CIM fails' {
        Mock -ModuleName RemoteBaseline -CommandName Get-CimInstance -MockWith { [pscustomobject]@{ UUID = 'aabbccdd-0000-1111-2222-333344445555' } }
        $identity = & $script:Module { Get-RemoteBaselineHostIdentity }
        $identity.HostComputerId | Should -BeExactly 'AABBCCDD-0000-1111-2222-333344445555'
        (@($identity.PSObject.Properties.Name) -join ',') | Should -BeExactly 'HostComputer,HostComputerId,HostUser,PSVersion,StartUtc'
        $identity.StartUtc | Should -Match $script:IsoPattern
        Mock -ModuleName RemoteBaseline -CommandName Get-CimInstance -MockWith { throw 'CIM deliberately unavailable' }
        (& $script:Module { Get-RemoteBaselineHostIdentity }).HostComputerId | Should -BeNull
    }

    It 'Write-RemoteBaselineCsvFile writes a byte order mark, one line per cell, a bare null and a header-only file for no rows' {
        $path = Join-Path -Path $TestDrive -ChildPath 'rows.csv'
        & $script:Module { param($Path) Write-RemoteBaselineCsvFile -Row @([pscustomobject]@{ A = "a`r`nb  c"; B = $null; C = ''; D = 7 }) -Path $Path } $path
        $lines = [System.IO.File]::ReadAllLines($path)
        $lines.Count | Should -Be 2
        $lines[1] | Should -BeExactly '"a b c",,"","7"'
        ([System.IO.File]::ReadAllBytes($path)[0..2] -join ',') | Should -BeExactly '239,187,191'
        $empty = Join-Path -Path $TestDrive -ChildPath 'empty.csv'
        & $script:Module { param($Path) Write-RemoteBaselineCsvFile -Row @() -Path $Path -Column @('A', 'B') } $empty
        [System.IO.File]::ReadAllLines($empty).Count | Should -Be 1
        [System.IO.File]::ReadAllLines($empty)[0].TrimStart([char]0xFEFF) | Should -BeExactly '"A","B"'
    }

    It 'Write-RemoteBaselineManifest leaves no partial manifest when a hash fails' {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path $folder -ItemType Directory | Out-Null
        [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'a.txt'), 'x')
        Mock -ModuleName RemoteBaseline -CommandName Get-FileHash -MockWith { throw 'hash deliberately failed' }
        { & $script:Module { param($Folder) Write-RemoteBaselineManifest -RunFolder $Folder } $folder } | Should -Throw '*hash deliberately failed*'
        (Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'manifest.sha256')) | Should -BeFalse
    }

    It 'ConvertTo-RemoteBaselineOneLine trims and collapses whitespace and line breaks, and turns null into an empty string' {
        (& $script:Module { ConvertTo-RemoteBaselineOneLine -Text "  a`r`n b`t c  " }) | Should -BeExactly 'a b c'
        (& $script:Module { ConvertTo-RemoteBaselineOneLine -Text $null }) | Should -BeExactly ''
    }
}

Describe 'Bundle integrity, DESIGN.md section 9' {
    BeforeAll {
        $script:ModulesRoot = Join-Path -Path $script:ModuleFolder -ChildPath 'Modules'
        $script:ModulesRootFull = (Get-Item -LiteralPath $script:ModulesRoot).FullName.TrimEnd('\')
    }

    It 'lists the five modules of the bundle in alphabetical order in bundle.json' {
        (@($script:Bundle.Modules | ForEach-Object { $_.Module }) -join ',') | Should -BeExactly ($script:AllModules -join ',')
    }

    It 'has the hash bundle.json records for every file of <Module>' -ForEach $TypeCases {
        $entry = @($script:Bundle.Modules | Where-Object { $_.Module -eq $Module })[0]
        @($entry.Files).Count | Should -BeGreaterThan 3
        $bad = @(foreach ($file in $entry.Files) {
                $path = Join-Path -Path $script:ModulesRootFull -ChildPath $file.Path.Replace('/', '\')
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $file.Path + ' (missing)' }
                elseif ((Get-Sha256Hex -Path $path) -ne $file.Sha256) { $file.Path + ' (hash differs)' }
            })
        $bad.Count | Should -Be 0 -Because ($bad -join '; ')
    }

    It 'has no file under Modules\ that bundle.json does not list, and lists none that is missing' {
        $recorded = @($script:Bundle.Modules | ForEach-Object { $_.Files | ForEach-Object { $_.Path } })
        $onDisk = @(Get-ChildItem -LiteralPath $script:ModulesRoot -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($script:ModulesRootFull.Length + 1).Replace('\', '/') } | Where-Object { $_ -ne 'bundle.json' })
        $extra = @($onDisk | Where-Object { $recorded -notcontains $_ })
        $missing = @($recorded | Where-Object { $onDisk -notcontains $_ })
        $extra.Count | Should -Be 0 -Because ('extra: ' + ($extra -join ', '))
        $missing.Count | Should -Be 0 -Because ('missing: ' + ($missing -join ', '))
        @($recorded | Select-Object -Unique).Count | Should -Be $recorded.Count
    }

    It 'has a bundled manifest of <Module> whose ModuleVersion equals bundle.json' -ForEach $TypeCases {
        $entry = @($script:Bundle.Modules | Where-Object { $_.Module -eq $Module })[0]
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path -Path (Join-Path -Path $script:ModulesRoot -ChildPath $Module) -ChildPath ($Module + '.psd1'))
        $manifest.ModuleVersion | Should -BeExactly $entry.Version
    }

    It 'names exactly the five bundled manifests as NestedModules' {
        $data = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
        (@($data.NestedModules) -join '|') | Should -BeExactly ((@($script:AllModules | ForEach-Object { 'Modules\' + $_ + '\' + $_ + '.psd1' })) -join '|')
        foreach ($nested in $data.NestedModules) { (Test-Path -LiteralPath (Join-Path -Path $script:ModuleFolder -ChildPath $nested) -PathType Leaf) | Should -BeTrue }
        (@($script:Module.NestedModules | ForEach-Object { $_.Name } | Sort-Object) -join ',') | Should -BeExactly ($script:AllModules -join ',')
    }

    It 'exports only Get-RemoteBaseline' {
        (@($script:Module.ExportedFunctions.Keys) -join ',') | Should -BeExactly 'Get-RemoteBaseline'
        $script:Module.ExportedCmdlets.Count | Should -Be 0
        $script:Module.ExportedAliases.Count | Should -Be 0
        $script:Module.ExportedVariables.Count | Should -Be 0
        (@(Get-Command -Module RemoteBaseline | ForEach-Object { $_.Name }) -join ',') | Should -BeExactly 'Get-RemoteBaseline'
    }

    It 'resolves <Function> through the resolver from under the module folder, at the bundled version' -ForEach $TypeCases {
        $resolved = & $script:Module { param($ModuleName, $FunctionName) Get-RemoteBaselineCollectorCommand -Module $ModuleName -Function $FunctionName } $Module $Function
        $resolved.Command | Should -BeOfType ([System.Management.Automation.FunctionInfo])
        $resolved.Command.Name | Should -BeExactly $Function
        $base = $resolved.Command.Module.ModuleBase
        $base.StartsWith($script:ModuleFolder, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue -Because $base
        $base.StartsWith($script:ModulesRootFull, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue -Because $base
        $resolved.Command.Module.Name | Should -BeExactly $Module
        $resolved.Version | Should -BeExactly (@($script:Bundle.Modules | Where-Object { $_.Module -eq $Module })[0]).Version
        $resolved.Version | Should -BeExactly $resolved.Command.Module.Version.ToString()
    }

    It 'throws the line collector NAME not bundled for a module this module does not carry, or a function it does not export' {
        { & $script:Module { Get-RemoteBaselineCollectorCommand -Module 'RemoteNothing' -Function 'Get-Nothing' } } | Should -Throw '*collector RemoteNothing not bundled*'
        { & $script:Module { Get-RemoteBaselineCollectorCommand -Module 'RemoteService' -Function 'Get-FirewallInventory' } } | Should -Throw '*collector RemoteService not bundled*'
    }

    It 'does not put a loaded copy of a bundled collector from under this module into the caller''s session' {
        $inSession = @(Get-Module | Where-Object { $script:AllModules -contains $_.Name -and $_.ModuleBase.StartsWith($script:ModuleFolder, [System.StringComparison]::OrdinalIgnoreCase) })
        $inSession.Count | Should -Be 0
    }
}

Describe 'Get-RemoteBaseline - the bundled collector is called, not whatever has its name (section 13.1)' {
    BeforeAll {
        # Command lookup checks aliases before functions in every scope, so a decoy alias in the session wins a lookup by name; a decoy function is added for the other three types. The real resolver and the real bundled collectors are used here, no mock.
        # The decoy records its calls in a list its closure holds, so no global variable is needed.
        $script:DecoyCalls = [System.Collections.Generic.List[string]]::new()
        $calls = $script:DecoyCalls
        $decoy = { [void]$calls.Add('decoy ran'); 'decoy row' }.GetNewClosure()
        $script:DecoyAlias = @('Get-ScheduledTaskInventory', 'Get-ServiceInventory')
        Set-Item -Path 'Function:\global:Invoke-RbDecoy' -Value $decoy
        foreach ($case in $script:TypeCases) {
            if ($script:DecoyAlias -contains $case.Function) {
                Set-Alias -Name $case.Function -Value 'Invoke-RbDecoy' -Scope Global
            } else {
                Set-Item -Path ('Function:\global:' + $case.Function) -Value $decoy
            }
        }
    }

    AfterAll {
        foreach ($case in $script:TypeCases) {
            if ($script:DecoyAlias -contains $case.Function) {
                Remove-Item -Path ('Alias:\' + $case.Function) -Force -ErrorAction SilentlyContinue
            } else {
                # Not global:-qualified: from this child scope the plain name finds the global function and removes it, the qualified path does not.
                Remove-Item -Path ('Function:\' + $case.Function) -Force -ErrorAction SilentlyContinue
            }
        }
        Remove-Item -Path 'Function:\Invoke-RbDecoy' -Force -ErrorAction SilentlyContinue
    }

    It 'has the alias win a lookup by name inside the module, so the setup is in effect: <Function>' -ForEach $TypeCases {
        $kind = & $script:Module { param($FunctionName) (Get-Command -Name $FunctionName -ErrorAction Stop | Select-Object -First 1).CommandType.ToString() } $Function
        if ($script:DecoyAlias -contains $Function) { $kind | Should -BeExactly 'Alias' }
        else { $kind | Should -BeIn @('Function', 'Alias') }
    }

    It 'resolves <Function> to the bundled copy whatever the session holds, ModuleBase under the module''s Modules folder' -ForEach $TypeCases {
        $resolved = & $script:Module { param($ModuleName, $FunctionName) Get-RemoteBaselineCollectorCommand -Module $ModuleName -Function $FunctionName } $Module $Function
        $resolved.Command.CommandType.ToString() | Should -BeExactly 'Function'
        $resolved.Command.Module.ModuleBase.StartsWith($script:ModulesRootFull, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue -Because $resolved.Command.Module.ModuleBase
        $resolved.Command.Module.Name | Should -BeExactly $Module
        $resolved.Version | Should -BeExactly (@($script:Bundle.Modules | Where-Object { $_.Module -eq $Module })[0]).Version
    }

    It 'runs the bundled <Function> in Invoke-RemoteBaselineCollector and never the decoy, with the bundled version' -ForEach $TypeCases {
        # The staging path sits under a file, so the real collector's own output path step throws at once (a few milliseconds) and nothing is collected. That throw is the proof the real function ran: the decoy returns a string and throws nothing.
        $blocker = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($blocker, 'a file where a folder is needed')
        $result = & $script:Module {
            param($TypeName, $Staging)
            Invoke-RemoteBaselineCollector -Type $TypeName -ComputerName @('a1') -StagingPath $Staging -ThrottleLimit 1
        } $Type (Join-Path -Path $blocker -ChildPath 'sub')
        $script:DecoyCalls.Count | Should -Be 0
        $result.Error | Should -Not -BeNullOrEmpty
        $result.Error | Should -Not -Match 'no result row'
        $result.Version | Should -BeExactly (@($script:Bundle.Modules | Where-Object { $_.Module -eq $Module })[0]).Version
        $result.Rows[0].Status | Should -BeExactly 'Failed'
        $result.Rows[0].Error | Should -BeExactly ('host: ' + $result.Error)
    }
}

Describe 'Get-RemoteBaseline - a collector that is not bundled, or reports a folder outside the staging folder (section 13.1)' {
    Context 'a nested module that is not there' {
        BeforeAll {
            $script:Nb = Invoke-FakeBaseline -Config @{ NotBundled = @('RemoteRSOP') } -Parameter @{ ComputerName = @('a1', 'b2') }
        }

        It 'gives every name a synthetic Failed row for that collector, host: collector NAME not bundled, and completes the run' {
            @($script:Nb.Rows | ForEach-Object { $_.Status }) -join ',' | Should -BeExactly 'Partial,Partial'
            foreach ($row in $script:Nb.Rows) {
                $row.RSOPStatus | Should -BeExactly 'Failed'
                (@($row.Errors) -join '|') | Should -BeExactly 'RSOP: host: collector RemoteRSOP not bundled'
            }
            $script:Nb.State.Calls.Count | Should -Be 4
        }

        It 'records the message and no version for it in run.json' {
            $rsop = (Read-JsonFile -Path (Join-Path -Path $script:Nb.RunFolder -ChildPath 'run.json')).Collectors[1]
            $rsop.Error | Should -BeExactly 'collector RemoteRSOP not bundled'
            $rsop.Version | Should -BeNull
            $rsop.RunId | Should -BeNull
        }
    }

    Context 'an OutputFolder outside the staging folder' {
        BeforeAll {
            $config = @{ Entries = @{ RemoteFirewall = @{ a1 = @{ Outside = $true } } } }
            $script:Os = Invoke-FakeBaseline -Config $config -Parameter @{ ComputerName = @('a1'); Type = @('Firewall') }
            $script:OsRoot = Join-Path -Path $script:Os.OutputPath -ChildPath 'outside'
            $script:OsRun = Join-Path -Path $script:OsRoot -ChildPath 'RemoteFirewall-20200101-000102Z'
            $script:OsComputer = Join-Path -Path $script:OsRun -ChildPath 'A1_20348_20200101-000102Z'
        }

        It 'renames nothing: the folder the row named keeps its name, and no module-named folder appears beside it or in collectors' {
            (Test-Path -LiteralPath $script:OsRun -PathType Container) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path -Path $script:OsRoot -ChildPath 'RemoteFirewall')) | Should -BeFalse
            (Get-ChildNameList -Path (Join-Path -Path $script:Os.RunFolder -ChildPath 'collectors')) | Should -BeExactly 'RemoteFirewall-20200101-000102Z'
        }

        It 'moves nothing: the computer folder and its files stay, and no host folder is created' {
            (Test-Path -LiteralPath (Join-Path -Path $script:OsComputer -ChildPath 'system.json')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path -Path $script:OsComputer -ChildPath 'subject.json')) | Should -BeTrue
            (Get-ChildNameList -Path $script:Os.RunFolder) | Should -BeExactly 'collectors,manifest.sha256,results.csv,run.json'
            $script:Os.Rows[0].OutputFolder | Should -BeExactly ''
        }

        It 'puts the arrange line for the refused rename and the refused move on the row, and makes it Partial' {
            $script:Os.Rows[0].Errors | Should -Contain ('arrange: RemoteFirewall: path outside the staging folder: ' + $script:OsRun)
            $script:Os.Rows[0].Errors | Should -Contain ('arrange: RemoteFirewall: path outside the staging folder: ' + $script:OsComputer)
            $script:Os.Rows[0].Status | Should -BeExactly 'Partial'
        }
    }
}

Describe 'Get-RemoteBaseline - run.json and results.csv that cannot be written (section 13.2)' {
    Context 'run.json' {
        BeforeAll {
            Register-TextWriterFailure -FileName 'run.json' -Message "disk full`r`nsecond"
            $script:Rj = Invoke-FakeBaseline -Config @{ Entries = (Get-EntryForAllModule -PerName @{ NOSUCH = @{ Mode = 'Failed' } }) } -Parameter @{ ComputerName = @('a1', 'NOSUCH'); Compress = $true }
        }

        It 'puts one run.json line in every row, makes the Success row Partial and leaves the Failed row Failed' {
            $script:Rj.Rows[0].Status | Should -BeExactly 'Partial'
            $script:Rj.Rows[0].Error | Should -BeExactly 'run.json: disk full second'
            $script:Rj.Rows[0].ErrorCount | Should -BeExactly 1
            $script:Rj.Rows[1].Status | Should -BeExactly 'Failed'
            $script:Rj.Rows[1].Errors[$script:Rj.Rows[1].Errors.Count - 1] | Should -BeExactly 'run.json: disk full second'
        }

        It 'writes no warning in the middle of the run, only the one per row that is not Success' {
            $script:Rj.Warnings.Count | Should -Be 2
            @($script:Rj.Warnings | Where-Object { $_ -match 'Failed to write' }).Count | Should -Be 0
        }

        It 'still writes results.csv, the manifest over what exists, and the zip' {
            (Test-Path -LiteralPath (Join-Path -Path $script:Rj.RunFolder -ChildPath 'run.json')) | Should -BeFalse
            (Test-Path -LiteralPath (Join-Path -Path $script:Rj.RunFolder -ChildPath 'results.csv')) | Should -BeTrue
            $manifest = Get-Content -LiteralPath (Join-Path -Path $script:Rj.RunFolder -ChildPath 'manifest.sha256') -Raw
            $manifest | Should -Match 'results\.csv'
            $manifest | Should -Not -Match '(?m)^[0-9a-f]{64}  run\.json$'
            (Test-Path -LiteralPath ($script:Rj.RunFolder + '.zip')) | Should -BeTrue
        }

        It 'keeps the line out of results.csv, which is on disk' {
            (Get-Content -LiteralPath (Join-Path -Path $script:Rj.RunFolder -ChildPath 'results.csv') -Raw) | Should -Not -Match 'run\.json:'
        }
    }

    Context 'results.csv' {
        BeforeAll {
            Mock -ModuleName RemoteBaseline -CommandName Write-RemoteBaselineCsvFile -ParameterFilter { $Path -like '*results.csv' } -MockWith { throw "locked`r`nby another process" }
            $script:Rc = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1', 'b2'); Compress = $true }
        }

        It 'puts one results.csv line in every row and makes every Success row Partial' {
            foreach ($row in $script:Rc.Rows) {
                $row.Status | Should -BeExactly 'Partial'
                $row.Error | Should -BeExactly 'results.csv: locked by another process'
            }
        }

        It 'writes no mid-run warning, and still writes run.json, the manifest and the zip' {
            $script:Rc.Warnings.Count | Should -Be 2
            @($script:Rc.Warnings | Where-Object { $_ -match 'Failed to write' }).Count | Should -Be 0
            (Test-Path -LiteralPath (Join-Path -Path $script:Rc.RunFolder -ChildPath 'results.csv')) | Should -BeFalse
            (Test-Path -LiteralPath (Join-Path -Path $script:Rc.RunFolder -ChildPath 'run.json')) | Should -BeTrue
            (Get-Content -LiteralPath (Join-Path -Path $script:Rc.RunFolder -ChildPath 'manifest.sha256') -Raw) | Should -Match 'run\.json'
            (Test-Path -LiteralPath ($script:Rc.RunFolder + '.zip')) | Should -BeTrue
        }
    }

    Context 'a caller with -WarningAction Stop and a run.json that cannot be written' {
        BeforeAll {
            Register-TextWriterFailure -FileName 'run.json' -Message 'disk full'
            [void](Register-FakeCollector)
            $script:Rs = [System.Collections.Generic.List[object]]::new()
            $script:RsThrown = $null
            try {
                Get-RemoteBaseline -ComputerName @('a1', 'b2') -OutputPath (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))) -WarningAction Stop | ForEach-Object { [void]$script:Rs.Add($_) }
            } catch {
                $script:RsThrown = $_
            }
        }

        It 'loses no row: both rows arrive with the run.json line, and none is turned into a host: failure' {
            $script:Rs.Count | Should -Be 2
            foreach ($row in $script:Rs) {
                $row.Status | Should -BeExactly 'Partial'
                (@($row.Errors) -join '|') | Should -BeExactly 'run.json: disk full'
                $row.FirewallStatus | Should -BeExactly 'Success'
            }
        }

        It 'stops only at the first per-row warning, after the rows' {
            $script:RsThrown | Should -Not -BeNull
            $script:RsThrown.Exception.GetType().Name | Should -BeExactly 'ActionPreferenceStopException'
        }
    }
}

Describe 'Get-RemoteBaseline - the arrangement is retried, section 13.6' {
    Context 'a normal run' {
        It 'never sleeps' {
            $run = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1', 'b2') }
            $run.Rows[0].Status | Should -BeExactly 'Success'
            Should -Invoke -ModuleName RemoteBaseline -CommandName Start-Sleep -Exactly -Times 0
        }
    }

    Context 'a move that fails twice and succeeds the third time' {
        BeforeAll {
            $script:MoveCount = 0
            Mock -ModuleName RemoteBaseline -CommandName Move-Item -MockWith {
                $script:MoveCount++
                if ($script:MoveCount -le 2) { throw 'The process cannot access the file because it is being used by another process.' }
                Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
            }
            $script:Rt = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1'); Type = @('Service') }
        }

        It 'gives no arrange line and a Success row, with the folder where it belongs' {
            $script:MoveCount | Should -Be 3
            $script:Rt.Rows[0].Status | Should -BeExactly 'Success'
            @($script:Rt.Rows[0].Errors | Where-Object { $_ -like 'arrange:*' }).Count | Should -Be 0
            (Test-Path -LiteralPath (Join-Path -Path (Join-Path -Path $script:Rt.Rows[0].OutputFolder -ChildPath 'RemoteService') -ChildPath 'system.json')) | Should -BeTrue
        }

        It 'sleeps 500 ms after each of the two failures and not after the success' {
            Should -Invoke -ModuleName RemoteBaseline -CommandName Start-Sleep -Scope Context -Exactly -Times 2 -ParameterFilter { $Milliseconds -eq 500 }
        }
    }

    Context 'a move that fails every time' {
        BeforeAll {
            $script:MoveCount = 0
            Mock -ModuleName RemoteBaseline -CommandName Move-Item -MockWith {
                $script:MoveCount++
                throw 'The process cannot access the file because it is being used by another process.'
            }
            $script:Rf = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1'); Type = @('Service') }
        }

        It 'tries three times, sleeps twice, then gives the arrange line and leaves the folder in collectors' {
            $script:MoveCount | Should -Be 3
            Should -Invoke -ModuleName RemoteBaseline -CommandName Start-Sleep -Scope Context -Exactly -Times 2
            $script:Rf.Rows[0].Errors[0] | Should -Match '^arrange: RemoteService: The process cannot access the file'
            $script:Rf.Rows[0].Status | Should -BeExactly 'Partial'
            $script:Rf.Rows[0].OutputFolder | Should -BeExactly ''
            (Test-Path -LiteralPath (Join-Path -Path (Join-Path -Path (Join-Path -Path $script:Rf.RunFolder -ChildPath 'collectors') -ChildPath 'RemoteService') -ChildPath 'A1_20348_20200101-000102Z')) | Should -BeTrue
        }
    }

    Context 'a rename of the collector run folder that fails twice and succeeds the third time' {
        BeforeAll {
            $script:RenameCount = 0
            Mock -ModuleName RemoteBaseline -CommandName Rename-Item -MockWith {
                $script:RenameCount++
                if ($script:RenameCount -le 2) { throw 'Access to the path is denied.' }
                Microsoft.PowerShell.Management\Rename-Item -LiteralPath $LiteralPath -NewName $NewName
            }
            $script:Rr = Invoke-FakeBaseline -Parameter @{ ComputerName = @('a1'); Type = @('Service') }
        }

        It 'gives no arrange line, has renamed the folder, and slept twice' {
            $script:RenameCount | Should -Be 3
            $script:Rr.Rows[0].Status | Should -BeExactly 'Success'
            (Get-ChildNameList -Path (Join-Path -Path $script:Rr.RunFolder -ChildPath 'collectors')) | Should -BeExactly 'RemoteService'
            Should -Invoke -ModuleName RemoteBaseline -CommandName Start-Sleep -Scope Context -Exactly -Times 2 -ParameterFilter { $Milliseconds -eq 500 }
        }
    }

    Context 'a failure that cannot pass, a name that is taken' {
        It 'is refused at once without a retry or a sleep' {
            $run = Invoke-FakeBaseline -Config @{ BlockRename = @('RemoteRSOP') } -Parameter @{ ComputerName = @('a1') }
            @($run.Rows[0].Errors | Where-Object { $_ -like 'arrange: RemoteRSOP: *' }).Count | Should -Be 1
            Should -Invoke -ModuleName RemoteBaseline -CommandName Start-Sleep -Exactly -Times 0
        }
    }
}

Describe 'Get-RemoteBaseline - a Failed row that carries a computer folder (section 13.7)' {
    Context 'RSOP Failed with a folder, as an unelevated run writes it' {
        BeforeAll {
            $config = @{ Entries = @{ RemoteRSOP = @{ a1 = @{ Mode = 'FailedWithFolder'; Errors = @('not elevated: gpresult needs administrative rights') } } } }
            $script:Fw = Invoke-FakeBaseline -Config $config -Parameter @{ ComputerName = @('a1') }
            $script:FwHost = $script:Fw.Rows[0].OutputFolder
        }

        It 'moves the folder under the host folder like any other, and the collector row stays Failed' {
            $script:FwHost | Should -Not -BeNullOrEmpty
            (Test-Path -LiteralPath (Join-Path -Path (Join-Path -Path $script:FwHost -ChildPath 'RemoteRSOP') -ChildPath 'system.json')) | Should -BeTrue
            (Get-ChildNameList -Path $script:FwHost) | Should -BeExactly 'RemoteFirewall,RemoteRSOP,RemoteScheduledTask,RemoteSecEdit,RemoteService,host.json'
            (Get-ChildNameList -Path (Join-Path -Path (Join-Path -Path $script:Fw.RunFolder -ChildPath 'collectors') -ChildPath 'RemoteRSOP')) | Should -BeExactly 'results.csv,run.json'
            $script:Fw.Rows[0].RSOPStatus | Should -BeExactly 'Failed'
            $script:Fw.Rows[0].RSOPErrorCount | Should -BeExactly 1
            $script:Fw.Rows[0].Status | Should -BeExactly 'Partial'
        }

        It 'lists the subfolder and the Failed status in host.json' {
            $rsop = (Read-JsonFile -Path (Join-Path -Path $script:FwHost -ChildPath 'host.json')).Collectors[1]
            $rsop.Subfolder | Should -BeExactly 'RemoteRSOP'
            $rsop.Status | Should -BeExactly 'Failed'
        }
    }

    Context 'the only selected collector is Failed with a folder' {
        It 'keeps the row Failed and still places the folder' {
            $config = @{ Entries = @{ RemoteRSOP = @{ a1 = @{ Mode = 'FailedWithFolder'; Errors = @('not elevated') } } } }
            $run = Invoke-FakeBaseline -Config $config -Parameter @{ ComputerName = @('a1'); Type = @('RSOP') }
            $run.Rows[0].Status | Should -BeExactly 'Failed'
            $run.Rows[0].OutputFolder | Should -Not -BeNullOrEmpty
            (Test-Path -LiteralPath (Join-Path -Path (Join-Path -Path $run.Rows[0].OutputFolder -ChildPath 'RemoteRSOP') -ChildPath 'system.json')) | Should -BeTrue
            $run.Rows[0].IsElevated | Should -BeTrue
        }
    }
}

Describe 'Manifest' {
    BeforeAll {
        $script:ManifestData = Test-ModuleManifest -Path $script:ManifestPath
    }

    It 'passes Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the public function set' {
        @($script:ManifestData.ExportedFunctions.Keys) | Should -Be @('Get-RemoteBaseline')
    }

    It 'declares no RequiredModules' {
        $script:ManifestData.RequiredModules.Count | Should -Be 0
    }

    It 'has Author Tom Stryhn and the module version 1.0.0' {
        $script:ManifestData.Author | Should -Be 'Tom Stryhn'
        $script:ManifestData.Version.ToString() | Should -BeExactly '1.0.0'
    }

    It 'names every bundled version in ReleaseNotes' {
        $notes = (Import-PowerShellDataFile -LiteralPath $script:ManifestPath).PrivateData.PSData.ReleaseNotes
        foreach ($entry in $script:Bundle.Modules) { $notes | Should -Match ([regex]::Escape($entry.Module + ' ' + $entry.Version)) }
    }

    It 'has a matching .VERSION in every src\ps1 file and every tests file that carries a PSScriptInfo header' {
        $moduleVersion = $script:ManifestData.Version.ToString()
        $candidateFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $script:ModuleFolder -ChildPath 'src\ps1') -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter '*.ps1')
        $scriptInfoFiles = @($candidateFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '<#PSScriptInfo' })
        $scriptInfoFiles.Count | Should -Be $candidateFiles.Count
        foreach ($file in $scriptInfoFiles) {
            (Get-Content -LiteralPath $file.FullName -Raw) | Should -Match ([regex]::Escape(".VERSION $moduleVersion")) -Because $file.Name
        }
    }

    It 'has a different .GUID in every file that carries a PSScriptInfo header' {
        $candidateFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $script:ModuleFolder -ChildPath 'src\ps1') -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter '*.ps1')
        $guids = @($candidateFiles | ForEach-Object {
                if ((Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^\.GUID\s+([0-9a-fA-F-]{36})') { $Matches[1].ToLowerInvariant() }
            })
        $guids.Count | Should -Be $candidateFiles.Count
        @($guids | Select-Object -Unique).Count | Should -Be $guids.Count
    }

    It 'has a FileList that matches the module folder on disk in both directions' {
        $listed = @((Import-PowerShellDataFile -LiteralPath $script:ManifestPath).FileList | ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path -Path $script:ModuleFolder -ChildPath $_)) })
        $onDisk = @(Get-ChildItem -LiteralPath $script:ModuleFolder -File -Recurse -Force | ForEach-Object { $_.FullName })
        $missing = @($listed | Where-Object { $onDisk -notcontains $_ })
        $extra = @($onDisk | Where-Object { $listed -notcontains $_ })
        $missing.Count | Should -Be 0 -Because ('in FileList, not on disk: ' + ($missing -join ', '))
        $extra.Count | Should -Be 0 -Because ('on disk, not in FileList: ' + ($extra -join ', '))
        @($listed | Select-Object -Unique).Count | Should -Be $listed.Count
    }
}

Describe 'Read-only source, DESIGN.md section 10' {
    BeforeAll {
        $script:Usage = [System.Collections.Generic.List[object]]::new()
        $script:StringLiteral = [System.Collections.Generic.List[string]]::new()
        $script:SrcFile = @(Get-ChildItem -LiteralPath (Join-Path -Path $script:ModuleFolder -ChildPath 'src\ps1') -Filter '*.ps1' -File)
        foreach ($file in $script:SrcFile) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $parameterNames = @($node.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
                [void]$script:Usage.Add([pscustomobject]@{ File = $file.Name; Name = $node.GetCommandName(); Parameter = $parameterNames })
            }
            foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
                [void]$script:StringLiteral.Add($node.Value)
            }
        }
        # Start-Sleep is the pause between the attempts of a rename or move (section 13.6): it acts on nothing but time.
        $script:Allowed = @('Set-StrictMode', 'New-Object', 'New-Item', 'Remove-Item', 'Move-Item', 'Rename-Item', 'Write-Warning', 'Write-Verbose', 'Add-Type', 'Start-Sleep', 'Compress-RemoteBaselineRunFolder')
    }

    It 'has no command with a changing verb outside the allow-list (own Write-RemoteBaseline* functions included)' {
        $changing = @($script:Usage | Where-Object { $_.Name -and $_.Name -match '^(Set|New|Remove|Add|Clear|Stop|Start|Restart|Disable|Enable|Update|Write)-' })
        $changing.Count | Should -BeGreaterThan 5
        $bad = @($changing | Where-Object { $script:Allowed -notcontains $_.Name -and $_.Name -notlike 'Write-RemoteBaseline*' } | ForEach-Object { $_.File + ': ' + $_.Name })
        $bad.Count | Should -Be 0 -Because ($bad -join '; ')
    }

    It 'has no Invoke-Expression, no remoting or WMI method call and no process start' {
        $names = @($script:Usage | ForEach-Object { $_.Name })
        foreach ($forbidden in @('Invoke-Expression', 'iex', 'Invoke-Command', 'icm', 'Enter-PSSession', 'New-PSSession', 'Invoke-CimMethod', 'Invoke-WmiMethod', 'Start-Process', 'Set-Content', 'Add-Content', 'Out-File')) {
            $names | Should -Not -Contain $forbidden
        }
    }

    It 'gives every New-Item, Remove-Item, Move-Item and Rename-Item call a path and no parameter that could name a remote path' {
        $calls = @($script:Usage | Where-Object { @('New-Item', 'Remove-Item', 'Move-Item', 'Rename-Item') -contains $_.Name })
        $calls.Count | Should -BeGreaterThan 5
        foreach ($call in $calls) {
            @($call.Parameter | Where-Object { $_ -in @('Path', 'LiteralPath') }).Count | Should -BeGreaterThan 0 -Because ($call.File + ' ' + $call.Name)
            foreach ($forbidden in @('ComputerName', 'Session', 'CimSession', 'Credential', 'AsJob')) {
                $call.Parameter | Should -Not -Contain $forbidden -Because ($call.File + ' ' + $call.Name)
            }
        }
    }

    It 'uses Add-Type only to load the zip assemblies, in Compress-RemoteBaselineRunFolder' {
        $calls = @($script:Usage | Where-Object { $_.Name -eq 'Add-Type' })
        $calls.Count | Should -BeGreaterThan 0
        foreach ($call in $calls) {
            $call.File | Should -BeExactly 'Compress-RemoteBaselineRunFolder.ps1'
            $call.Parameter | Should -Contain 'AssemblyName'
            $call.Parameter | Should -Not -Contain 'TypeDefinition'
            $call.Parameter | Should -Not -Contain 'MemberDefinition'
        }
    }

    It 'calls a command dynamically only where a collector function is called by name or a scriptblock is run' {
        $dynamic = @($script:Usage | Where-Object { -not $_.Name } | ForEach-Object { $_.File } | Select-Object -Unique)
        $bad = @($dynamic | Where-Object { @('Get-RemoteBaseline.ps1', 'Invoke-RemoteBaselineCollector.ps1') -notcontains $_ })
        $bad.Count | Should -Be 0 -Because ($bad -join ', ')
    }

    It 'has no UNC path literal and sets StrictMode Latest in Get-RemoteBaseline' {
        @($script:StringLiteral | Where-Object { $_ -match '^\\\\' }).Count | Should -Be 0
        (Get-Content -LiteralPath (Join-Path -Path $script:ModuleFolder -ChildPath 'src\ps1\Get-RemoteBaseline.ps1') -Raw) | Should -Match 'Set-StrictMode -Version Latest'
    }
}

Describe 'ASCII only' {
    It 'has no byte above 127 in the sources, the tests, the manifest, the README and SECURITY.md' {
        $files = @(Get-ChildItem -LiteralPath $script:ModuleFolder -Include '*.ps1', '*.psd1', '*.psm1' -Recurse -File | Where-Object { $_.FullName -notlike '*\Modules\*' })
        $files += @(Get-ChildItem -LiteralPath $PSScriptRoot -Include '*.ps1' -Recurse -File)
        foreach ($name in @('README.md', 'SECURITY.md')) {
            $path = Join-Path -Path $script:RepoRoot -ChildPath $name
            if (Test-Path -LiteralPath $path) { $files += Get-Item -LiteralPath $path }
        }
        $files.Count | Should -BeGreaterThan 20
        $bad = @($files | Where-Object { @([System.IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 }).Count -gt 0 } | ForEach-Object { $_.Name })
        $bad.Count | Should -Be 0 -Because ($bad -join ', ')
    }
}
