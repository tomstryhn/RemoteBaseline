<#PSScriptInfo

.DESCRIPTION Turns one setting class instance into zero or more flat setting objects

.VERSION 1.3.0

.GUID 8a48f839-9fbb-46ba-857c-49b7b4e21398

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteRSOP/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteRSOP

#>

function ConvertTo-RsopInventorySettingRow {

    <#
    .SYNOPSIS
        Turns one setting class instance into zero or more flat setting objects.

    .DESCRIPTION
        The one place that knows the setting classes. Every class outside the documented list
        returns zero objects, so a caller can call this for every exported class of every
        namespace without a class filter of its own. GpoId is extracted from GPOID the same way
        for every class: a value of the form cn={guid},... or CN={GUID},... becomes the {GUID}
        upper case, LocalGPO is kept as is, and an empty value becomes null. GpoName comes from
        GpoNameMap, keyed on the raw GPOID lower-cased, so the lookup matches RSOP_GPO's own id
        property case-insensitively without extracting the GUID a second time.

    .PARAMETER Namespace
        Computer or the S_1_... folder name the instance was read from.

    .PARAMETER ClassName
        The RSOP class name of Instance.

    .PARAMETER Instance
        One projected instance (section 6.1 of the design), as parsed from RawJson.

    .PARAMETER GpoNameMap
        A hashtable, built once per namespace, from a GPO's raw id (lower-cased) to its name.
        May be $null or empty when the namespace carries no RSOP_GPO instances.

    .NOTES
        FUNCTION: ConvertTo-RsopInventorySettingRow
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
        [string]$ClassName,

        [Parameter(Mandatory = $true)]
        [psobject]$Instance,

        [AllowNull()]
        [hashtable]$GpoNameMap
    )

    #region classes this function knows, every other class returns zero objects
    # The classes that share one shape, keyed on the class name: the Key, the property Name is read from, the ValueType, the property Value is read from, how that value is shaped (Plain, Bool for a bool cast, Array for an @() wrap) and the properties Detail carries, in order.
    $classTable = @{
        'RSOP_SecuritySettingNumeric'         = @{ Key = 'SecuritySetting'; Name = 'KeyName'; ValueType = 'Numeric'; Value = 'Setting'; Shape = 'Plain'; Detail = @() }
        'RSOP_SecuritySettingBoolean'         = @{ Key = 'SecuritySetting'; Name = 'KeyName'; ValueType = 'Boolean'; Value = 'Setting'; Shape = 'Bool'; Detail = @() }
        'RSOP_SecuritySettingString'          = @{ Key = 'SecuritySetting'; Name = 'KeyName'; ValueType = 'String'; Value = 'Setting'; Shape = 'Plain'; Detail = @() }
        'RSOP_UserPrivilegeRight'             = @{ Key = 'PrivilegeRights'; Name = 'UserRight'; ValueType = 'AccountList'; Value = 'AccountList'; Shape = 'Array'; Detail = @() }
        'RSOP_SubcategorySystemAuditSetting'  = @{ Key = 'AuditSubcategory'; Name = 'SubcategoryName'; ValueType = 'AuditSetting'; Value = 'SettingValue'; Shape = 'Plain'; Detail = @('SubcategoryGuid') }
        'RSOP_SecurityEventLogSettingNumeric' = @{ Key = 'EventLog'; Name = 'KeyName'; ValueType = 'Numeric'; Value = 'Setting'; Shape = 'Plain'; Detail = @('Type') }
        'RSOP_SecurityEventLogSettingBoolean' = @{ Key = 'EventLog'; Name = 'KeyName'; ValueType = 'Boolean'; Value = 'Setting'; Shape = 'Bool'; Detail = @('Type') }
        'RSOP_RestrictedGroup'                = @{ Key = 'RestrictedGroup'; Name = 'GroupName'; ValueType = 'Members'; Value = 'Members'; Shape = 'Array'; Detail = @() }
        'RSOP_File'                           = @{ Key = 'FileSecurity'; Name = 'Path'; ValueType = 'Sddl'; Value = 'SDDLString'; Shape = 'Plain'; Detail = @('Mode', 'OriginalPath') }
        'RSOP_RegistryKey'                    = @{ Key = 'RegistryKeySecurity'; Name = 'Path'; ValueType = 'Sddl'; Value = 'SDDLString'; Shape = 'Plain'; Detail = @('Mode') }
    }
    # The classes that keep a branch of their own below.
    $branchClasses = @('RSOP_RegistryPolicySetting', 'RSOP_RegistryValue', 'RSOP_SystemService', 'RSOP_AuditPolicy', 'RSOP_RestrictedGroupEx')
    if (-not $classTable.ContainsKey($ClassName) -and $branchClasses -notcontains $ClassName) { return }
    #endregion

    #region fields common to every setting class, section 7.2
    $gpoIdRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'GPOID' -Default $null
    $gpoId = ConvertTo-RsopInventoryGpoId -Value $gpoIdRaw

    $gpoName = $null
    if ($gpoIdRaw -and $GpoNameMap -and $GpoNameMap.ContainsKey($gpoIdRaw.ToLowerInvariant())) {
        $gpoName = $GpoNameMap[$gpoIdRaw.ToLowerInvariant()]
    }

    $precedenceRaw = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'precedence' -Default $null
    $precedence = $null
    if ($null -ne $precedenceRaw) { $precedence = [int]$precedenceRaw }

    $somId = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'SOMID' -Default $null
    $instanceId = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'id' -Default $null

    # Present on every RSOP_SecuritySettings subclass, and read the same way for every class.
    $status = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Status' -Default $null
    $errorCode = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'ErrorCode' -Default $null
    #endregion

    $key = $null
    $name = $null
    $valueType = $null
    $value = $null
    $deleted = $null
    $rawRegType = $null
    $detail = '{}'

    #region class-specific Key, Name, ValueType, Value and Detail, section 8
    if ($classTable.ContainsKey($ClassName)) {
        $entry = $classTable[$ClassName]
        $key = $entry.Key
        $name = Get-RsopInventorySafeProperty -InputObject $Instance -Name $entry.Name -Default $null
        $valueType = $entry.ValueType
        if ($entry.Shape -eq 'Array') {
            $value = @(Get-RsopInventorySafeProperty -InputObject $Instance -Name $entry.Value -Default @())
        } else {
            $value = Get-RsopInventorySafeProperty -InputObject $Instance -Name $entry.Value -Default $null
            if ($entry.Shape -eq 'Bool' -and $null -ne $value) { $value = [bool]$value }
        }
        if ($entry.Detail.Count -gt 0) {
            $detailFields = [ordered]@{}
            foreach ($detailName in $entry.Detail) {
                $detailFields[$detailName] = Get-RsopInventorySafeProperty -InputObject $Instance -Name $detailName -Default $null
            }
            $detail = ConvertTo-Json -InputObject $detailFields -Compress
        }
    } else {
        switch ($ClassName) {
            'RSOP_RegistryPolicySetting' {
                $key = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'registryKey' -Default $null
                $name = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'valueName' -Default $null
                # Cast here, so a valueType that is present but null counts as 0 (REG_NONE) the same way an absent one does.
                $rawRegType = [int](Get-RsopInventorySafeProperty -InputObject $Instance -Name 'valueType' -Default 0)
                $rawBytes = @(Get-RsopInventorySafeProperty -InputObject $Instance -Name 'value' -Default @())
                $intBytes = @($rawBytes | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ })
                $value = ConvertFrom-RsopInventoryRegistryValue -ValueType ([int]$rawRegType) -Bytes $intBytes
                if ([int]$rawRegType -eq 7) { $value = @($value) }
                $rawDeleted = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'deleted' -Default $null
                if ($null -ne $rawDeleted) { $deleted = [bool]$rawDeleted }
                $command = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'command' -Default $null
                $detail = ConvertTo-Json -InputObject ([ordered]@{ command = $command }) -Compress
                # A create-key marker carries no value name and type REG_NONE, and the decoder already yields a null value for it.
                if ([string]::IsNullOrEmpty($name) -and [int]$rawRegType -eq 0) {
                    $name = ''
                    $value = $null
                }
            }
            'RSOP_RegistryValue' {
                $path = [string](Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Path' -Default '')
                $lastSlash = $path.LastIndexOf('\')
                if ($lastSlash -ge 0) {
                    $key = $path.Substring(0, $lastSlash)
                    $name = $path.Substring($lastSlash + 1)
                } else {
                    $key = ''
                    $name = $path
                }
                $rawRegType = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Type' -Default $null
                $value = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Data' -Default $null
            }
            'RSOP_SystemService' {
                $key = 'SystemService'
                $name = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Service' -Default $null
                $valueType = 'StartupMode'
                $rawMode = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'StartupMode' -Default $null
                $value = switch ($rawMode) {
                    2 { 'Automatic' }
                    3 { 'Manual' }
                    4 { 'Disabled' }
                    default { "$rawMode" }
                }
                $sddl = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'SDDLString' -Default $null
                $detail = ConvertTo-Json -InputObject ([ordered]@{ StartupMode = $rawMode; SDDLString = $sddl }) -Compress
            }
            'RSOP_AuditPolicy' {
                $key = 'AuditCategory'
                $name = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Category' -Default $null
                $valueType = 'AuditSetting'
                $successFlag = [bool](Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Success' -Default $false)
                $failureFlag = [bool](Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Failure' -Default $false)
                $value = 0
                if ($successFlag) { $value += 1 }
                if ($failureFlag) { $value += 2 }
            }
            'RSOP_RestrictedGroupEx' {
                $key = 'RestrictedGroup'
                $name = Get-RsopInventorySafeProperty -InputObject $Instance -Name 'GroupName' -Default $null
                $valueType = 'Members'
                $value = @(Get-RsopInventorySafeProperty -InputObject $Instance -Name 'Members' -Default @())
                $membersOf = @(Get-RsopInventorySafeProperty -InputObject $Instance -Name 'MembersOf' -Default @())
                $detail = ConvertTo-Json -InputObject ([ordered]@{ MembersOf = $membersOf }) -Compress
            }
        }
    }
    #endregion

    #region registry value type name, the one lookup for both registry classes
    $regTypeNames = @{ 0 = 'REG_NONE'; 1 = 'REG_SZ'; 2 = 'REG_EXPAND_SZ'; 3 = 'REG_BINARY'; 4 = 'REG_DWORD'; 7 = 'REG_MULTI_SZ'; 11 = 'REG_QWORD' }
    if ($null -ne $rawRegType) {
        if ($regTypeNames.ContainsKey([int]$rawRegType)) {
            $valueType = $regTypeNames[[int]$rawRegType]
        } else {
            $valueType = 'REG_TYPE_' + [int]$rawRegType
        }
    }
    #endregion

    return [pscustomobject]@{
        Namespace  = $Namespace
        Class      = $ClassName
        GpoId      = $gpoId
        GpoName    = $gpoName
        Precedence = $precedence
        SomId      = $somId
        Key        = $key
        Name       = $name
        ValueType  = $valueType
        Value      = $value
        Deleted    = $deleted
        Status     = $status
        ErrorCode  = $errorCode
        InstanceId = $instanceId
        Detail     = $detail
    }
}
