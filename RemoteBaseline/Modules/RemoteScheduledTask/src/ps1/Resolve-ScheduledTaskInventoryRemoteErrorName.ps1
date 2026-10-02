<#PSScriptInfo

.DESCRIPTION Matches one remote error record to a requested computer name

.VERSION 1.4.1

.GUID d94b6fa6-3b45-4b9c-b60f-f1d89fb2e338

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function Resolve-ScheduledTaskInventoryRemoteErrorName {

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
        FUNCTION: Resolve-ScheduledTaskInventoryRemoteErrorName
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

    $targetObject = Get-ScheduledTaskInventorySafeProperty -InputObject $ErrorRecord -Name 'TargetObject' -Default $null
    if ($targetObject -is [uri]) {
        if ($targetObject.Host) { $candidates += $targetObject.Host }
    } elseif ($targetObject) {
        $candidates += "$targetObject"
    }

    $originInfo = Get-ScheduledTaskInventorySafeProperty -InputObject $ErrorRecord -Name 'OriginInfo' -Default $null
    $originName = Get-ScheduledTaskInventorySafeProperty -InputObject $originInfo -Name 'PSComputerName' -Default $null
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
