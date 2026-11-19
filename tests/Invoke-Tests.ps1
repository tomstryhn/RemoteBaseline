<#PSScriptInfo

.DESCRIPTION Runs PSScriptAnalyzer and the Pester suite for RemoteBaseline

.VERSION 1.4.0

.GUID 03c735de-9c08-4dd6-a6a6-ce1d2d55fb0e

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

<#
.SYNOPSIS
    Runs PSScriptAnalyzer and the Pester suite for RemoteBaseline.

.DESCRIPTION
    Runs PSScriptAnalyzer over the module and tests folder, then runs the Pester suite. Exits 1
    on any analyzer Error or Warning result, on any failed test, or when zero tests ran. Exits 0
    only when analysis is clean and at least one test ran and passed. Every path is derived from
    $PSScriptRoot, so this still works from a relocated copy of the repository.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path -Path $repoRoot -ChildPath 'RemoteBaseline'
$testsPath = $PSScriptRoot
$settingsPath = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
$testFilePath = Join-Path -Path $testsPath -ChildPath 'RemoteBaseline.Tests.ps1'

Write-Verbose "Repo root: $repoRoot"

# The pinned Pester is loaded before the analyzer runs. The analyzer's walk over the tests folder can load
# the newest installed Pester assembly as a side effect, and the pinned one cannot load after that.
try {
    Import-Module Pester -RequiredVersion 6.1.0 -Force -ErrorAction Stop
}
catch {
    Write-Error "Could not load Pester 6.1.0: $($_.Exception.Message)"
    exit 1
}

try {
    Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force -ErrorAction Stop
}
catch {
    Write-Error "Could not load PSScriptAnalyzer 1.25.0: $($_.Exception.Message)"
    exit 1
}

# Invoke-ScriptAnalyzer has only -Path, which it matches as a wildcard. A folder with square brackets in
# its name would match nothing and the run would report clean without having read a single file.
$analyzerResults = @()
$analyzerResults += Invoke-ScriptAnalyzer -Path ([Management.Automation.WildcardPattern]::Escape($modulePath)) -Recurse -Settings $settingsPath
$analyzerResults += Invoke-ScriptAnalyzer -Path ([Management.Automation.WildcardPattern]::Escape($testsPath)) -Recurse -Settings $settingsPath

$analyzerIssues = @($analyzerResults | Where-Object { $_.Severity -eq 'Error' -or $_.Severity -eq 'Warning' })

if ($analyzerIssues.Count -gt 0) {
    $analyzerIssues | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-String | Write-Output
    Write-Error "PSScriptAnalyzer reported $($analyzerIssues.Count) Error/Warning result(s)."
    exit 1
}

Write-Output 'PSScriptAnalyzer: clean, no Error or Warning results.'

#region Test file location a folder with square brackets in its path is reached through a junction
# The module cannot be imported from a folder with square brackets in its path on either engine: PowerShell
# refuses wildcard characters in the path of a nested module, and the module bundles its collectors as nested
# modules. Windows PowerShell 5.1 also dot-sources the provider path of the test file as a wildcard, so
# Pester finds no test there. The repository is therefore reached through a junction with a plain name for
# the run, and the junction is removed again.
$testFileToRun = $testFilePath
$junctionPath = $null
if ($testFilePath -match '[\[\]]') {
    $junctionPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('RemoteBaseline-tests-' + [Guid]::NewGuid().ToString('N'))
    if ($junctionPath -match '[\[\]]') {
        Write-Error "The temporary folder path '$junctionPath' contains square brackets, so the suite cannot be started from '$repoRoot'."
        exit 1
    }
    # The link target is matched as a wildcard path on 5.1, so it is escaped there. PowerShell 7 takes it literally.
    $linkTarget = $repoRoot
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $linkTarget = [Management.Automation.WildcardPattern]::Escape($repoRoot)
    }
    $null = New-Item -Path $junctionPath -ItemType Junction -Value $linkTarget
    $testFileToRun = Join-Path -Path $junctionPath -ChildPath 'tests\RemoteBaseline.Tests.ps1'
    Write-Verbose "Running the tests through the junction $junctionPath"
}
#endregion

$config = New-PesterConfiguration
# Pester resolves Run.Path as a wildcard, so escape it: a repository folder path containing [ or ]
# would otherwise silently match nothing.
$config.Run.Path = [Management.Automation.WildcardPattern]::Escape($testFileToRun)
$config.Run.PassThru = $true
$config.Run.Exit = $false
$config.Output.Verbosity = 'Detailed'

# Pester puts the location back with a wildcard Set-Location when a run ends. On PowerShell 7 that fails
# for a folder with square brackets in its name and, under the error action set above, ends this script
# with exit 1 although every test passed. The run therefore starts from the temp folder and the caller's
# location is restored here with a literal path.
$startLocation = (Get-Location).Path
Set-Location -LiteralPath ([System.IO.Path]::GetTempPath())
try {
    $pesterResult = Invoke-Pester -Configuration $config
}
finally {
    # A session that has run the whole suite has been seen to refuse any location change into a folder with
    # square brackets in its name on PowerShell 7.7. The script is about to end, so this is only reported.
    try {
        Set-Location -LiteralPath $startLocation
    }
    catch {
        Write-Warning "Could not restore the location '$startLocation': $($_.Exception.Message)"
    }
    if ($junctionPath -and (Test-Path -LiteralPath $junctionPath)) {
        # Directory.Delete without the recursive flag removes the link and never the folder it points to.
        [System.IO.Directory]::Delete($junctionPath)
    }
}

$totalCount = 0
if ($pesterResult -and $pesterResult.PSObject.Properties['TotalCount']) {
    $totalCount = $pesterResult.TotalCount
}

Write-Output "Pester total tests run: $totalCount"

if ($totalCount -eq 0) {
    Write-Error 'Zero Pester tests ran.'
    exit 1
}

if ($pesterResult.FailedCount -gt 0) {
    Write-Error "$($pesterResult.FailedCount) Pester test(s) failed."
    exit 1
}

Write-Output 'PSScriptAnalyzer and Pester both passed.'
exit 0
