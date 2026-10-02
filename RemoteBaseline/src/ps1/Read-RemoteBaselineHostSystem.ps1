<#PSScriptInfo

.DESCRIPTION Reads the system.json of the first present collector subfolder of a host folder

.VERSION 1.1.0

.GUID d1e78657-fdf9-4a1b-a71d-a3d338a9ef25

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Read-RemoteBaselineHostSystem {

    <#
    .SYNOPSIS
        Reads the system.json of the first present collector subfolder of a host folder.

    .DESCRIPTION
        Walks the module names in the order given (the run order of the selected collectors) and
        reads <host folder>\<Module>\system.json of the first one that has the file, which is the
        only collector file the module ever reads. A subfolder without the file is skipped
        without a line: a collector that did not write it already says so in its own errors. A
        file that is present but cannot be read or parsed gives one line "host.json: <Module>:
        system.json: <message>" and the walk goes on to the next subfolder. Returns an object
        with System (the parsed object, or $null when no subfolder gave one) and Problems
        (string[], possibly empty). Never throws.

    .PARAMETER HostFolder
        The host folder.

    .PARAMETER Module
        The collector module names, in run order.

    .NOTES
        FUNCTION: Read-RemoteBaselineHostSystem
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$HostFolder,

        [Parameter(Mandatory = $true)]
        [string[]]$Module
    )

    $system = $null
    $problems = [System.Collections.Generic.List[string]]::new()

    foreach ($moduleName in @($Module)) {
        $systemPath = Join-Path -Path (Join-Path -Path $HostFolder -ChildPath $moduleName) -ChildPath 'system.json'
        if (-not (Test-Path -LiteralPath $systemPath -PathType Leaf)) { continue }
        try {
            $parsed = [System.IO.File]::ReadAllText($systemPath) | ConvertFrom-Json
            if ($null -eq $parsed) { throw 'the file is empty' }
            $system = $parsed
            break
        } catch {
            [void]$problems.Add('host.json: ' + $moduleName + ': system.json: ' + (ConvertTo-RemoteBaselineOneLine -Text $_.Exception.Message))
        }
    }

    return [pscustomobject]@{
        System   = $system
        Problems = [string[]]$problems.ToArray()
    }
}
