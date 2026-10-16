#Requires -Version 7.4
<#
.SYNOPSIS
Transforms exported JSON agent configurations into reviewable Foundry configurations.
.PARAMETER ValidateOnly
Validates source configurations without writing output. DryRun orchestration still
writes local artifacts so subsequent offline validation can inspect them.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MigrationPlanDir,
    [string]$AgentConfigDir,
    [string]$OutputDir = ".\refactored-agents",
    [string]$FoundryProjectEndpoint,
    [bool]$ValidateOnly = $false
)
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")
& (Join-Path $PSScriptRoot "check-and-setup-dependencies.ps1") -RequirePython
$plan = Read-MigrationJson (Join-Path $MigrationPlanDir "resource-migration-map.json")
$sources = @($plan.agents | Where-Object { $null -ne $_ })
if ($AgentConfigDir) {
    if (-not (Test-Path -LiteralPath $AgentConfigDir -PathType Container)) {
        throw "Agent configuration directory not found: $AgentConfigDir"
    }
    $sources += @(Get-ChildItem -LiteralPath $AgentConfigDir -File -Filter "*.json" |
        ForEach-Object { Read-MigrationJson $_.FullName })
}
if ($sources.Count -eq 0) {
    throw "No exported agents found. Supply -AgentConfigDir containing JSON configurations; Azure resource inventory alone cannot reconstruct agents."
}
$names = @{}
foreach ($source in $sources) {
    if (-not $source.name -or $source.name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$' -or
        -not $source.model -or -not ($source.system_prompt -or $source.instructions)) {
        throw "Each exported agent requires a safe name, model (target deployment name), and system_prompt or instructions."
    }
    if ($names.ContainsKey($source.name)) { throw "Duplicate agent name: $($source.name)" }
    $names[$source.name] = $true
    if (-not $ValidateOnly -and (Test-Path -LiteralPath (Join-Path $OutputDir $source.name))) {
        throw "Agent output already exists: $($source.name). Use a fresh OutputDir to avoid retaining stale deployment receipts."
    }
}
$stagingDir = Join-Path ([IO.Path]::GetTempPath()) "foundry-refactoring-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $stagingDir
try {
    foreach ($source in $sources) {
        $jsonFile = Join-Path $stagingDir "source.json"
        Write-MigrationJson $source $jsonFile
        $target = Join-Path $stagingDir "agents\$($source.name)\agent-config.json"
        & python (Join-Path $PSScriptRoot "helpers\agent-transformer.py") $jsonFile $target
        if ($LASTEXITCODE -ne 0) { throw "Agent transformation failed for $($source.name)." }
    }
    $null = @(Get-MigrationAgents (Join-Path $stagingDir "agents"))
    if (-not $ValidateOnly) {
        $null = New-Item -ItemType Directory -Path $OutputDir -Force
        foreach ($source in $sources) {
            Move-Item -LiteralPath (Join-Path $stagingDir "agents\$($source.name)") -Destination $OutputDir
        }
    }
} finally {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
