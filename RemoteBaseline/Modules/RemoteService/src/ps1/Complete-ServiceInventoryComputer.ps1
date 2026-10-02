<#PSScriptInfo

.DESCRIPTION Turns one worker object into a result row, and writes its per-computer folder

.VERSION 1.4.0

.GUID 9ad44ca9-108b-4409-9555-ef194217103d

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteService/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteService

#>

function Complete-ServiceInventoryComputer {

    <#
    .SYNOPSIS
        Turns one worker object into a result row, and writes its per-computer folder.

    .DESCRIPTION
        Turns one worker object, or nothing plus the errors that explain why there is none, into
        a result row. When a worker object is present, it also writes the per-computer folder.
        Called once per computer: a caller with several local aliases for the same computer calls
        this once for the first alias and copies the returned row for every later one, changing
        only ComputerName, so no two rows for one folder can ever disagree on Status, a count or
        Errors. Status is computed from the worker object's own counts and its own Errors list
        alone, before any host-side error (a write failure) is appended, so a problem the host
        has while writing the files never changes a Status the target-side collection already
        earned.

    .PARAMETER RequestedComputerName
        The name as the caller requested it, used for the result row and any error messages.

    .PARAMETER Transport
        Local or WinRM.

    .PARAMETER RunFolder
        The run folder a new per-computer folder is created under. Its leaf name is also the
        RunId recorded in system.json.

    .PARAMETER WorkerObject
        The object Get-ServiceInventoryWorker's scriptblock returned, or $null when the target
        produced nothing.

    .PARAMETER ExtraErrors
        Errors already known before this call, folded into the row's Errors alongside anything
        found here. May be empty or $null.

    .NOTES
        FUNCTION: Complete-ServiceInventoryComputer
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject, type name RemoteService.Result
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedComputerName,

        [Parameter(Mandatory = $true)]
        [string]$Transport,

        [Parameter(Mandatory = $true)]
        [string]$RunFolder,

        [AllowNull()]
        [psobject]$WorkerObject,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ExtraErrors
    )

    $errors = @()
    # Every host-side message added to $errors is collapsed to one trimmed line where it is added: the list goes to system.json as it stands, and the message of a failed write or a remote call can carry a line break.
    if ($ExtraErrors) { $errors += @($ExtraErrors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' }) }

    if ($null -eq $WorkerObject) {
        return ConvertTo-ServiceInventoryResultRow -ComputerName $RequestedComputerName -Status 'Failed' -Transport $Transport -Errors $errors
    }

    # Set before the try so the catch-all below always has a value to return, even when a later step here throws: a computer that was reached still carries its ComputerId.
    $computerId = $null

    try {
        # A malformed worker object can carry $null or empty-string entries in Errors, dropped here so a summary or a results row never shows a blank line for one.
        $workerErrors = @(Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'Errors' -Default @() | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $errors += $workerErrors

        $computerId = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerId' -Default $null
        $serviceCount = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'ServiceCount' -Default $null
        $sddlFailedCount = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'SddlFailedCount' -Default $null
        $binaryCount = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'BinaryCount' -Default $null
        $binaryMissingCount = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'BinaryMissingCount' -Default $null
        $accountCount = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'AccountCount' -Default $null
        $accountUnresolvedCount = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'AccountUnresolvedCount' -Default $null

        # Status is computed from the worker object's own counts and its own Errors list, never from anything the host adds afterward. A $null count (a malformed or partial worker object) is not the same as a verified 0, so Success also requires both counts to be present.
        if (($null -eq $serviceCount) -or ([int]$serviceCount -eq 0)) {
            $status = 'Failed'
        } elseif (($null -ne $sddlFailedCount) -and ($null -ne $binaryMissingCount) -and ([int]$sddlFailedCount -eq 0) -and ([int]$binaryMissingCount -eq 0) -and ($workerErrors.Count -eq 0)) {
            $status = 'Success'
        } else {
            $status = 'Partial'
        }

        $reportedName = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'ComputerName' -Default $RequestedComputerName
        if ([string]::IsNullOrWhiteSpace($reportedName)) { $reportedName = $RequestedComputerName }
        $reportedNameUpper = $reportedName.ToUpperInvariant()

        $buildNumber = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'CurrentBuild' -Default $null
        if ([string]::IsNullOrWhiteSpace($buildNumber)) { $buildNumber = 'unknown' }

        $folderStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
        # The reported name comes from the target. A name carrying path separators, dots or wildcard characters must not steer the folder outside the run folder or trip the provider, so anything outside letters, digits, underscore and hyphen becomes an underscore. ASCII NetBIOS names are unchanged; a name with other letters gets underscores and stays unique through the suffix rule.
        $safeReportedName = [regex]::Replace($reportedNameUpper, '[^A-Za-z0-9_-]', '_')
        # The build number is a registry string read on the target, so it gets the same reduction. The stamp is generated here and stays.
        $safeBuildNumber = [regex]::Replace([string]$buildNumber, '[^A-Za-z0-9_-]', '_')
        $folderName = '{0}_{1}_{2}Z' -f $safeReportedName, $safeBuildNumber, $folderStamp
        $outputFolder = Resolve-ServiceInventoryUniqueFolder -Path (Join-Path $RunFolder $folderName)

        $services = @(Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'Services' -Default @())
        $accounts = @(Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'Accounts' -Default @())
        $binaries = @(Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'Binaries' -Default @())

        try {
            # -InputObject @($services), not a pipe, so an empty array still serialises to [] and a one-element array still serialises to a one-element array, rather than collapsing to a bare object.
            $servicesJson = ConvertTo-Json -InputObject @($services) -Depth 4
            Write-ServiceInventoryTextFile -Path (Join-Path $outputFolder 'services.json') -Content $servicesJson
        } catch {
            $errors += ("write services.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $csvRows = @(ConvertTo-ServiceInventoryServiceCsvRow -Services $services -Binaries $binaries)
            $serviceCsvColumns = @('Name', 'DisplayName', 'State', 'StartMode', 'DelayedAutoStart', 'StartName', 'StartNameSid', 'ServiceType', 'PathName', 'ExecutablePath', 'ProcessId', 'DesktopInteract', 'ErrorControl', 'Sddl', 'SddlExitCode', 'BinaryExists', 'BinaryCompanyName', 'BinaryProductName', 'BinaryFileVersion', 'BinarySignatureStatus', 'BinarySignerSubject', 'Description')
            Write-ServiceInventoryCsvFile -Row $csvRows -Path (Join-Path $outputFolder 'services.csv') -Column $serviceCsvColumns
        } catch {
            $errors += ("write services.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $accountsJson = ConvertTo-Json -InputObject @($accounts) -Depth 4
            Write-ServiceInventoryTextFile -Path (Join-Path $outputFolder 'accounts.json') -Content $accountsJson
        } catch {
            $errors += ("write accounts.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $accountCsvColumns = @('Token', 'Kind', 'Sid', 'Name', 'Status', 'ReferenceCount', 'Error')
            $accountCsvRows = @($accounts | Select-Object -Property $accountCsvColumns)
            Write-ServiceInventoryCsvFile -Row $accountCsvRows -Path (Join-Path $outputFolder 'accounts.csv') -Column $accountCsvColumns
        } catch {
            $errors += ("write accounts.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $binariesJson = ConvertTo-Json -InputObject @($binaries) -Depth 4
            Write-ServiceInventoryTextFile -Path (Join-Path $outputFolder 'binaries.json') -Content $binariesJson
        } catch {
            $errors += ("write binaries.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $binaryCsvColumns = @('Path', 'Exists', 'Length', 'LastWriteTimeUtc', 'FileVersion', 'ProductVersion', 'CompanyName', 'ProductName', 'FileDescription', 'OriginalFilename', 'InternalName', 'Sha256', 'SignatureStatus', 'SignatureStatusMessage', 'SignerSubject', 'SignerThumbprint', 'Error')
            $binaryCsvRows = @($binaries | Select-Object -Property $binaryCsvColumns)
            Write-ServiceInventoryCsvFile -Row $binaryCsvRows -Path (Join-Path $outputFolder 'binaries.csv') -Column $binaryCsvColumns
        } catch {
            $errors += ("write binaries.csv on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            $summaryObject = [pscustomobject]@{
                ServiceCount            = $serviceCount
                SddlFailedCount         = $sddlFailedCount
                SddlFailedItems         = @($services | Where-Object { $_.SddlExitCode -ne 0 -or -not $_.Sddl } | Select-Object -ExpandProperty Name)
                ServicesDurationMs      = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'ServicesDurationMs' -Default $null
                SddlDurationMs          = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'SddlDurationMs' -Default $null
                AccountsDurationMs      = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'AccountsDurationMs' -Default $null
                BinariesDurationMs      = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'BinariesDurationMs' -Default $null
                AccountCount            = $accountCount
                AccountUnresolvedCount  = $accountUnresolvedCount
                AccountUnresolvedTokens = @($accounts | Where-Object { $_.Status -eq 'NotFound' } | Select-Object -ExpandProperty Token)
                BinaryCount             = $binaryCount
                BinaryMissingCount      = $binaryMissingCount
                BinaryMissingPaths      = @($binaries | Where-Object { -not $_.Exists -or $_.Error } | Select-Object -ExpandProperty Path)
            }
            $summaryJson = $summaryObject | ConvertTo-Json -Depth 6
            Write-ServiceInventoryTextFile -Path (Join-Path $outputFolder 'summary.json') -Content $summaryJson
        } catch {
            $errors += ("write summary.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        try {
            # Built as an explicit ordered list of names, not by enumerating $WorkerObject.PSObject.Properties, so the key order in system.json always matches the output convention regardless of how a worker object happened to be built (a live worker return or a PSSerializer round trip).
            $systemObject = [ordered]@{}
            $identityPropertyOrder = @('ComputerName', 'DnsHostName', 'Domain', 'OSCaption', 'OSVersion', 'CurrentBuild', 'UBR',
                'DisplayVersion', 'EditionID', 'InstallationType', 'Culture', 'TimeZoneId', 'PSVersion', 'CollectedBy',
                'PartOfDomain', 'IsElevated', 'DomainRole', 'CollectedUtc', 'ComputerId', 'MachineGuid',
                'MachineSid', 'DomainSid', 'ComputerAccountSid', 'DomainNetbiosName')
            foreach ($name in $identityPropertyOrder) {
                $systemObject[$name] = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Collector'] = 'RemoteService'
            $systemObject['CollectorVersion'] = $MyInvocation.MyCommand.Module.Version.ToString()
            $systemObject['RunId'] = Split-Path -Path $RunFolder -Leaf

            $modulePropertyOrder = @('ScPath', 'ServiceCount', 'SddlFailedCount', 'BinaryCount', 'BinaryMissingCount',
                'AccountCount', 'AccountUnresolvedCount', 'ServicesDurationMs', 'SddlDurationMs', 'AccountsDurationMs', 'BinariesDurationMs')
            foreach ($name in $modulePropertyOrder) {
                $systemObject[$name] = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name $name -Default $null
            }

            $systemObject['Errors'] = @($errors)
            $systemObject['Transport'] = $Transport
            $systemObject['RequestedComputerName'] = $RequestedComputerName
            $systemObject['Status'] = $status

            $systemJson = [pscustomobject]$systemObject | ConvertTo-Json -Depth 6
            Write-ServiceInventoryTextFile -Path (Join-Path $outputFolder 'system.json') -Content $systemJson
        } catch {
            $errors += ("write system.json on ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        }

        $isElevatedValue = Get-ServiceInventorySafeProperty -InputObject $WorkerObject -Name 'IsElevated' -Default $null
        if ($null -ne $isElevatedValue) { $isElevatedValue = [bool]$isElevatedValue }

        return ConvertTo-ServiceInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status $status -Transport $Transport `
            -OutputFolder $outputFolder -IsElevated $isElevatedValue `
            -ServiceCount $serviceCount -SddlFailedCount $sddlFailedCount `
            -BinaryCount $binaryCount -BinaryMissingCount $binaryMissingCount `
            -AccountCount $accountCount -AccountUnresolvedCount $accountUnresolvedCount `
            -Errors $errors
    } catch {
        $errors += ("unexpected error processing ${RequestedComputerName}: $($_.Exception.Message)" -replace '\s+', ' ').Trim()
        return ConvertTo-ServiceInventoryResultRow -ComputerName $RequestedComputerName -ComputerId $computerId -Status 'Failed' -Transport $Transport -Errors $errors
    }
}
