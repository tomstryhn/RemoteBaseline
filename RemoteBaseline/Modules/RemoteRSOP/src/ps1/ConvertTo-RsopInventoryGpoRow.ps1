<#PSScriptInfo

.DESCRIPTION Turns one RSOP_GPO instance into one gpo object

.VERSION 1.3.0

.GUID 7c89deae-cdd5-499d-8d6c-9cf812295395

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertTo-RsopInventoryGpoRow {

    <#
    .SYNOPSIS
        Turns one RSOP_GPO instance into one gpo object.

    .DESCRIPTION
        GpoId is extracted from id the same way settings.csv extracts it from GPOID: a value of
        the form cn={guid},... or CN={GUID},... becomes the {GUID} upper case, LocalGPO is kept
        as is, and an empty value becomes null. ExtensionIds stays an array here; the csv writer
        joins it with a pipe.

    .PARAMETER Namespace
        Computer or the S_1_... folder name the instance was read from.

    .PARAMETER Instance
        One projected RSOP_GPO instance, as parsed from RawJson.

    .NOTES
        FUNCTION: ConvertTo-RsopInventoryGpoRow
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
        [psobject]$Instance
    )

    $idRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'id' -Default $null
    $gpoId = ConvertTo-RsopInventoryGpoId -Value $idRaw

    $enabledRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'enabled' -Default $null
    $accessDeniedRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'accessDenied' -Default $null
    $filterAllowedRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'filterAllowed' -Default $null
    $versionRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'version' -Default $null

    return [pscustomobject]@{
        Namespace       = $Namespace
        GpoId           = $gpoId
        Name            = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'name' -Default $null
        GuidName        = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'guidName' -Default $null
        Enabled         = $(if ($null -ne $enabledRaw) { [bool]$enabledRaw } else { $null })
        AccessDenied    = $(if ($null -ne $accessDeniedRaw) { [bool]$accessDeniedRaw } else { $null })
        FilterAllowed   = $(if ($null -ne $filterAllowedRaw) { [bool]$filterAllowedRaw } else { $null })
        FilterId        = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'filterId' -Default $null
        # RSOP_GPO.version is a uint32. A GPO the computer is denied by security filtering reports
        # 0xFFFF0001 (4294901761), which overflows Int32, so the column is Int64.
        Version         = $(if ($null -ne $versionRaw) { [int64]$versionRaw } else { $null })
        FileSystemPath  = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'fileSystemPath' -Default $null
        ExtensionIds    = @(Get-RsopInventorySafeProperty -InputObject $Instance -Name 'extensionIDs' -Default @())
    }
}
