<#PSScriptInfo

.DESCRIPTION Matches one remote error record to a requested computer name

.VERSION 1.0.0

.GUID 6d7a36f3-22bc-4309-9deb-a359cc3970bf

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Resolve-SystemInventoryRemoteErrorName
function Resolve-SystemInventoryRemoteErrorName {

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
        FUNCTION: Resolve-SystemInventoryRemoteErrorName
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
        [String[]]$RemoteNames
    )

    $candidates = @()

    $targetObject = Get-SystemInventorySafeProperty -InputObject $ErrorRecord -Name 'TargetObject' -Default $null
    if ($targetObject -is [Uri]) {
        if ($targetObject.Host) {
            $candidates += $targetObject.Host
        }
    }
    elseif ($targetObject) {
        $candidates += "$targetObject"
    }

    $originInfo = Get-SystemInventorySafeProperty -InputObject $ErrorRecord -Name 'OriginInfo' -Default $null
    $originName = Get-SystemInventorySafeProperty -InputObject $originInfo -Name 'PSComputerName' -Default $null
    if ($originName) {
        $candidates += "$originName"
    }

    foreach ($candidate in $candidates) {
        foreach ($rn in $RemoteNames) {
            if ($candidate -ieq $rn) {
                return $rn
            }
        }

        $dotIndex = $candidate.IndexOf('.')
        if ($dotIndex -gt 0) {
            $stripped = $candidate.Substring(0, $dotIndex)
            foreach ($rn in $RemoteNames) {
                if ($stripped -ieq $rn) {
                    return $rn
                }
            }
        }
    }

    return $null
}
#endregion
