#Requires -Version 7.4
<#
.SYNOPSIS
Validates local agent artifacts and optionally verifies deployed versions and invocation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AgentSourceDir,
    [string]$FoundryProjectEndpoint,
    [string]$OutputDir = ".\reports"
)
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")
$results = [Collections.Generic.List[object]]::new()
$failure = $null
try {
    $agents = @(Get-MigrationAgents $AgentSourceDir)
    if ($FoundryProjectEndpoint) {
        $endpoint = Get-MigrationEndpoint $FoundryProjectEndpoint
        & (Join-Path $PSScriptRoot "check-and-setup-dependencies.ps1") -RequireAzure
    }
    foreach ($agent in $agents) {
        $null = Get-MigrationDefinition $agent.Config
        if ($FoundryProjectEndpoint) {
            $receipt = Read-MigrationJson (Join-Path $agent.Directory "deployment.json")
            $hash = (Get-FileHash -LiteralPath (Join-Path $agent.Directory "agent-config.json") -Algorithm SHA256).Hash
            if ($receipt.endpoint -ne $endpoint -or $receipt.configHash -ne $hash -or -not $receipt.version) {
                throw "Deployment receipt does not match $($agent.Name)."
            }
            $null = Invoke-MigrationApi -Endpoint $endpoint -Path "agents/$($agent.Name)/versions/$($receipt.version)"
            $null = Test-MigrationAgent $endpoint $agent.Name ([string]$receipt.version)
        }
        $results.Add(@{ name = $agent.Name; status = "passed" })
    }
} catch {
    $failure = $_
    $results.Add(@{ name = "validation"; status = "failed"; error = $_.Exception.Message })
}
$mode = if ($FoundryProjectEndpoint) { "online" } else { "offline" }
$report = @{ mode = $mode; passed = ($null -eq $failure); agents = @($results.ToArray()) }
Write-MigrationJson $report (Join-Path $OutputDir "validation-report.json")
@"
# Migration validation

Mode: $mode
Passed: $($report.passed)

$($results | ForEach-Object { "- $($_.name): $($_.status) $($_.error)" } | Out-String)

Offline checks do not verify deployment, governance enforcement, performance, or compliance.
Online checks additionally verify recorded agent versions and run a smoke invocation.
"@ | Set-Content -LiteralPath (Join-Path $OutputDir "validation-report.md") -Encoding utf8
if ($failure) { throw $failure }
