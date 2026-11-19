<#PSScriptInfo

.DESCRIPTION Runs the worker on one or more remote computers with a single Invoke-Command call

.VERSION 1.0.0

.GUID 896c0075-7eb4-4166-bc62-f3abac979521

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Invoke-SystemInventoryRemote
function Invoke-SystemInventoryRemote {

    <#
    .SYNOPSIS
        Runs the worker on one or more remote computers with a single Invoke-Command call.

    .DESCRIPTION
        Kept as its own function, rather than calling Invoke-Command directly from the public
        function, so tests can mock this one boundary and control both the streamed worker
        objects and the error records without depending on -ErrorVariable behaviour under a mock.
        Each worker-shaped object carrying a PSComputerName note property is passed to -OnResult
        as it arrives from the pipeline, one at a time, so the caller can finish with one result
        (write its folder, build its row) and drop its reference before the next one is held,
        rather than holding every target's result until the whole pipeline ends. Every error
        record Invoke-Command collects through -ErrorVariable is returned once the pipeline has
        ended.

    .PARAMETER ComputerName
        The remote targets to contact, already resolved and de-duplicated.

    .PARAMETER Credential
        Forwarded to Invoke-Command when supplied. Omitted entirely, not passed as $null, when
        the caller supplies nothing.

    .PARAMETER ThrottleLimit
        Forwarded to Invoke-Command.

    .PARAMETER OnResult
        Invoked once per worker-shaped object as it arrives from Invoke-Command, before the next
        one is read from the pipeline.

    .PARAMETER UseSSL
        Forwarded to Invoke-Command as UseSSL when set. Omitted entirely, not passed as
        $false, when the caller does not supply it.

    .PARAMETER SkipSidReference
        Handed to the worker as its first argument, a real bool, on every call: false without the
        switch, true with it. The worker's first parameter is -SkipSidReference, so the first
        element of the argument list binds to it. True leaves the SID reference unread.

    .PARAMETER SkipDismFeatures
        Handed to the worker as its second argument, a real bool, on every call: false without
        the switch, true with it. The worker's second parameter is -SkipDismFeatures. True leaves
        the DISM feature list unread.

    .NOTES
        FUNCTION: Invoke-SystemInventoryRemote
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String[]]$ComputerName,

        [System.Management.Automation.PSCredential]
        $Credential,

        [Parameter(Mandatory = $true)]
        [Int]$ThrottleLimit,

        [Parameter(Mandatory = $true)]
        [ScriptBlock]$OnResult,

        [Switch]$UseSSL,

        [Switch]$SkipSidReference,

        [Switch]$SkipDismFeatures
    )

    $invokeParams = @{
        ComputerName  = @($ComputerName)
        ScriptBlock   = Get-SystemInventoryWorker
        ThrottleLimit = $ThrottleLimit
        ErrorAction   = 'SilentlyContinue'
        ErrorVariable = 'remoteErrors'
    }
    if ($Credential) {
        $invokeParams['Credential'] = $Credential
    }
    if ($UseSSL) {
        $invokeParams['UseSSL'] = $true
    }
    # Always passed, with or without the switches, as real bools in the order of the worker's parameters:
    # the worker takes them positionally.
    $invokeParams['ArgumentList'] = @([Bool]$SkipSidReference, [Bool]$SkipDismFeatures)

    $remoteErrors = $null
    Invoke-Command @invokeParams | ForEach-Object { & $OnResult $_ }

    return [PSCustomObject]@{
        Errors = @($remoteErrors)
    }
}
#endregion
