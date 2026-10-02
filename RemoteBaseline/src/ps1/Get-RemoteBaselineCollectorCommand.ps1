<#PSScriptInfo

.DESCRIPTION Resolves a bundled collector function and its version from this module's nested modules

.VERSION 1.1.0

.GUID 8a5f0c1e-6b3d-4e92-a7c4-2d9b71e05f38

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Get-RemoteBaselineCollectorCommand {

    <#
    .SYNOPSIS
        Resolves a bundled collector function and its version from this module's nested modules.

    .DESCRIPTION
        Returns the FunctionInfo of the collector's public function as the nested module exports
        it, together with that nested module's version, so the call runs the bundled copy and
        run.json names the version that actually ran. A lookup by name is not used for this:
        command lookup checks aliases before functions in every scope, so an alias or a function
        of the same name in the caller's session (from a profile or a script) would win over the
        bundled copy while the version read from the manifest still named the bundled one.

        This is the one place that decides which code a collector call runs, and the one place a
        test replaces to put a fake collector in its stead.

        Throws "collector <Module> not bundled" when this module has no such nested module or the
        nested module does not export the function (or when the function runs outside a module);
        the caller turns the message into a synthetic Failed row per requested name.

    .PARAMETER Module
        The collector module name, for example RemoteFirewall.

    .PARAMETER Function
        The collector's public function name, for example Get-FirewallInventory.

    .NOTES
        FUNCTION: Get-RemoteBaselineCollectorCommand
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject with Command (the FunctionInfo) and Version (string).
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$Module,

        [Parameter(Mandatory = $true)]
        [string]$Function
    )

    Set-StrictMode -Version Latest

    # The session state of the module this function is defined in (RemoteBaseline), not the caller's.
    $ownModule = $ExecutionContext.SessionState.Module
    $nested = $null
    if ($null -ne $ownModule) {
        $nested = @($ownModule.NestedModules | Where-Object { $_.Name -eq $Module }) | Select-Object -First 1
    }
    if ($null -eq $nested -or -not $nested.ExportedFunctions.ContainsKey($Function)) {
        throw "collector $Module not bundled"
    }

    return [pscustomobject]@{
        Command = $nested.ExportedFunctions[$Function]
        Version = $nested.Version.ToString()
    }
}
