#!/usr/bin/env pwsh
<#
.SYNOPSIS
Comprehensive discovery script for OpenAI and Foundry resources.
Audits all AI resources in subscription and generates migration planning data.

.DESCRIPTION
This script discovers:
- OpenAI Studio deployments and models
- Foundry projects and agents
- Classic AI Services resources
- Model versions and deployment locations
- Current configurations and settings

Generates audit reports in both human-readable and machine-readable formats.

.PARAMETER SubscriptionId
The Azure subscription ID to audit (defaults to current subscription).

.PARAMETER OutputDir
Directory where audit reports are saved (defaults to ./audit).

.EXAMPLE
./discover-resources.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -OutputDir "./audit"

.NOTES
Non-destructive. Does not modify any resources.
#>

#Requires -Version 7.4
[CmdletBinding()]
param(
    [string]$SubscriptionId = $null,
    [string]$OutputDir = ".\audit"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Invoke-AzureQuery {
    param([string]$Query, [string]$Description)
    
    Log "Querying: $Description..." -Level "QUERY"
    
    $skipToken = $null
    do {
        $arguments = @("graph", "query", "-q", $Query, "--subscriptions", $SubscriptionId, "--first", "1000")
        if ($skipToken) { $arguments += @("--skip-token", $skipToken) }
        $result = Invoke-MigrationAz $arguments
        foreach ($resource in $result.data) { [pscustomobject]$resource }
        $skipToken = $result.skip_token
    } while ($skipToken)
}

# Initialize
Log "Starting resource discovery..." -Level "INFO"
Write-Host ""

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Set subscription
if ($SubscriptionId) {
    Log "Setting subscription: $SubscriptionId" -Level "INFO"
    $null = Invoke-MigrationAz @("account", "set", "--subscription", $SubscriptionId)
} else {
    $SubscriptionId = (Invoke-MigrationAz @("account", "show")).id
    Log "Using current subscription: $SubscriptionId" -Level "INFO"
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportFile = Join-Path $OutputDir "resource-audit-report_$timestamp.md"
$jsonFile = Join-Path $OutputDir "resources_$timestamp.json"

# Discover resources
Log "Discovering Azure OpenAI resources..." -Level "INFO"
$openaiResources = @(Invoke-AzureQuery `
    "Resources | where type =~ 'microsoft.cognitiveservices/accounts' and kind =~ 'OpenAI'" `
    "OpenAI Accounts")

Log "Discovering Foundry projects..." -Level "INFO"
$foundryProjects = @(Invoke-AzureQuery `
    "Resources | where type =~ 'microsoft.cognitiveservices/accounts/projects' or (type =~ 'microsoft.machinelearningservices/workspaces' and kind =~ 'project')" `
    "Foundry Projects")

Log "Discovering AI Services resources..." -Level "INFO"
$aiServices = @(Invoke-AzureQuery `
    "Resources | where type == 'microsoft.cognitiveservices/accounts'" `
    "AI Services Accounts")

Log "Discovering Container Registries..." -Level "INFO"
$acrs = @(Invoke-AzureQuery `
    "Resources | where type == 'microsoft.containerregistry/registries'" `
    "Container Registries")

Log "Discovering Application Insights..." -Level "INFO"
$appInsights = @(Invoke-AzureQuery `
    "Resources | where type == 'microsoft.insights/components'" `
    "Application Insights")

Log "Discovering Key Vaults..." -Level "INFO"
$keyVaults = @(Invoke-AzureQuery `
    "Resources | where type == 'microsoft.keyvault/vaults'" `
    "Key Vaults")

$models = @(
    foreach ($account in $aiServices) {
        $deployments = Invoke-MigrationAz @("cognitiveservices", "account", "deployment", "list",
            "--name", $account.name, "--resource-group", $account.resourceGroup, "--subscription", $SubscriptionId)
        foreach ($deployment in $deployments) {
            @{
                accountId = $account.id
                deploymentName = $deployment.name
                model = $deployment.properties.model
                location = $account.location
            }
        }
    }
)

# Build audit object
$audit = @{
    timestamp = Get-Date -AsUTC
    subscriptionId = $SubscriptionId
    models = $models
    agents = @()
    resourceCounts = @{
        openaiAccounts = $openaiResources.Count
        foundryProjects = $foundryProjects.Count
        aiServices = $aiServices.Count
        containerRegistries = $acrs.Count
        applicationInsights = $appInsights.Count
        keyVaults = $keyVaults.Count
    }
    resources = @{
        openai = $openaiResources
        foundry = $foundryProjects
        aiServices = $aiServices
        acrs = $acrs
        appInsights = $appInsights
        keyVaults = $keyVaults
    }
}

# Generate markdown report
$report = @"
# Azure AI Resources Audit Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Subscription:** $SubscriptionId
**Report Version:** 1.0

## Executive Summary

This audit discovered the following AI resources in your Azure subscription:

| Resource Type | Count | Status |
|---------------|-------|--------|
| OpenAI Accounts | $($audit.resourceCounts.openaiAccounts) | $($audit.resourceCounts.openaiAccounts -gt 0 ? '✓ Present' : '⚠ None found') |
| Foundry Projects | $($audit.resourceCounts.foundryProjects) | $($audit.resourceCounts.foundryProjects -gt 0 ? '✓ Present' : '⚠ None found') |
| AI Services | $($audit.resourceCounts.aiServices) | ✓ Present |
| Container Registries | $($audit.resourceCounts.containerRegistries) | $($audit.resourceCounts.containerRegistries -gt 0 ? '✓ Present' : '⚠ None found') |
| Application Insights | $($audit.resourceCounts.applicationInsights) | $($audit.resourceCounts.applicationInsights -gt 0 ? '✓ Present' : '⚠ None found') |
| Key Vaults | $($audit.resourceCounts.keyVaults) | $($audit.resourceCounts.keyVaults -gt 0 ? '✓ Present' : '⚠ None found') |

## Migration Readiness

### Current State
- **OpenAI Resources Found:** $($audit.resourceCounts.openaiAccounts)
- **Foundry Projects Found:** $($audit.resourceCounts.foundryProjects)
- **Supporting Infrastructure:** Inventory only; readiness requires separate review

### Recommended Next Steps

1. **Phase 1: Planning** - Review this audit report and identify priority resources
2. **Phase 2: Foundry Setup** - Create target Foundry project(s) if needed
3. **Phase 3: Refactoring** - Transform OpenAI agents to Foundry agents
4. **Phase 4: Deployment** - Deploy to Foundry
5. **Phase 5: Governance** - Apply guardrails and RBAC
6. **Phase 6: Testing** - Validate end-to-end workflows
7. **Phase 7: Cutover** - Migrate traffic to Foundry

## Detailed Inventory

### OpenAI Accounts ($($audit.resourceCounts.openaiAccounts))

$(if ($openaiResources.Count -gt 0) {
    foreach ($resource in $openaiResources) {
        @"
- **Name:** $($resource.name)
  - **Resource Group:** $($resource.resourceGroup)
  - **Location:** $($resource.location)
  - **SKU:** $($resource.sku)
  - **Created:** $($resource.createdTime -replace 'T', ' ')
  - **Tags:** $(($resource.tags | ConvertTo-Json -Compress) -replace '"', '')

"@
    }
} else {
    "No OpenAI accounts found in this subscription.`n"
})

### Foundry Projects ($($audit.resourceCounts.foundryProjects))

$(if ($foundryProjects.Count -gt 0) {
    foreach ($project in $foundryProjects) {
        @"
- **Name:** $($project.name)
  - **Resource Group:** $($project.resourceGroup)
  - **Location:** $($project.location)
  - **Type:** $($project.kind)
  - **Created:** $($project.createdTime -replace 'T', ' ')

"@
    }
} else {
    "No Foundry projects found. You will need to create one for migration.`n"
})

### Container Registries ($($audit.resourceCounts.containerRegistries))

$(if ($acrs.Count -gt 0) {
    foreach ($acr in $acrs) {
        @"
- **Name:** $($acr.name)
  - **Resource Group:** $($acr.resourceGroup)
  - **Location:** $($acr.location)
  - **SKU:** $($acr.sku)
  - **Login Server:** $($acr.properties.loginServer)

"@
    }
} else {
    "No container registries found. One will be created if deploying hosted agents.`n"
})

### Application Insights ($($audit.resourceCounts.applicationInsights))

$(if ($appInsights.Count -gt 0) {
    foreach ($ai in $appInsights) {
        @"
- **Name:** $($ai.name)
  - **Resource Group:** $($ai.resourceGroup)
  - **Location:** $($ai.location)
  - **Application Type:** $($ai.properties.applicationType)

"@
    }
} else {
    "No Application Insights instances found. Consider enabling for audit logging.`n"
})

## Migration Planning Notes

### What Will Change
- **Agent Management:** Shift from OpenAI Studio to Foundry agents
- **Model Deployment:** Move to Foundry's managed model deployments
- **Tool Integration:** Leverage Foundry's native toolbox and skills
- **Governance:** Implement Foundry's RBAC, guardrails, and audit logging
- **Monitoring:** Use Foundry's native telemetry instead of custom solutions

### What Will Stay the Same
- **Azure Subscription:** No change required
- **Resource Groups:** Can keep existing naming
- **Networking:** Can maintain existing VNet/firewall configuration
- **Compliance:** Foundry maintains same compliance certifications

### Estimated Effort

Based on discovered resources:
- **Discovery & Planning:** 2-4 hours
- **Foundry Setup:** 2-4 hours (if creating new project)
- **Agent Refactoring:** 2 hours per agent
- **Testing & Validation:** 4-8 hours
- **Cutover & Cleanup:** 2-4 weeks (gradual traffic shift)

**Total Estimated Effort:** 12-30 hours + cutover period

## Risk Assessment

### Discovery Scope
- This audit is read-only; no resources were modified.
- Agent prompts and application code are not included in resource inventory.
- Logging, RBAC, networking, capacity and compliance have not been validated.

### Medium Risk
- ⚠ Model version compatibility testing needed
- ⚠ Agent prompt optimization required
- ⚠ Custom tooling may need refactoring

### Mitigation Strategies
1. Deploy to staging environment first
2. Run parallel OpenAI + Foundry during transition
3. Implement comprehensive monitoring
4. Establish rollback procedures

## Next Steps

1. **Review this audit** - Validate discovered resources
2. **Generate migration plan** - Run generate-migration-plan.ps1
3. **Create Foundry project** - Use create-foundry-project.ps1 or use existing
4. **Apply governance template** - Review governance/default-governance.json
5. **Begin Phase 1 refactoring** - Start with low-risk agents

---

For detailed migration instructions, see the main README.md file.

**Report Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

# Save reports
$report | Out-File -FilePath $reportFile -Encoding UTF8
Write-MigrationJson $audit $jsonFile
Write-MigrationJson $models (Join-Path $OutputDir "models-deployed_$timestamp.json")

Log "Audit complete!" -Level "SUCCESS"
Write-Host ""
Log "Reports generated:" -Level "INFO"
Log "  - Markdown report: $reportFile" -Level "INFO"
Log "  - JSON data: $jsonFile" -Level "INFO"
