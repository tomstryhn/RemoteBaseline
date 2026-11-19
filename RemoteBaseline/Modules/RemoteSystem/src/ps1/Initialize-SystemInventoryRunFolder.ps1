<#PSScriptInfo

.DESCRIPTION Creates the run folder under OutputPath and proves it is writable

.VERSION 1.0.0

.GUID 38f288e8-0027-4589-a085-36050fe2de94

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region Initialize-SystemInventoryRunFolder
function Initialize-SystemInventoryRunFolder {

    <#
    .SYNOPSIS
        Creates the run folder under OutputPath and proves it is writable.

    .DESCRIPTION
        Creates <OutputPath>\RemoteSystem-<yyyyMMdd-HHmmss>Z and throws on any failure, before
        any collection starts. OutputPath itself is created first when missing. Writability is
        proved by writing and removing a small probe file inside the new run folder, not by
        inspecting permissions, so the same check works the same way on any file system. A run
        folder this call created and then could not use is removed again. An OutputPath the call
        created stays.

    .PARAMETER OutputPath
        The already-resolved root folder for the run.

    .NOTES
        FUNCTION: Initialize-SystemInventoryRunFolder
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String
    #>

    param(
        [Parameter(Mandatory = $true)]
        [String]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
    $runFolder = Resolve-SystemInventoryUniqueFolder -Path (Join-Path $OutputPath ('RemoteSystem-' + $stamp + 'Z'))

    $probePath = Join-Path $runFolder '.write-test'
    try {
        [System.IO.File]::WriteAllText($probePath, 'ok')
        Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
    }
    catch {
        $failure = $_.Exception.Message
        # The run folder exists but is not usable, so it is removed and a failed call leaves nothing behind.
        # A failure to remove it is ignored, the write error is the one worth reporting.
        Remove-Item -LiteralPath $runFolder -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
        throw "OutputPath is not writable: $OutputPath. $failure"
    }

    return $runFolder
}
#endregion
