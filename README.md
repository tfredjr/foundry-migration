# OpenAI Studio to Azure Foundry Migration Framework

A comprehensive, hands-off migration toolkit to refactor and restructure AI resources from OpenAI Studio to Azure Foundry with modern governance capabilities.

## Overview

This framework automates the discovery, assessment, and migration of OpenAI Studio resources to Azure Foundry. It handles:

- **Resource Discovery** — Catalog all OpenAI and classic Foundry resources
- **Model Inventory** — Map models (gpt-4o, latest versions, etc.) across deployments
- **Agent Refactoring** — Transform OpenAI Studio workflows into Foundry agents
- **Governance Setup** — Apply guardrails, skills, and RBAC
- **Migration Planning** — Generate detailed reports and migration plans
- **Hands-Off Execution** — Run scripts with minimal manual intervention

## Quick Start

### Prerequisites

- **Azure CLI** (`az`) — [Install](https://aka.ms/installazurecli)
- **Azure Developer CLI** (`azd`) — [Install](https://aka.ms/azure-dev/install)
- **Python 3.9+** — For migration scripts
- **jq** (Linux/macOS) or PowerShell (Windows) — For JSON processing
- **Azure Permissions** — Owner or Contributor role on the subscription

### 1. Run the Dependency Check (Required)

```bash
# macOS / Linux
./scripts/check-and-setup-dependencies.sh

# Windows (PowerShell)
./scripts/check-and-setup-dependencies.ps1
```

This validates all prerequisites and installs missing dependencies.

### 2. Run the Discovery Phase

```bash
# Discover and audit all OpenAI and Foundry resources
./scripts/discover-resources.ps1 -SubscriptionId "<subscription-id>" -OutputDir "./audit"

# Review the generated audit report
./audit/resource-audit-report.md
```

This creates:
- `resource-audit-report.md` — Human-readable inventory
- `resources.json` — Machine-readable resource catalog
- `models-deployed.json` — Model version mapping
- `migration-plan.json` — Recommended refactoring steps

### 3. Review the Migration Plan

```bash
# Generate a detailed migration plan
./scripts/generate-migration-plan.ps1 -AuditFile "./audit/resources.json" -OutputDir "./migration-plan"
```

Review `./migration-plan/MIGRATION_STRATEGY.md` for step-by-step guidance.

### 4. Create the Foundry Project (or use existing)

```bash
# Option A: Create a new Foundry project
./scripts/create-foundry-project.ps1 -ProjectName "energy-transfer-ai" -Location "eastus" -EnableHostedAgents $true

# Option B: Use an existing Foundry project
# Set environment variables:
export AZURE_AI_PROJECT_ENDPOINT="<your-foundry-project-endpoint>"
export AZURE_AI_PROJECT_NAME="<project-name>"
export AZURE_RESOURCE_GROUP="<resource-group>"
export AZURE_AI_ACCOUNT_NAME="<foundry-account-name>"
```

### 5. Refactor and Deploy Agents

```bash
# Transform OpenAI Studio resources into Foundry agents
./scripts/refactor-agents.ps1 -MigrationPlanDir "./migration-plan" -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT

# Deploy refactored agents
./scripts/deploy-agents.ps1 -AgentSourceDir "./refactored-agents" -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT
```

### 6. Apply Governance and Guardrails

```bash
# Configure RBAC, guardrails, and skills
./scripts/apply-governance.ps1 -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT -GovernanceConfigFile "./governance/default-governance.json"
```

### 7. Validate and Test

```bash
# Run validation tests
./scripts/validate-migration.ps1 -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT -AgentSourceDir "./refactored-agents"

# Review validation report
./reports/validation-report.md
```

## Directory Structure

```
foundry-migration/
├── README.md (this file)
├── scripts/
│   ├── check-and-setup-dependencies.ps1     # Verify & install deps
│   ├── discover-resources.ps1               # Audit OpenAI + Foundry
│   ├── generate-migration-plan.ps1          # Create migration plan
│   ├── create-foundry-project.ps1           # Setup Foundry project
│   ├── refactor-agents.ps1                  # Transform agents
│   ├── deploy-agents.ps1                    # Deploy to Foundry
│   ├── apply-governance.ps1                 # Setup guardrails/RBAC
│   ├── validate-migration.ps1               # Verify migration
│   └── helpers/
│       ├── openai-resource-scanner.py       # OpenAI audit
│       ├── foundry-resource-scanner.py      # Foundry audit
│       ├── agent-transformer.py             # Agent refactoring
│       ├── model-mapper.py                  # Model version tracking
│       └── common.py                        # Shared utilities
├── templates/
│   ├── agent-template.yaml                  # Foundry agent scaffold
│   ├── azure.yaml                           # azd project template
│   ├── agent-spec.json                      # Agent configuration schema
│   ├── guardrail-config.json                # Guardrails template
│   ├── toolbox-config.json                  # Toolbox definition
│   └── evaluation-suite.yaml                # Eval setup template
├── governance/
│   ├── default-governance.json              # Default guardrails + RBAC
│   ├── rbac-roles.json                      # Role definitions
│   ├── guardrail-policies.json              # Policy guardrails
│   └── audit-logging.json                   # Audit + monitoring setup
├── examples/
│   ├── migrated-agent-gpt4o/                # Example: gpt-4o agent
│   ├── migrated-agent-latest/               # Example: latest model
│   └── multi-model-agent/                   # Example: model selection
├── audit/ (generated)
│   ├── resource-audit-report.md
│   ├── resources.json
│   ├── models-deployed.json
│   └── migration-plan.json
├── migration-plan/ (generated)
│   ├── MIGRATION_STRATEGY.md
│   ├── resource-migration-map.json
│   └── phased-rollout.json
├── refactored-agents/ (generated)
│   ├── agent-1/
│   ├── agent-2/
│   └── ...
└── reports/ (generated)
    ├── validation-report.md
    ├── deployment-status.json
    └── governance-compliance.md
```

## Phase-Based Migration Strategy

### Phase 1: Discovery & Planning (Non-destructive)
- Audit all OpenAI and Foundry resources
- Catalog model deployments and versions
- Create detailed migration plan
- **Duration:** 1-2 hours | **Risk:** None

### Phase 2: Setup & Preparation
- Create/validate Foundry project
- Set up governance baseline
- Prepare agent templates
- **Duration:** 2-4 hours | **Risk:** Low

### Phase 3: Refactoring (Offline)
- Transform agents offline
- Validate refactored code
- Test locally
- **Duration:** 4-8 hours | **Risk:** Low (no production changes)

### Phase 4: Deployment & Testing
- Deploy agents to Foundry
- Run smoke tests
- Validate governance compliance
- **Duration:** 2-4 hours | **Risk:** Medium (staging/canary deployment recommended)

### Phase 5: Cutover & Cleanup
- Monitor new agents in production
- Gradual traffic shift (if applicable)
- Deprecate OpenAI Studio resources
- Archive audit trail
- **Duration:** 2-4 weeks | **Risk:** Depends on cutover strategy

## Key Features

### 1. Automated Discovery
- **OpenAI Studio Auditing** — Lists all models, completions, fine-tunings
- **Foundry Resource Inventory** — Catalogs projects, agents, deployments
- **Model Version Tracking** — Maps gpt-4o, latest, and custom models
- **Deployment Location Mapping** — Identifies where models are running

### 2. Intelligent Refactoring
- **Agent Transformation** — Converts OpenAI workflows to Foundry agents
- **Model Abstraction** — Supports model selection and fallback logic
- **Tool Migration** — Maps OpenAI function calls to Foundry tools
- **Prompt Optimization** — Validates prompt quality post-refactor

### 3. Governance & Compliance
- **RBAC Automation** — Sets up role assignments
- **Guardrails** — Applies content filters, jailbreak detection
- **Audit Logging** — Enables comprehensive telemetry
- **Compliance Templates** — SOC 2, HIPAA-ready configurations

### 4. Hands-Off Execution
- **One-Command Workflow** — Run entire phases with single scripts
- **Idempotent Operations** — Safe to re-run without side effects
- **Progress Tracking** — Detailed logs and status reports
- **Rollback Capability** — Preserve original resources during migration

## Detailed Workflow

### Step 1: Prerequisites & Environment Setup

```powershell
# Set your subscription and Azure credentials
az login
az account set --subscription "<subscription-id>"

# Verify you have required permissions
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" `
  --include-groups `
  --query "[?roleDefinitionName == 'Owner' || roleDefinitionName == 'Contributor']" `
  -o table
```

### Step 2: Discover Resources

```powershell
# Run comprehensive audit
./scripts/discover-resources.ps1 `
  -SubscriptionId "$(az account show --query id -o tsv)" `
  -OutputDir "./audit" `
  -Verbose

# Outputs generated:
# - audit/resource-audit-report.md     # Human-readable summary
# - audit/resources.json               # Machine-readable catalog
# - audit/models-deployed.json         # Model version inventory
# - audit/migration-plan.json          # Initial recommendations
```

### Step 3: Analyze and Plan

```powershell
# Generate detailed migration strategy
./scripts/generate-migration-plan.ps1 `
  -AuditFile "./audit/resources.json" `
  -OutputDir "./migration-plan" `
  -Verbose

# Review the strategy
notepad ./migration-plan/MIGRATION_STRATEGY.md

# Key sections to review:
# - Resource Mapping: How old resources map to Foundry
# - Model Strategy: Which models to deploy where
# - Phasing: Recommended rollout sequence
# - Risks & Mitigations: Identified issues and solutions
```

### Step 4: Create Foundry Project (if needed)

```powershell
# Option A: Create new project
./scripts/create-foundry-project.ps1 `
  -ProjectName "energy-transfer-production" `
  -Location "eastus" `
  -EnableHostedAgents $true `
  -Verbose

# Option B: Use existing Foundry project
# Set environment variables for your project:
$env:AZURE_AI_PROJECT_ENDPOINT = "https://<region>.api.cognitive.microsoft.com/"
$env:AZURE_AI_PROJECT_NAME = "your-project-name"
$env:AZURE_RESOURCE_GROUP = "rg-your-project"
$env:AZURE_AI_ACCOUNT_NAME = "your-account"
```

### Step 5: Refactor Agents

```powershell
# Transform OpenAI Studio agents to Foundry agents
./scripts/refactor-agents.ps1 `
  -MigrationPlanDir "./migration-plan" `
  -OutputDir "./refactored-agents" `
  -ValidateOnly $false `  # Set $true to validate without transforming
  -Verbose

# Script generates:
# - refactored-agents/agent-1/
#   - agent.yaml                # Agent configuration
#   - azure.yaml                # Deployment config
#   - src/main.py              # Agent code
#   - requirements.txt          # Dependencies
#   - README.md                # Agent documentation
# - refactored-agents/agent-2/
#   - ...
```

### Step 6: Deploy to Foundry

```powershell
# Deploy refactored agents
./scripts/deploy-agents.ps1 `
  -AgentSourceDir "./refactored-agents" `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT `
  -SmokeTest $true `         # Run validation tests
  -Verbose

# Outputs:
# - Deployed agent URLs
# - Service endpoints
# - Deployment logs
```

### Step 7: Apply Governance

```powershell
# Set up guardrails, RBAC, and audit logging
./scripts/apply-governance.ps1 `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT `
  -GovernanceConfigFile "./governance/default-governance.json" `
  -Verbose

# Configures:
# - Content filters (jailbreak detection, PII detection)
# - RBAC: Agent Developer, Agent Operator, Auditor roles
# - Audit logging to Application Insights
# - Compliance checkpoints
```

### Step 8: Validate & Report

```powershell
# Run comprehensive validation
./scripts/validate-migration.ps1 `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT `
  -AgentSourceDir "./refactored-agents" `
  -Verbose

# Review validation report
notepad ./reports/validation-report.md

# Checks include:
# - All agents deployed successfully
# - Governance policies applied
# - Model deployments verified
# - Audit logging enabled
# - Performance baselines established
```

## Migration Checklist

- [ ] **Prerequisites**
  - [ ] Azure CLI installed and logged in
  - [ ] Azure Developer CLI installed
  - [ ] Python 3.9+ available
  - [ ] Adequate Azure permissions (Owner/Contributor)
  - [ ] Subscription selected

- [ ] **Phase 1: Discovery**
  - [ ] Run dependency check script
  - [ ] Execute resource discovery
  - [ ] Review audit report
  - [ ] Validate resource counts
  - [ ] Identify any blocked resources

- [ ] **Phase 2: Planning**
  - [ ] Generate migration plan
  - [ ] Review migration strategy
  - [ ] Identify model placement
  - [ ] Plan agent grouping
  - [ ] Document custom requirements

- [ ] **Phase 3: Setup**
  - [ ] Create/validate Foundry project
  - [ ] Configure subscriptions
  - [ ] Set up service principals
  - [ ] Prepare governance policies
  - [ ] Configure audit logging

- [ ] **Phase 4: Refactoring**
  - [ ] Review agent transformation rules
  - [ ] Refactor agents (offline)
  - [ ] Test refactored code locally
  - [ ] Validate model references
  - [ ] Document any custom changes

- [ ] **Phase 5: Deployment**
  - [ ] Deploy agents to staging
  - [ ] Run smoke tests
  - [ ] Validate agent invocation
  - [ ] Check model deployments
  - [ ] Review deployment logs

- [ ] **Phase 6: Governance**
  - [ ] Apply guardrails
  - [ ] Configure RBAC
  - [ ] Enable audit logging
  - [ ] Validate compliance
  - [ ] Test access controls

- [ ] **Phase 7: Validation**
  - [ ] Run validation suite
  - [ ] Review validation report
  - [ ] Test end-to-end workflows
  - [ ] Validate governance compliance
  - [ ] Establish performance baselines

- [ ] **Phase 8: Cutover**
  - [ ] Plan traffic migration
  - [ ] Implement monitoring
  - [ ] Set up alerts
  - [ ] Deprecate OpenAI resources
  - [ ] Archive audit trail

## Troubleshooting

### Common Issues

#### Issue: "Resource not found" errors during discovery
**Solution:**
- Verify subscription selection: `az account show`
- Check permissions: `az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)"`
- Ensure OpenAI resources exist in the selected subscription

#### Issue: Foundry project endpoint not accessible
**Solution:**
- Verify endpoint URL format (should be `https://<region>.api.cognitive.microsoft.com/`)
- Check network connectivity: `curl -I $env:AZURE_AI_PROJECT_ENDPOINT`
- Verify authentication: `az account show`
- If VNet-isolated, ensure you're inside the VNet or using a private endpoint

#### Issue: Model deployment fails with quota errors
**Solution:**
- Check quota: `az cognitiveservices account show --name <account> --resource-group <rg>`
- Request quota increase if needed
- Consider deploying to different regions
- Review `./reports/deployment-status.json` for detailed errors

#### Issue: Agent deployment timeout
**Solution:**
- Check agent logs: `./scripts/helpers/check-agent-logs.ps1 -AgentName "<name>"`
- Verify Azure Container Registry has space
- Try deploying smaller agents first
- Review `./reports/deployment-status.json` for details

### Getting Help

1. **Check logs** — Review script logs in `./logs/` directory
2. **Review reports** — Examine `./audit/` and `./reports/` for issues
3. **Validate environment** — Run dependency check script
4. **Dry-run mode** — Use `-ValidateOnly $true` flag for safe testing

## Environment Variables

Key environment variables used throughout the migration:

```powershell
# Azure subscription
$env:AZURE_SUBSCRIPTION_ID = "<subscription-id>"

# Foundry project (required for deployment phases)
$env:AZURE_AI_PROJECT_ENDPOINT = "https://<region>.api.cognitive.microsoft.com/"
$env:AZURE_AI_PROJECT_NAME = "<project-name>"
$env:AZURE_RESOURCE_GROUP = "<resource-group>"
$env:AZURE_AI_ACCOUNT_NAME = "<account-name>"

# Optional: Service principal auth (for CI/CD)
$env:AZURE_CLIENT_ID = "<client-id>"
$env:AZURE_CLIENT_SECRET = "<client-secret>"
$env:AZURE_TENANT_ID = "<tenant-id>"

# Optional: Logging and debugging
$env:MIGRATION_LOG_LEVEL = "INFO"  # DEBUG, INFO, WARN, ERROR
$env:MIGRATION_DRY_RUN = "false"   # Set to 'true' for dry-run mode
```

## Performance Considerations

- **Large Deployments** — For 50+ agents, consider batching deployments
- **Model Deployments** — Deploy high-traffic models to multiple regions for redundancy
- **Quota Planning** — Request quota increases before bulk deployments
- **Parallel Operations** — Scripts support parallel execution (see `-Parallel` flag)

## Security Best Practices

1. **RBAC Setup** — Apply least-privilege access
2. **Secrets Management** — Use Azure Key Vault for sensitive values
3. **Network Isolation** — Consider VNet-isolated Foundry projects
4. **Audit Logging** — Enable comprehensive telemetry
5. **Guardrails** — Apply content filters and jailbreak detection
6. **Monitoring** — Set up alerts for anomalies

## Next Steps After Migration

1. **Monitor Performance** — Track agent latency and error rates
2. **Gather Feedback** — Collect user feedback on refactored agents
3. **Optimize Prompts** — Use Foundry's evaluation tools
4. **Deprecate Old Resources** — Cleanly remove OpenAI Studio resources
5. **Document Lessons** — Update team documentation
6. **Plan Continuous Improvement** — Schedule quarterly reviews

## Additional Resources

- [Azure Foundry Documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Foundry Agents Concepts](https://learn.microsoft.com/azure/ai-foundry/agents/concepts/agents)
- [Deployment Best Practices](https://learn.microsoft.com/azure/ai-foundry/agents/how-to/develop/agents)
- [Governance & Security](https://learn.microsoft.com/azure/ai-foundry/concepts/security)
- [Cost Optimization](https://learn.microsoft.com/azure/ai-foundry/how-to/manage-costs)

## Support & Feedback

For issues, questions, or improvements:
1. Review this README and troubleshooting section
2. Check generated reports in `./audit/` and `./reports/`
3. Review script logs in `./logs/`
4. Contact your Azure support team for Foundry-specific issues

---

**Last Updated:** 2026-10-05
**Version:** 1.0.0
**Status:** Production Ready
