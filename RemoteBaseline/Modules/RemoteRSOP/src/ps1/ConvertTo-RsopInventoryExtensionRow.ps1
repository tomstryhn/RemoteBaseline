<#PSScriptInfo

.DESCRIPTION Turns one RSOP_ExtensionStatus instance into one extension object

.VERSION 1.2.0

.GUID 22f75539-e447-41ff-9bb8-cceef0771f68

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertTo-RsopInventoryExtensionRow {

    <#
    .SYNOPSIS
        Turns one RSOP_ExtensionStatus instance into one extension object.

    .DESCRIPTION
        BeginTime and EndTime are copied as delivered: the worker already rendered them as ISO
        8601 UTC strings when it built RawJson, and this function never re-parses them. Deleted,
        Status and ErrorCode are outside this class's shape and are not present here. EventSources
        stays an array here; the csv writer joins it with a pipe.

    .PARAMETER Namespace
        Computer or the S_1_... folder name the instance was read from.

    .PARAMETER Instance
        One projected RSOP_ExtensionStatus instance, as parsed from RawJson.

    .PARAMETER EventSourceMap
        A hashtable, built once per namespace, from an extension's ExtensionGuid (lower-cased) to
        the string array of eventLogName\eventLogSource labels linked to it through
        RSOP_ExtensionEventSourceLink. May be $null or empty when the namespace carries no linked
        event sources.

    .NOTES
        FUNCTION: ConvertTo-RsopInventoryExtensionRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [psobject]$Instance,

        [AllowNull()]
        [hashtable]$EventSourceMap
    )

    $extensionGuid = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'extensionGuid' -Default $null

    $eventSources = @()
    if ($extensionGuid -and $EventSourceMap -and $EventSourceMap.ContainsKey($extensionGuid.ToLowerInvariant())) {
        $eventSources = @($EventSourceMap[$extensionGuid.ToLowerInvariant()])
    }

    # PowerShell 7 parses date-shaped JSON strings into DateTime on the way in, so both times go back to the ISO text
    $beginTime = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'beginTime' -Default $null
    if ($beginTime -is [DateTime]) { $beginTime = $beginTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
    $endTime = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'endTime' -Default $null
    if ($endTime -is [DateTime]) { $endTime = $endTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }

    return [pscustomobject]@{
        Namespace     = $Namespace
        ExtensionGuid = $extensionGuid
        DisplayName   = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'displayName' -Default $null
        Error         = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'error' -Default $null
        BeginTime     = $beginTime
        EndTime       = $endTime
        LoggingStatus = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'loggingStatus' -Default $null
        EventSources  = $eventSources
    }
}
