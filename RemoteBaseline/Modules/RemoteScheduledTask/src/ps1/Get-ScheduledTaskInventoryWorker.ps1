<#PSScriptInfo

.DESCRIPTION Returns the self-contained scriptblock that collects the scheduled task inventory on a target

.VERSION 1.3.0

.GUID dac065f2-91e4-4b6c-80f8-ae90183a82a2

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteScheduledTask/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteScheduledTask

#>

function Get-ScheduledTaskInventoryWorker {

    <#
    .SYNOPSIS
        Returns the self-contained scriptblock that collects the scheduled task inventory on a
        target.

    .DESCRIPTION
        The scriptblock this function returns is what actually runs on the target, local or
        remote, so it uses no module function, no module variable and no using: expression. It
        takes -ScheduleService, untyped and optional: production callers pass nothing and the
        scriptblock creates its own Schedule.Service COM object, tests pass a fake object built
        the same shape. It reads every scheduled task the ScheduledTasks module can see, exports
        each task's definition and flattens it into the fields an operator reads (the definition
        text itself is not kept), the run-time state of each task, the security descriptor the
        Task Scheduler service enforces, the account each task runs as and that account's SID,
        and the identity and signature of every distinct binary an Exec action starts, and
        returns one flat object describing the target and all of it. It never throws: every
        step is wrapped in its own try/catch and appends to
        an Errors list instead. It runs no native command and writes nothing to the target's disk.
        Invoke-ScheduledTaskInventoryLocal calls it directly for the local computer.
        Invoke-ScheduledTaskInventoryRemote passes it to Invoke-Command for every remote target.

    .NOTES
        FUNCTION: Get-ScheduledTaskInventoryWorker
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock
    #>

    param()

    return {
        param(
            $ScheduleService
        )

        # Off here, not only in the public function, so the worker behaves the same in-process as on a remote target, where strict mode is off by default.
        Set-StrictMode -Off

        function Get-ScheduledTaskInventoryXmlValue {
            <#
            .SYNOPSIS
                Returns the trimmed text of an XML value read through the PowerShell XML adapter.
            #>
            param(
                $Node
            )

            if ($null -eq $Node) { return $null }

            if ($Node -is [System.Xml.XmlNode]) {
                $text = $Node.InnerText
            } else {
                $text = [string]$Node
            }

            if ([string]::IsNullOrEmpty($text)) { return $null }
            $trimmedText = $text.Trim()
            if ($trimmedText.Length -eq 0) { return $null }
            return $trimmedText
        }

        function Get-ScheduledTaskInventoryExecutablePath {
            <#
            .SYNOPSIS
                Computes the ExecutablePath of one Exec action from its Command and WorkingDirectory.
            #>
            param(
                [AllowNull()]
                $Command,

                [AllowNull()]
                $WorkingDirectory
            )

            if ([string]::IsNullOrWhiteSpace($Command)) { return $null }

            $candidate = $Command.Trim()
            if ($candidate.StartsWith('"', [System.StringComparison]::Ordinal)) {
                $closeIndex = $candidate.IndexOf('"', 1)
                if ($closeIndex -gt 0) {
                    $candidate = $candidate.Substring(1, $closeIndex - 1)
                } else {
                    $candidate = $candidate.Substring(1)
                }
            }

            $candidate = [Environment]::ExpandEnvironmentVariables($candidate)
            if ($candidate.StartsWith('\??\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidate = $candidate.Substring(4)
            } elseif ($candidate.StartsWith('\SystemRoot\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $candidate = $env:SystemRoot + '\' + $candidate.Substring('\SystemRoot\'.Length)
            }

            $isRooted = $false
            try {
                $isRooted = [System.IO.Path]::IsPathRooted($candidate)
            } catch {
                $isRooted = $false
            }
            if ($isRooted) { return $candidate }

            if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
                $expandedWorkingDirectory = [Environment]::ExpandEnvironmentVariables($WorkingDirectory.Trim())
                $workingDirectoryRooted = $false
                try {
                    $workingDirectoryRooted = [System.IO.Path]::IsPathRooted($expandedWorkingDirectory)
                } catch {
                    $workingDirectoryRooted = $false
                }
                if ($workingDirectoryRooted) {
                    try {
                        $combined = Join-Path -Path $expandedWorkingDirectory -ChildPath $candidate
                        $combinedExists = Test-Path -LiteralPath $combined -PathType Leaf -ErrorAction Stop
                    } catch {
                        $combined = $null
                        $combinedExists = $false
                    }
                    if ($combinedExists) { return $combined }
                }
            }

            $foundCommand = $null
            try {
                $foundCommand = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            } catch {
                $foundCommand = $null
            }
            if ($foundCommand) { return $foundCommand.Source }

            return $candidate
        }

        $errors = @()

        #region Identity
        $dnsHostName = $null
        $domain = $null
        $partOfDomain = $false
        $domainRole = -1
        $osCaption = $null
        $osVersion = $null
        $currentBuild = $null
        $ubr = $null
        $displayVersion = $null
        $editionId = $null
        $installationType = $null
        $culture = $null
        $timeZoneId = $null
        $isElevated = $false
        $collectedBy = $null

        try {
            $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $currentBuild = $cv.CurrentBuild
            if ($null -ne $cv.UBR) { $ubr = $cv.UBR.ToString() }
            $displayVersion = $cv.DisplayVersion
            $editionId = $cv.EditionID
            $installationType = $cv.InstallationType
        } catch {
            $errors += "CurrentVersion key: $($_.Exception.Message)"
        }

        $os = $null
        $cs = $null
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop -Verbose:$false
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop -Verbose:$false
        } catch {
            $errors += "Get-CimInstance failed: $($_.Exception.Message)"
        }

        if ($null -ne $os) {
            $osCaption = $os.Caption
            $osVersion = $os.Version
        }
        if ($null -ne $cs) {
            $dnsHostName = $cs.DNSHostName
            $domain = $cs.Domain
            $partOfDomain = [bool]$cs.PartOfDomain
            if ($null -ne $cs.DomainRole) { $domainRole = [int]$cs.DomainRole }
        }

        try {
            $culture = [System.Globalization.CultureInfo]::CurrentCulture.Name
        } catch {
            $errors += "culture: $($_.Exception.Message)"
        }

        try {
            $timeZoneId = [System.TimeZoneInfo]::Local.Id
        } catch {
            $errors += "time zone: $($_.Exception.Message)"
        }

        try {
            $winIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $collectedBy = $winIdentity.Name
            $winPrincipal = New-Object System.Security.Principal.WindowsPrincipal($winIdentity)
            $isElevated = $winPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch {
            $errors += "elevation check: $($_.Exception.Message)"
            $isElevated = $false
        }

        # An unelevated caller sees only the items it may open. Without this line the row would be Success with a shorter inventory and IsElevated as the only signal; convention 1.2 asks for the shortfall to be named, which makes the row Partial.
        if (-not $isElevated) {
            $errors += 'not elevated: tasks the caller cannot open are not listed'
        }

        #region Computer identity
        $computerId = $null
        $machineGuid = $null
        try {
            $product = $null
            $product = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop -Verbose:$false
            if ($null -ne $product -and $null -ne $product.PSObject.Properties['UUID'] -and -not [string]::IsNullOrWhiteSpace([string]$product.UUID)) {
                $computerId = ([string]$product.UUID).Trim().ToUpperInvariant()
            }
        }
        catch { $errors += "identity: ComputerId: $($_.Exception.Message)" }
        try {
            $machineGuid = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        }
        catch { $errors += "identity: MachineGuid: $($_.Exception.Message)" }
        #endregion
        #endregion

        #region Tasks, xml and run-time state
        $tasks = @()
        $taskCount = 0
        $xmlFailedCount = 0
        $tasksDurationMs = 0

        $stopwatchTasks = [System.Diagnostics.Stopwatch]::StartNew()

        $runTaskDependentSteps = $false

        $rawTaskObjects = @()
        try {
            $rawTaskObjects = @(Get-ScheduledTask -ErrorAction Stop -Verbose:$false)
            $runTaskDependentSteps = $true
        } catch {
            $errors += "tasks: $($_.Exception.Message)"
            $rawTaskObjects = @()
        }

        # The key order of every task object in tasks.json, after the five keys filled from the cmdlet's own object. Every name starts as $null unless the table below gives it another initial value.
        $taskFieldNames = @(
            'LastRunTime', 'LastTaskResult', 'LastTaskResultHex', 'NextRunTime', 'NumberOfMissedRuns', 'Sddl', 'SddlError', 'Xml', 'XmlError', 'XmlParseError',
            'TaskVersion', 'Author', 'Date', 'Description', 'Documentation', 'URI', 'Source', 'Version', 'RegistrationSecurityDescriptor',
            'PrincipalId', 'UserId', 'GroupId', 'LogonType', 'RunLevel', 'DisplayName', 'ProcessTokenSidType', 'RequiredPrivileges', 'PrincipalToken', 'PrincipalSid', 'PrincipalName',
            'Hidden', 'SettingsEnabled', 'AllowStartOnDemand', 'AllowHardTerminate', 'DisallowStartIfOnBatteries', 'StopIfGoingOnBatteries', 'RunOnlyIfNetworkAvailable',
            'RunOnlyIfIdle', 'StartWhenAvailable', 'WakeToRun', 'ExecutionTimeLimit', 'Priority', 'MultipleInstancesPolicy', 'UseUnifiedSchedulingEngine',
            'DisallowStartOnRemoteAppSession', 'RestartOnFailure', 'MaintenanceSettings', 'ActionsContext',
            'ActionCount', 'ExecActionCount', 'ComHandlerActionCount', 'TriggerCount', 'TriggerTypes', 'Actions', 'Triggers'
        )
        $taskFieldDefaults = @{
            SddlError             = ''
            RequiredPrivileges    = @()
            ActionCount           = 0
            ExecActionCount       = 0
            ComHandlerActionCount = 0
            TriggerCount          = 0
            TriggerTypes          = ''
            Actions               = @()
            Triggers              = @()
        }
        # Task fields whose name is also the name of the xml element they are read from, in the order they are read. A field named differently from its element (PrincipalId, RegistrationSecurityDescriptor, SettingsEnabled and the Repetition fields of a trigger) is read on its own line.
        $registrationInfoFields = @('Author', 'Date', 'Description', 'Documentation', 'URI', 'Source', 'Version')
        $principalFields = @('UserId', 'GroupId', 'LogonType', 'RunLevel', 'DisplayName', 'ProcessTokenSidType')
        $settingsFields = @('Hidden', 'AllowStartOnDemand', 'AllowHardTerminate', 'DisallowStartIfOnBatteries', 'StopIfGoingOnBatteries', 'RunOnlyIfNetworkAvailable', 'RunOnlyIfIdle',
            'StartWhenAvailable', 'WakeToRun', 'ExecutionTimeLimit', 'Priority', 'MultipleInstancesPolicy', 'UseUnifiedSchedulingEngine', 'DisallowStartOnRemoteAppSession')
        $triggerFields = @('Enabled', 'StartBoundary', 'EndBoundary', 'ExecutionTimeLimit', 'Delay', 'UserId', 'Subscription', 'StateChange')

        $taskList = [System.Collections.Generic.List[object]]::new()
        foreach ($rawTask in $rawTaskObjects) {
            # Direct property reads: strict mode is off in this worker, so a property the cmdlet's object lacks reads as $null and needs no presence check.
            $rawTaskPath = $rawTask.TaskPath
            $rawTaskName = $rawTask.TaskName

            $stateText = $null
            if ($null -ne $rawTask.State) { $stateText = $rawTask.State.ToString() }

            $enabledValue = $null
            if ($null -ne $rawTask.Settings -and $null -ne $rawTask.Settings.Enabled) { $enabledValue = [bool]$rawTask.Settings.Enabled }

            $taskProperties = [ordered]@{
                TaskPath   = "$rawTaskPath$rawTaskName"
                FolderPath = $rawTaskPath
                TaskName   = $rawTaskName
                State      = $stateText
                Enabled    = $enabledValue
            }
            foreach ($fieldName in $taskFieldNames) {
                if ($taskFieldDefaults.ContainsKey($fieldName)) {
                    $taskProperties[$fieldName] = $taskFieldDefaults[$fieldName]
                } else {
                    $taskProperties[$fieldName] = $null
                }
            }
            [void]$taskList.Add([pscustomobject]$taskProperties)
        }

        $taskList.Sort( [Comparison[object]] { param($a, $b) [string]::Compare($a.TaskPath, $b.TaskPath, [System.StringComparison]::OrdinalIgnoreCase) } )
        # .ToArray(), not @(...): wrapping a generic List[object] with the array subexpression operator hits a PowerShell dynamic-binder mismatch once enough CIM types have loaded in the session.
        $tasks = $taskList.ToArray()
        $taskCount = $tasks.Count

        if ($runTaskDependentSteps -and $tasks.Count -gt 0) {
            #region Xml export
            foreach ($t in $tasks) {
                $exportedXml = $null
                $xmlErrorMessage = $null
                try {
                    $exportedXml = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.FolderPath -ErrorAction Stop -Verbose:$false
                } catch {
                    $xmlErrorMessage = $_.Exception.Message
                }

                if ($null -eq $xmlErrorMessage -and [string]::IsNullOrEmpty($exportedXml)) {
                    $xmlErrorMessage = 'empty export'
                }
                if ($null -ne $xmlErrorMessage) { $exportedXml = $null }

                $t.Xml = $exportedXml
                $t.XmlError = $xmlErrorMessage

                if ($null -ne $xmlErrorMessage) {
                    $xmlFailedCount++
                    $errors += "task $($t.TaskPath): xml: $xmlErrorMessage"
                }
            }
            #endregion

            #region Run-time state
            $infoCallThrew = $false
            $rawInfoResults = @()
            $infoErrors = $null
            try {
                # The cmdlet's own objects from step 2, not the pscustomobjects built from them: Get-ScheduledTaskInfo binds TaskName and TaskPath only by name, never by pipeline, and binds a CimInstance by pipeline value only through -InputObject, which is also the fast form (0.3 s against 203 tasks, the by-name form 3.6 s).
                $rawInfoResults = @($rawTaskObjects | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue -ErrorVariable infoErrors -Verbose:$false)
            } catch {
                $errors += "taskinfo: $($_.Exception.Message)"
                $rawInfoResults = @()
                $infoCallThrew = $true
            }

            if (-not $infoCallThrew) {
                foreach ($ie in @($infoErrors)) {
                    $ieException = $ie.PSObject.Properties['Exception']
                    $ieMessageText = $(if ($ieException -and $null -ne $ieException.Value) { $ieException.Value.Message } else { "$ie" })
                    $errors += "taskinfo: $ieMessageText"
                }
            }

            $infoByKey = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($info in $rawInfoResults) {
                $infoTaskPathProp = $info.PSObject.Properties['TaskPath']
                $infoTaskNameProp = $info.PSObject.Properties['TaskName']
                if (-not $infoTaskPathProp -or -not $infoTaskNameProp) { continue }
                $infoKey = "$($infoTaskPathProp.Value)$($infoTaskNameProp.Value)"
                $infoByKey[$infoKey] = $info
            }

            foreach ($t in $tasks) {
                $key = "$($t.FolderPath)$($t.TaskName)"
                $matchedInfo = $null
                if ($infoByKey.ContainsKey($key)) { $matchedInfo = $infoByKey[$key] }

                if ($null -eq $matchedInfo) {
                    if (-not $infoCallThrew) {
                        $errors += "task $($t.TaskPath): info: not returned"
                    }
                    continue
                }

                # In its own try, so a value the cast or the conversion refuses (a missed-run count outside the int range, say) costs that one task its run-time fields and adds one error line, instead of ending the worker with an exception and no result at all.
                try {
                    $lastRunTimeValue = $matchedInfo.LastRunTime
                    if ($null -ne $lastRunTimeValue) {
                        $t.LastRunTime = $lastRunTimeValue.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
                    }

                    $lastTaskResultValue = $matchedInfo.LastTaskResult
                    if ($null -ne $lastTaskResultValue) {
                        $t.LastTaskResult = [int64]$lastTaskResultValue
                        $t.LastTaskResultHex = '0x' + ('{0:X8}' -f [uint32]$lastTaskResultValue)
                    }

                    $nextRunTimeValue = $matchedInfo.NextRunTime
                    if ($null -ne $nextRunTimeValue) {
                        $t.NextRunTime = $nextRunTimeValue.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
                    }

                    $missedRunsValue = $matchedInfo.NumberOfMissedRuns
                    if ($null -ne $missedRunsValue) { $t.NumberOfMissedRuns = [int]$missedRunsValue }
                } catch {
                    $errors += "task $($t.TaskPath): info: $($_.Exception.Message)"
                }
            }
            #endregion
        }

        $stopwatchTasks.Stop()
        $tasksDurationMs = [int]$stopwatchTasks.ElapsedMilliseconds
        #endregion

        #region Security descriptors
        $sddlFailedCount = 0
        $sddlDurationMs = 0

        if ($runTaskDependentSteps -and $tasks.Count -gt 0) {
            $stopwatchSddl = [System.Diagnostics.Stopwatch]::StartNew()

            $scheduleServiceObject = $ScheduleService
            $connectFailed = $false
            $connectErrorMessage = $null
            try {
                if ($null -eq $scheduleServiceObject) {
                    $scheduleServiceObject = New-Object -ComObject Schedule.Service
                }
                $scheduleServiceObject.Connect()
            } catch {
                $connectFailed = $true
                $rawMessage = $_.Exception.GetBaseException().Message
                $connectErrorMessage = ([string]$rawMessage).Trim() -replace '\s+', ' '
            }

            if ($connectFailed) {
                foreach ($t in $tasks) {
                    $t.SddlError = $connectErrorMessage
                }
                $sddlFailedCount = $tasks.Count
                $errors += "sddl: $connectErrorMessage"
            } else {
                $folderCache = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($t in $tasks) {
                    $sddlText = $null
                    $sddlErrorMessage = ''
                    try {
                        $folderKey = $t.FolderPath
                        if ($folderKey.Length -gt 1 -and $folderKey.EndsWith('\', [System.StringComparison]::Ordinal)) {
                            $folderKey = $folderKey.Substring(0, $folderKey.Length - 1)
                        }
                        if ([string]::IsNullOrEmpty($folderKey)) { $folderKey = '\' }

                        if ($folderCache.ContainsKey($folderKey)) {
                            $folderObject = $folderCache[$folderKey]
                        } else {
                            $folderObject = $scheduleServiceObject.GetFolder($folderKey)
                            $folderCache[$folderKey] = $folderObject
                        }

                        $comTaskObject = $folderObject.GetTask($t.TaskName)
                        $sddlText = $comTaskObject.GetSecurityDescriptor(7)
                    } catch {
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $sddlErrorMessage = ([string]$rawMessage).Trim() -replace '\s+', ' '
                        $sddlText = $null
                    }

                    if ($sddlErrorMessage) {
                        $sddlFailedCount++
                        $errors += "task $($t.TaskPath): sddl: $sddlErrorMessage"
                    }

                    $t.Sddl = $sddlText
                    $t.SddlError = $sddlErrorMessage
                }
            }

            $stopwatchSddl.Stop()
            $sddlDurationMs = [int]$stopwatchSddl.ElapsedMilliseconds
        }
        #endregion

        #region Flat fields from the registration xml
        foreach ($t in $tasks) {
            if ($null -eq $t.Xml) { continue }

            try {
                $doc = [xml]$t.Xml
                $taskNode = $doc.Task

                $t.TaskVersion = Get-ScheduledTaskInventoryXmlValue -Node $taskNode.version

                $regInfo = $taskNode.RegistrationInfo
                foreach ($fieldName in $registrationInfoFields) {
                    $t.$fieldName = Get-ScheduledTaskInventoryXmlValue -Node $regInfo.$fieldName
                }
                $t.RegistrationSecurityDescriptor = Get-ScheduledTaskInventoryXmlValue -Node $regInfo.SecurityDescriptor

                $principalNode = $taskNode.Principals.Principal
                $t.PrincipalId = Get-ScheduledTaskInventoryXmlValue -Node $principalNode.id
                foreach ($fieldName in $principalFields) {
                    $t.$fieldName = Get-ScheduledTaskInventoryXmlValue -Node $principalNode.$fieldName
                }

                $requiredPrivilegesList = New-Object System.Collections.Generic.List[string]
                $requiredPrivilegesNode = $principalNode.RequiredPrivileges
                foreach ($privilegeChild in $requiredPrivilegesNode.ChildNodes) {
                    if ($privilegeChild.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    $privilegeValue = Get-ScheduledTaskInventoryXmlValue -Node $privilegeChild
                    if ($null -ne $privilegeValue) { [void]$requiredPrivilegesList.Add($privilegeValue) }
                }
                $t.RequiredPrivileges = @($requiredPrivilegesList.ToArray())

                if ($t.UserId) {
                    $t.PrincipalToken = $t.UserId
                } elseif ($t.GroupId) {
                    $t.PrincipalToken = $t.GroupId
                }

                $settingsNode = $taskNode.Settings
                foreach ($fieldName in $settingsFields) {
                    $t.$fieldName = Get-ScheduledTaskInventoryXmlValue -Node $settingsNode.$fieldName
                }
                $t.SettingsEnabled = Get-ScheduledTaskInventoryXmlValue -Node $settingsNode.Enabled

                if ($null -ne $settingsNode.RestartOnFailure) { $t.RestartOnFailure = 'true' }
                if ($null -ne $settingsNode.MaintenanceSettings) { $t.MaintenanceSettings = 'true' }

                $actionsNode = $taskNode.Actions
                $t.ActionsContext = Get-ScheduledTaskInventoryXmlValue -Node $actionsNode.Context

                $actionList = [System.Collections.Generic.List[object]]::new()
                $execActionCount = 0
                $comHandlerActionCount = 0
                foreach ($actionNode in $actionsNode.ChildNodes) {
                    if ($actionNode.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                    $actionType = $actionNode.LocalName
                    $actionCommand = $null
                    $actionArguments = $null
                    $actionWorkingDirectory = $null
                    $actionExecutablePath = $null
                    $actionClassId = $null
                    $actionData = $null
                    $actionXml = $null

                    if ($actionType -eq 'Exec') {
                        $actionCommand = Get-ScheduledTaskInventoryXmlValue -Node $actionNode.Command
                        $actionArguments = Get-ScheduledTaskInventoryXmlValue -Node $actionNode.Arguments
                        $actionWorkingDirectory = Get-ScheduledTaskInventoryXmlValue -Node $actionNode.WorkingDirectory
                        $actionExecutablePath = Get-ScheduledTaskInventoryExecutablePath -Command $actionCommand -WorkingDirectory $actionWorkingDirectory
                        $execActionCount++
                    } elseif ($actionType -eq 'ComHandler') {
                        $actionClassId = Get-ScheduledTaskInventoryXmlValue -Node $actionNode.ClassId
                        $actionData = Get-ScheduledTaskInventoryXmlValue -Node $actionNode.Data
                        $comHandlerActionCount++
                    } elseif ($actionType -eq 'SendEmail' -or $actionType -eq 'ShowMessage') {
                        $actionXml = $actionNode.OuterXml
                    }

                    [void]$actionList.Add([pscustomobject]@{
                        Type             = $actionType
                        Id               = (Get-ScheduledTaskInventoryXmlValue -Node $actionNode.id)
                        Command          = $actionCommand
                        Arguments        = $actionArguments
                        WorkingDirectory = $actionWorkingDirectory
                        ExecutablePath   = $actionExecutablePath
                        ClassId          = $actionClassId
                        Data             = $actionData
                        Xml              = $actionXml
                    })
                }
                $t.Actions = @($actionList.ToArray())
                $t.ActionCount = $actionList.Count
                $t.ExecActionCount = $execActionCount
                $t.ComHandlerActionCount = $comHandlerActionCount

                $triggersNode = $taskNode.Triggers
                $triggerList = [System.Collections.Generic.List[object]]::new()
                $triggerTypeOrder = New-Object System.Collections.Generic.List[string]
                $triggerTypeSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($triggerNode in $triggersNode.ChildNodes) {
                    if ($triggerNode.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                    $triggerType = $triggerNode.LocalName
                    if ($triggerTypeSeen.Add($triggerType)) { [void]$triggerTypeOrder.Add($triggerType) }

                    $repetitionNode = $triggerNode.Repetition

                    $triggerProperties = [ordered]@{
                        Type = $triggerType
                        Id   = (Get-ScheduledTaskInventoryXmlValue -Node $triggerNode.id)
                    }
                    foreach ($fieldName in $triggerFields) {
                        $triggerProperties[$fieldName] = Get-ScheduledTaskInventoryXmlValue -Node $triggerNode.$fieldName
                    }
                    $triggerProperties['RepetitionInterval'] = Get-ScheduledTaskInventoryXmlValue -Node $repetitionNode.Interval
                    $triggerProperties['RepetitionDuration'] = Get-ScheduledTaskInventoryXmlValue -Node $repetitionNode.Duration
                    $triggerProperties['RepetitionStopAtDurationEnd'] = Get-ScheduledTaskInventoryXmlValue -Node $repetitionNode.StopAtDurationEnd
                    [void]$triggerList.Add([pscustomobject]$triggerProperties)
                }
                $t.Triggers = @($triggerList.ToArray())
                $t.TriggerCount = $triggerList.Count
                $t.TriggerTypes = [string]::Join(',', $triggerTypeOrder.ToArray())
            } catch {
                $t.XmlParseError = $_.Exception.Message
                $xmlFailedCount++
                $errors += "task $($t.TaskPath): xml: $($_.Exception.Message)"
            }
        }
        #endregion

        #region Drop the exported xml text, every field it holds has already been read
        foreach ($t in $tasks) {
            $t.PSObject.Properties.Remove('Xml')
        }
        #endregion

        #region Accounts
        $accounts = @()
        $accountCount = 0
        $accountUnresolvedCount = 0
        $accountsDurationMs = 0

        $stopwatchAccounts = [System.Diagnostics.Stopwatch]::StartNew()

        # The grouping, every lookup and the fill-back all sit inside one try/catch, so a failure anywhere in this step never stops the binaries step that follows: the account data for this run is simply empty, with the reason in $errors.
        try {
            $tokenTasks = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
            $tokenOrder = New-Object System.Collections.Generic.List[string]

            # First spelling seen per case-insensitive PrincipalToken is kept as the account's Token, so two tasks differing only by PrincipalToken casing still resolve to one account row.
            foreach ($t in $tasks) {
                $token = $t.PrincipalToken
                if ([string]::IsNullOrEmpty($token)) { continue }
                if (-not $tokenTasks.ContainsKey($token)) {
                    $tokenTasks[$token] = New-Object System.Collections.Generic.List[string]
                    [void]$tokenOrder.Add($token)
                }
                $tokenTasks[$token].Add($t.TaskPath)
            }

            $tokenOrder.Sort( [Comparison[string]] { param($a, $b) [string]::Compare($a, $b, [System.StringComparison]::Ordinal) } )

            $accountByToken = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($token in $tokenOrder) {
                # A leading * (the secedit export form) is ignored for the Kind test only, never for the token itself.
                $sidCandidate = $token
                if ($sidCandidate.StartsWith('*', [System.StringComparison]::Ordinal)) { $sidCandidate = $sidCandidate.Substring(1) }

                $kind = 'Name'
                if ($sidCandidate -match '^S-1-\d+(-\d+)+$') { $kind = 'Sid' }

                $sid = $null
                $accountName = $null
                $status = 'Resolved'
                $acctError = ''

                if ($kind -eq 'Sid') {
                    # The token without the * is kept as Sid always, resolved or not.
                    $sid = $sidCandidate
                    try {
                        $securityId = New-Object System.Security.Principal.SecurityIdentifier($sidCandidate)
                        $translatedAccount = $securityId.Translate([System.Security.Principal.NTAccount])
                        $accountName = $translatedAccount.Value
                    } catch {
                        $status = 'NotFound'
                        $accountName = $null
                        # The innermost exception's own message, not the method-invocation wrapper, trimmed and with every run of whitespace, line breaks included, collapsed to one space, so a NotFound account's Error is always a single line.
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $acctError = ([string]$rawMessage).Trim() -replace '\s+', ' '
                    }
                } else {
                    $lookupName = $token
                    try {
                        if ($token -ieq 'LocalSystem') {
                            # The Service Control Manager's own alias, not a real account, so it never goes through a lookup.
                            $sid = 'S-1-5-18'
                        } else {
                            if ($token.StartsWith('.\', [System.StringComparison]::Ordinal)) {
                                $lookupName = $env:COMPUTERNAME + $token.Substring(1)
                            }
                            $ntAccount = New-Object System.Security.Principal.NTAccount($lookupName)
                            $translated = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
                            $sid = $translated.Value
                        }
                    } catch {
                        $status = 'NotFound'
                        $sid = $null
                        $rawMessage = $_.Exception.GetBaseException().Message
                        $acctError = ([string]$rawMessage).Trim() -replace '\s+', ' '
                    }
                    $accountName = $lookupName
                }

                # Sorted in place: each token's list is read for this one account only, so a copy would add nothing.
                $taskPathsForToken = $tokenTasks[$token]
                $taskPathsForToken.Sort( [Comparison[string]] { param($a, $b) [string]::Compare($a, $b, [System.StringComparison]::OrdinalIgnoreCase) } )

                $accountObject = [pscustomobject]@{
                    Token          = $token
                    Kind           = $kind
                    Sid            = $sid
                    Name           = $accountName
                    Status         = $status
                    ReferenceCount = $taskPathsForToken.Count
                    References     = @($taskPathsForToken.ToArray())
                    Error          = $acctError
                }

                $accounts += $accountObject
                $accountByToken[$token] = $accountObject

                if ($status -eq 'NotFound') { $accountUnresolvedCount++ }
            }

            $accountCount = $accounts.Count

            foreach ($t in $tasks) {
                $token = $t.PrincipalToken
                if ([string]::IsNullOrEmpty($token)) { continue }
                $matchedAccount = $accountByToken[$token]
                if ($null -ne $matchedAccount) {
                    $t.PrincipalSid = $matchedAccount.Sid
                    $t.PrincipalName = $matchedAccount.Name
                }
            }
        } catch {
            $errors += "accounts: $($_.Exception.Message)"
            $accounts = @()
            $accountCount = 0
            $accountUnresolvedCount = 0
            foreach ($t in $tasks) {
                $t.PrincipalSid = $null
                $t.PrincipalName = $null
            }
        } finally {
            $stopwatchAccounts.Stop()
            $accountsDurationMs = [int]$stopwatchAccounts.ElapsedMilliseconds
        }
        #endregion

        #region Binaries
        $binaries = @()
        $binaryCount = 0
        $binaryMissingCount = 0
        $binariesDurationMs = 0

        $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $execPathList = New-Object System.Collections.Generic.List[string]
        foreach ($t in $tasks) {
            foreach ($action in $t.Actions) {
                if ($action.Type -ne 'Exec') { continue }
                $ep = $action.ExecutablePath
                if ($ep -and $seenPaths.Add($ep)) { [void]$execPathList.Add($ep) }
            }
        }
        $execPathList.Sort( [Comparison[string]] { param($a, $b) [string]::Compare($a, $b, [System.StringComparison]::Ordinal) } )

        $stopwatchBinaries = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($path in $execPathList) {
            $exists = $false
            $length = $null
            $lastWrite = $null
            $fileVersion = $null
            $productVersion = $null
            $companyName = $null
            $productName = $null
            $fileDescription = $null
            $originalFilename = $null
            $internalName = $null
            $sha256 = $null
            $sigStatus = $null
            $sigStatusMessage = $null
            $signerSubject = $null
            $signerThumbprint = $null
            $binError = ''

            try {
                $exists = Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop
            } catch {
                $exists = $false
            }

            if (-not $exists) {
                $binError = 'not found'
                $errors += "binary ${path}: not found"
                $binaryMissingCount++
            } else {
                try {
                    $fileInfo = Get-Item -LiteralPath $path -ErrorAction Stop
                    $length = [int64]$fileInfo.Length
                    $lastWrite = $fileInfo.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

                    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
                    $fileVersion = $versionInfo.FileVersion
                    $productVersion = $versionInfo.ProductVersion
                    $companyName = $versionInfo.CompanyName
                    $productName = $versionInfo.ProductName
                    $fileDescription = $versionInfo.FileDescription
                    $originalFilename = $versionInfo.OriginalFilename
                    $internalName = $versionInfo.InternalName

                    $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()

                    $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
                    $sigStatus = $signature.Status.ToString()
                    $sigStatusMessage = $signature.StatusMessage
                    if ($null -ne $signature.SignerCertificate) {
                        $signerSubject = $signature.SignerCertificate.Subject
                        $signerThumbprint = $signature.SignerCertificate.Thumbprint
                    }
                } catch {
                    $binError = "binary ${path}: $($_.Exception.Message)"
                    $errors += $binError
                    $binaryMissingCount++
                }
            }

            $binaries += [pscustomobject]@{
                Path                   = $path
                Exists                 = $exists
                Length                 = $length
                LastWriteTimeUtc       = $lastWrite
                FileVersion            = $fileVersion
                ProductVersion         = $productVersion
                CompanyName            = $companyName
                ProductName            = $productName
                FileDescription        = $fileDescription
                OriginalFilename       = $originalFilename
                InternalName           = $internalName
                Sha256                 = $sha256
                SignatureStatus        = $sigStatus
                SignatureStatusMessage = $sigStatusMessage
                SignerSubject          = $signerSubject
                SignerThumbprint       = $signerThumbprint
                Error                  = $binError
            }
        }
        $stopwatchBinaries.Stop()
        $binariesDurationMs = [int]$stopwatchBinaries.ElapsedMilliseconds
        $binaryCount = $binaries.Count
        #endregion

        #region Return
        $hiddenCount = 0
        foreach ($t in $tasks) {
            if ($t.Hidden -and ($t.Hidden -ieq 'true')) { $hiddenCount++ }
        }

        $collectedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)

        [pscustomobject]@{
            ComputerName           = $env:COMPUTERNAME
            DnsHostName            = $dnsHostName
            Domain                 = $domain
            OSCaption              = $osCaption
            OSVersion              = $osVersion
            CurrentBuild           = $currentBuild
            UBR                    = $ubr
            DisplayVersion         = $displayVersion
            EditionID              = $editionId
            InstallationType       = $installationType
            Culture                = $culture
            TimeZoneId             = $timeZoneId
            PSVersion              = $PSVersionTable.PSVersion.ToString()
            CollectedBy            = $collectedBy
            PartOfDomain           = [bool]$partOfDomain
            IsElevated             = [bool]$isElevated
            DomainRole             = [int]$domainRole
            CollectedUtc           = $collectedUtc
            ComputerId             = $computerId
            MachineGuid            = $machineGuid
            TaskCount              = [int]$taskCount
            XmlFailedCount         = [int]$xmlFailedCount
            SddlFailedCount        = [int]$sddlFailedCount
            BinaryCount            = [int]$binaryCount
            BinaryMissingCount     = [int]$binaryMissingCount
            AccountCount           = [int]$accountCount
            AccountUnresolvedCount = [int]$accountUnresolvedCount
            HiddenCount            = [int]$hiddenCount
            TasksDurationMs        = [int]$tasksDurationMs
            SddlDurationMs         = [int]$sddlDurationMs
            AccountsDurationMs     = [int]$accountsDurationMs
            BinariesDurationMs     = [int]$binariesDurationMs
            Tasks                  = @($tasks)
            Accounts               = @($accounts)
            Binaries               = @($binaries)
            Errors                 = @($errors | ForEach-Object { ([string]$_).Trim() -replace '\s+', ' ' })
        }
        #endregion
    }
}
