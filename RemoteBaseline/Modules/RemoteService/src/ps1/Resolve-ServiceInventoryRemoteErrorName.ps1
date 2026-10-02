<#PSScriptInfo

.DESCRIPTION Matches one remote error record to a requested computer name

.VERSION 1.4.0

.GUID 55a1e504-10a5-4b8e-b62c-575bd426a695

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function Resolve-ServiceInventoryRemoteErrorName {

    <#
    .SYNOPSIS
        Matches one remote error record to a requested computer name.

    .DESCRIPTION
        TargetObject is tried first, then OriginInfo.PSComputerName. A uri TargetObject
        contributes its Host rather than its full string form. A candidate that matches no
        requested name as it stands is retried once with a trailing domain suffix stripped, the
        first dot-separated label only. Returns the matched requested name, or nothing when no
        requested name matches.

    .PARAMETER ErrorRecord
        The error record returned by Invoke-Command through -ErrorVariable.

    .PARAMETER RemoteNames
        The requested remote computer names to match against.

    .NOTES
        FUNCTION: Resolve-ServiceInventoryRemoteErrorName
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String
    #>

    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecord,

        [Parameter(Mandatory = $true)]
        [string[]]$RemoteNames
    )

    $candidates = @()

    $targetObject = Get-ServiceInventorySafeProperty -InputObject $ErrorRecord -Name 'TargetObject' -Default $null
    if ($targetObject -is [uri]) {
        if ($targetObject.Host) { $candidates += $targetObject.Host }
    } elseif ($targetObject) {
        $candidates += "$targetObject"
    }

    $originInfo = Get-ServiceInventorySafeProperty -InputObject $ErrorRecord -Name 'OriginInfo' -Default $null
    $originName = Get-ServiceInventorySafeProperty -InputObject $originInfo -Name 'PSComputerName' -Default $null
    if ($originName) { $candidates += "$originName" }

    foreach ($candidate in $candidates) {
        foreach ($rn in $RemoteNames) {
            if ($candidate -ieq $rn) { return $rn }
        }

        $dotIndex = $candidate.IndexOf('.')
        if ($dotIndex -gt 0) {
            $stripped = $candidate.Substring(0, $dotIndex)
            foreach ($rn in $RemoteNames) {
                if ($stripped -ieq $rn) { return $rn }
            }
        }
    }

    return $null
}
