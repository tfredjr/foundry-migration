#Requires -Version 7.4
<#
.SYNOPSIS
Checks the tools required by the selected migration phases without installing software.
#>
[CmdletBinding()]
param(
    [switch]$RequireAzure,
    [switch]$RequirePython
)

$ErrorActionPreference = "Stop"
if (-not $PSBoundParameters.ContainsKey("RequireAzure") -and -not $PSBoundParameters.ContainsKey("RequirePython")) {
    $RequireAzure = $true
    $RequirePython = $true
}
if ($RequireAzure) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI is required. Install it from https://aka.ms/installazurecli and run az login."
    }
    $null = & az account show --only-show-errors --output none
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI authentication failed. Run az login and select a subscription." }
}
if ($RequirePython) {
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        throw "Python 3.9+ is required for Refactoring. Install Python and add it to PATH."
    }
    & python -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)"
    if ($LASTEXITCODE -ne 0) { throw "Refactoring requires Python 3.9+." }
}
Write-Verbose "Migration prerequisites passed. No software was installed."
