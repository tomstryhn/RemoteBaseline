<#PSScriptInfo

.DESCRIPTION Creates the run folder and its collectors folder under OutputPath and proves the path is writable

.VERSION 1.0.0

.GUID 57c3000a-042a-4a9a-9874-9d515fd9aee4

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Initialize-RemoteBaselineRunFolder {

    <#
    .SYNOPSIS
        Creates the run folder and its collectors folder under OutputPath and proves the path is writable.

    .DESCRIPTION
        Creates <OutputPath>\RemoteBaseline-<yyyyMMdd-HHmmss>Z (with _2, _3 on collision) and the
        collectors folder inside it, and throws on any failure, before any collection starts.
        OutputPath itself is created first when missing. Writability is proved by writing and
        removing a small probe file inside the new run folder, not by inspecting permissions, so
        the same check works the same way on any file system. A run folder this call created and
        then could not use is removed again, so a failed call leaves no empty folder behind.

    .PARAMETER OutputPath
        The already-resolved root folder for the run. On Windows PowerShell 5.1 it may be at most
        105 characters, because the collection writes about 150 characters below it and a path
        is limited to 260; a longer one throws before anything is created. PowerShell 7 has no
        such check.

    .NOTES
        FUNCTION: Initialize-RemoteBaselineRunFolder
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.String
    #>

    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    # Path budget, checked before anything is created. Measured on 5.1 without long path support: a file path of 259 characters works and 260 fails. The deepest staging path is secedit-mergedpolicy.stdout.txt (or .scesrv.log) under collectors\RemoteSecEdit-<stamp>Z\<HOST>_<build>_<stamp>Z: 145 characters below the output path for a 15-character host name, 149 with a _2 suffix on both the run folder and the computer folder. 105 + 149 = 254 leaves room for a two-digit suffix. PowerShell 7 handles long paths, so it gets no check. The caller turns the message into 'output path: <message>'; the limit, the message, both help texts and the README change together.
    if ((Test-RemoteBaselineDesktopEdition) -and $OutputPath.Length -gt 105) {
        throw "$($OutputPath.Length) characters; Windows PowerShell 5.1 limits a path to 260 and the collection needs about 150 below the output path, use a path of at most 105 characters"
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false | Out-Null
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
    $runFolder = Resolve-RemoteBaselineUniqueFolder -Path (Join-Path $OutputPath ('RemoteBaseline-' + $stamp + 'Z'))

    try {
        $probePath = Join-Path $runFolder '.write-test'
        [System.IO.File]::WriteAllText($probePath, 'ok')
        Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
        New-Item -Path (Join-Path $runFolder 'collectors') -ItemType Directory -ErrorAction Stop -WhatIf:$false -Confirm:$false | Out-Null
    } catch {
        $failure = $_.Exception.Message
        # Partial state: the run folder exists but is not usable. Removed so the failure leaves nothing; a cleanup failure is ignored on purpose, the original message is the one worth reporting.
        Remove-Item -LiteralPath $runFolder -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
        throw "OutputPath is not writable: $OutputPath. $failure"
    }

    return $runFolder
}
