#Requires -Version 7.4
<#
.SYNOPSIS
Generates a resource map and rollout plan from a discovery audit.
.DESCRIPTION
Resource inventory does not include application prompts or tools. Supply exported
agent JSON configurations to refactor-agents.ps1, or include them in audit.agents.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AuditFile,
    [string]$OutputDir = ".\migration-plan"
)
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")

$audit = Read-MigrationJson $AuditFile
if (-not $audit.subscriptionId -or -not $audit.resources) {
    throw "Audit must include subscriptionId and resources."
}
$resources = @(
    foreach ($category in @("openai", "foundry", "aiServices")) {
        foreach ($resource in @($audit.resources[$category])) {
            if ($null -ne $resource) {
                @{ id = $resource.id; name = $resource.name; location = $resource.location; category = $category }
            }
        }
    }
)
$agents = @($audit.agents | Where-Object { $null -ne $_ })
$plan = @{
    schemaVersion = "1.0"
    subscriptionId = $audit.subscriptionId
    auditFile = (Resolve-Path -LiteralPath $AuditFile).Path
    resources = $resources
    agents = $agents
}
Write-MigrationJson $plan (Join-Path $OutputDir "resource-migration-map.json")
Write-MigrationJson @{
    phases = @("Refactoring", "Deployment", "Governance", "Validation")
    agentNames = @($agents | ForEach-Object { $_.name })
    requiresReview = $true
} (Join-Path $OutputDir "phased-rollout.json")
@"
# Migration strategy

Subscription: $($audit.subscriptionId)
Inventory entries: $($resources.Count)
Exported agent configurations: $($agents.Count)

1. Review resource-migration-map.json. Resource inventory is not agent source code.
2. Supply exported JSON agent configurations using -AgentConfigDir if agents is empty.
3. Refactor and validate locally; review deployment names and port tool runtimes.
4. Create or select a Foundry project and deploy the referenced models separately.
5. Deploy prompt agents, apply a reviewed governance ARM template, then validate.

No resources, traffic, model deployments, or application code are changed by planning.
"@ | Set-Content -LiteralPath (Join-Path $OutputDir "MIGRATION_STRATEGY.md") -Encoding utf8
