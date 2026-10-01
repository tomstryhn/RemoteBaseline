<#PSScriptInfo

.DESCRIPTION Tests that a path is a direct child of a folder, comparing full resolved paths

.VERSION 1.0.0

.GUID c41d7e08-93a2-4b6f-8e15-7f0a3d62b9c4

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

function Test-RemoteBaselineChildPath {

    <#
    .SYNOPSIS
        Tests that a path is a direct child of a folder, comparing full resolved paths.

    .DESCRIPTION
        The containment check in front of every rename and move the module does. A collector's
        result rows name folders, and the module renames and moves what they name, so the module
        first proves that the folder sits where the collector was told to write: the collector's
        run folder directly under the staging folder, and a computer folder directly under that
        run folder. Both sides are resolved to full paths first (so a '..' segment cannot slip
        out) and compared ordinal, ignoring case, with trailing separators removed. A path that
        cannot be resolved is not a child. Never throws.

    .PARAMETER Path
        The folder whose parent is checked.

    .PARAMETER Folder
        The folder the parent of Path must be.

    .NOTES
        FUNCTION: Test-RemoteBaselineChildPath
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Boolean
    #>

    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Folder
    )

    Set-StrictMode -Version Latest

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Folder)) { return $false }
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
        $parent = [System.IO.Path]::GetDirectoryName($fullPath)
        if ([string]::IsNullOrEmpty($parent)) { return $false }
        $fullFolder = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
        return [string]::Equals($parent.TrimEnd('\', '/'), $fullFolder, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}
