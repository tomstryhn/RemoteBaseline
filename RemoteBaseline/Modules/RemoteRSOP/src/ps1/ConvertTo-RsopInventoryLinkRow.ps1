<#PSScriptInfo

.DESCRIPTION Turns one RSOP_GPLink instance into one link object

.VERSION 1.3.0

.GUID c7ed5347-eb30-426f-a87d-79279aefa3ae

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertTo-RsopInventoryLinkRow {

    <#
    .SYNOPSIS
        Turns one RSOP_GPLink instance into one link object.

    .DESCRIPTION
        GpoId and GpoName come from the embedded GPO projection carried on the instance itself
        (GpoId through the same {GUID} extraction settings.csv applies to GPOID). SomId and
        SomType come from the embedded SOM projection the same way. The embedded SOM reference
        does not reliably carry every RSOP_SOM property, so SomBlocked, SomBlocking and SomReason
        are read from SomMap, a lookup built once per namespace from the namespace's own
        RSOP_SOM instances, keyed on id, falling back to the embedded projection when the id is
        not in the map.

    .PARAMETER Namespace
        Computer or the S_1_... folder name the instance was read from.

    .PARAMETER Instance
        One projected RSOP_GPLink instance, as parsed from RawJson.

    .PARAMETER SomMap
        A hashtable, built once per namespace, from an RSOP_SOM instance's id (lower-cased) to
        the full instance. May be $null or empty when the namespace carries no RSOP_SOM
        instances.

    .PARAMETER GpoNameMap
        A hashtable, built once per namespace, from an RSOP_GPO instance's id (lower-cased) to
        its name. May be $null or empty when the namespace carries no RSOP_GPO instances.

    .NOTES
        FUNCTION: ConvertTo-RsopInventoryLinkRow
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
        [hashtable]$SomMap,

        [AllowNull()]
        [hashtable]$GpoNameMap
    )

    $embeddedGpo = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'GPO' -Default $null
    $gpoIdRaw = Get-RsopInventorySafeProperty -InputObject $embeddedGpo -Name 'id' -Default $null
    $gpoId = ConvertTo-RsopInventoryGpoId -Value $gpoIdRaw
    # The embedded GPO and SOM references carry only their key properties, so names and types come from the namespace maps
    $gpoName = $null
    if ($gpoIdRaw -and $GpoNameMap -and $GpoNameMap.ContainsKey($gpoIdRaw.ToLowerInvariant())) {
        $gpoName = $GpoNameMap[$gpoIdRaw.ToLowerInvariant()]
    }

    $embeddedSom = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'SOM' -Default $null
    $somId = Get-RsopInventorySafeProperty -InputObject $embeddedSom -Name 'id' -Default $null

    $somFull = $embeddedSom
    if ($somId -and $SomMap -and $SomMap.ContainsKey($somId.ToLowerInvariant())) {
        $somFull = $SomMap[$somId.ToLowerInvariant()]
    }

    $somType = Get-RsopInventorySafeProperty -InputObject $somFull -Name 'type' -Default $null
    $somBlocked = Get-RsopInventorySafeProperty -InputObject $somFull -Name 'blocked' -Default $null
    $somBlocking = Get-RsopInventorySafeProperty -InputObject $somFull -Name 'blocking' -Default $null
    $somReason = Get-RsopInventorySafeProperty -InputObject $somFull -Name 'reason' -Default $null

    $appliedOrderRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'appliedOrder' -Default $null
    $linkOrderRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'linkOrder' -Default $null
    $somOrderRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'somOrder' -Default $null
    $enabledRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'enabled' -Default $null
    $noOverrideRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'noOverride' -Default $null

    return [pscustomobject]@{
        Namespace   = $Namespace
        GpoId       = $gpoId
        GpoName     = $gpoName
        SomId       = $somId
        SomType     = $somType
        SomBlocked  = $somBlocked
        SomBlocking = $somBlocking
        SomReason   = $somReason
        AppliedOrder = $(if ($null -ne $appliedOrderRaw) { [int]$appliedOrderRaw } else { $null })
        LinkOrder   = $(if ($null -ne $linkOrderRaw) { [int]$linkOrderRaw } else { $null })
        SomOrder    = $(if ($null -ne $somOrderRaw) { [int]$somOrderRaw } else { $null })
        Enabled     = $(if ($null -ne $enabledRaw) { [bool]$enabledRaw } else { $null })
        NoOverride  = $(if ($null -ne $noOverrideRaw) { [bool]$noOverrideRaw } else { $null })
    }
}
