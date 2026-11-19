<#PSScriptInfo

.DESCRIPTION Writes host.json into a host folder

.VERSION 1.4.0

.GUID a86918a1-8451-46ee-b4d5-131fe3e0b199

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Write-RemoteBaselineHostFile
function Write-RemoteBaselineHostFile {

    <#
    .SYNOPSIS
        Writes host.json into a host folder.

    .DESCRIPTION
        Writes one object, keys in this order: ComputerName (the first requested name that maps to
        the folder), RequestedNames (string[]), ComputerId, DnsHostName, Domain, OSCaption,
        OSVersion, CurrentBuild, UBR, DisplayVersion, EditionID, InstallationType, Culture,
        TimeZoneId, PartOfDomain, DomainRole, IsElevated, MachineGuid, MachineSid, DomainSid,
        ComputerAccountSid, DomainNetbiosName (all copied from SystemInfo, the parsed system.json of
        the first present subfolder, $null when SystemInfo is $null or lacks the key, the last four
        are the SID reference, which only the first selected collector reads, so they are null when
        that collector did not reach the host), Collector (RemoteBaseline), CollectorVersion, RunId (the umbrella run folder
        name), Types (string[], selected, run order), Collectors (one object per selected type in
        run order: Type, Module, Version, Subfolder, Status, ErrorCount, RunId), Status and
        Errors (the umbrella row's, as they stand before the manifest and archive steps).

        Subfolder is the module name when that folder exists inside the host folder, $null when
        the collector did not reach this host. The file is named host.json, not system.json, so a
        reader that looks for computer folders by system.json never mistakes a host folder for
        one. Throws on a write failure. The caller turns that into a "host.json: <message>" line.

    .PARAMETER HostFolder
        The host folder to write into.

    .PARAMETER RequestedName
        Every requested name that maps to this folder, in requested order. The first is
        ComputerName.

    .PARAMETER Type
        The selected types, run order.

    .PARAMETER CollectorResult
        The hashtables Invoke-RemoteBaselineCollector returned, in run order.

    .PARAMETER Row
        The umbrella result row of the first requested name (aliases get identical rows).

    .PARAMETER SystemInfo
        The parsed system.json from Read-RemoteBaselineHostSystem, or $null.

    .PARAMETER CollectorVersion
        The RemoteBaseline module version.

    .PARAMETER RunId
        The umbrella run folder name.

    .NOTES
        FUNCTION: Write-RemoteBaselineHostFile
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        None.
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String]$HostFolder,

        [Parameter(Mandatory = $true)]
        [String[]]$RequestedName,

        [Parameter(Mandatory = $true)]
        [String[]]$Type,

        [Parameter(Mandatory = $true)]
        [Object[]]$CollectorResult,

        [Parameter(Mandatory = $true)]
        $Row,

        [AllowNull()]
        $SystemInfo,

        [Parameter(Mandatory = $true)]
        [String]$CollectorVersion,

        [Parameter(Mandatory = $true)]
        [String]$RunId
    )

    $hostObject = [ordered]@{}
    $hostObject['ComputerName'] = $RequestedName[0]
    $hostObject['RequestedNames'] = [String[]]@($RequestedName)

    # An explicit ordered list, not an enumeration of the source object, so the key order never depends on how
    # system.json happened to be written.
    $identityKeys = @('ComputerId', 'DnsHostName', 'Domain', 'OSCaption', 'OSVersion', 'CurrentBuild', 'UBR', 'DisplayVersion', 'EditionID', 'InstallationType', 'Culture', 'TimeZoneId', 'PartOfDomain', 'DomainRole', 'IsElevated', 'MachineGuid', 'MachineSid', 'DomainSid', 'ComputerAccountSid', 'DomainNetbiosName')
    foreach ($key in $identityKeys) {
        $hostObject[$key] = Get-RemoteBaselineSafeProperty -InputObject $SystemInfo -Name $key -Default $null
    }

    $hostObject['Collector'] = 'RemoteBaseline'
    $hostObject['CollectorVersion'] = $CollectorVersion
    $hostObject['RunId'] = $RunId
    $hostObject['Types'] = [String[]]@($Type)

    $collectorList = [System.Collections.Generic.List[Object]]::new()
    foreach ($typeName in @($Type)) {
        $result = @($CollectorResult | Where-Object { $_['Type'] -eq $typeName }) | Select-Object -First 1
        $moduleName = $null
        $version = $null
        $collectorRunId = $null
        if ($null -ne $result) {
            $moduleName = $result['Module']
            $version = $result['Version']
            $collectorRunId = $result['RunId']
        }
        $subfolder = $null
        if ($null -ne $moduleName -and (Test-Path -LiteralPath (Join-Path -Path $HostFolder -ChildPath $moduleName) -PathType Container)) {
            $subfolder = $moduleName
        }
        [Void]$collectorList.Add([PSCustomObject]([ordered]@{
                    Type       = $typeName
                    Module     = $moduleName
                    Version    = $version
                    Subfolder  = $subfolder
                    Status     = Get-RemoteBaselineSafeProperty -InputObject $Row -Name ($typeName + 'Status') -Default $null
                    ErrorCount = Get-RemoteBaselineSafeProperty -InputObject $Row -Name ($typeName + 'ErrorCount') -Default $null
                    RunId      = $collectorRunId
                }))
    }
    $hostObject['Collectors'] = $collectorList.ToArray()

    $hostObject['Status'] = Get-RemoteBaselineSafeProperty -InputObject $Row -Name 'Status' -Default $null
    $hostObject['Errors'] = [String[]]@(Get-RemoteBaselineSafeProperty -InputObject $Row -Name 'Errors' -Default @())

    $hostJson = [PSCustomObject]$hostObject | ConvertTo-Json -Depth 6
    Write-RemoteBaselineTextFile -Path (Join-Path -Path $HostFolder -ChildPath 'host.json') -Content $hostJson
}
#endregion
