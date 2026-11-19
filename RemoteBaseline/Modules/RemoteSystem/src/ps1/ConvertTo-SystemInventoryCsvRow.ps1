<#PSScriptInfo

.DESCRIPTION Builds the csv row for one row of any of the seven tables

.VERSION 1.0.0

.GUID b3e84d17-5a60-4c2f-9d71-8a0f6e2c4b35

.AUTHOR Tom Stryhn

.COMPANYNAME Tom Stryhn

.COPYRIGHT 2026 (c) Tom Stryhn

.LICENSEURI https://github.com/tomstryhn/RemoteBaseline/blob/main/LICENSE

.PROJECTURI https://github.com/tomstryhn/RemoteBaseline

#>

#region ConvertTo-SystemInventoryCsvRow
function ConvertTo-SystemInventoryCsvRow {

    <#
    .SYNOPSIS
        Builds the csv row for one row of any of the seven tables.

    .DESCRIPTION
        Produces one flat row in the column order the caller names, by looping over the column
        list and reading each column from the row object. A value that is a collection (an
        array column such as IPAddress or OperationalStatus) becomes its elements joined with a
        vertical bar, so an array of one element and a plain string give the same cell, and an
        empty array gives an empty string. Whitespace runs in text cells collapse to one space
        so a row stays on one line. A null value, and a property the row object lacks, stays
        null (an empty csv cell). Booleans and numbers keep their type.

    .PARAMETER Row
        One row object of a table, live or after a remoting hop.

    .PARAMETER Column
        The columns of the table in file order.

    .NOTES
        FUNCTION: ConvertTo-SystemInventoryCsvRow
        AUTHOR:   Tom Stryhn
        GITHUB:   https://github.com/tomstryhn/

    .INPUTS
        None. Does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject
    #>

    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [PSObject]$Row,

        [Parameter(Mandatory = $true)]
        [String[]]$Column
    )

    # The property collection of the row is taken once per row, not once per column.
    $rowProperties = $null
    if ($null -ne $Row) {
        $rowProperties = $Row.PSObject.Properties
    }

    $csvRow = [ordered]@{}
    foreach ($name in $Column) {
        # Read straight from PSObject.Properties, not through Get-SystemInventorySafeProperty: a function
        # that returns an empty array delivers nothing, so an empty array would arrive as $null and lose its
        # empty cell.
        $value = $null
        if ($null -ne $rowProperties) {
            $property = $rowProperties[$name]
            if ($null -ne $property) {
                $value = $property.Value
            }
        }

        if ($null -eq $value) {
            $csvRow[$name] = $null
        }
        elseif ($value -is [String]) {
            # The common case first: a text cell, whitespace runs collapsed.
            $csvRow[$name] = $value -replace '\s+', ' '
        }
        elseif ($value -is [System.Collections.IEnumerable]) {
            # A generic list, not an array grown with +=.
            $items = [System.Collections.Generic.List[String]]::new()
            foreach ($item in $value) {
                [Void]$items.Add("$item")
            }
            $csvRow[$name] = ($items -join '|') -replace '\s+', ' '
        }
        else {
            $csvRow[$name] = $value
        }
    }

    return [PSCustomObject]$csvRow
}
#endregion
