# Quick Start: Hands-Off Migration Execution

This guide enables non-technical stakeholders to execute the entire migration with minimal manual intervention.

## Prerequisites (5 minutes)

1. **Azure Credentials**
   ```powershell
   az login
   az account set --subscription "YOUR_SUBSCRIPTION_ID"
   ```

2. **Clone/Download Migration Framework**
   ```powershell
   git clone <migration-framework-repo>
   cd foundry-migration
   ```

3. **Verify Prerequisites** (runs all checks automatically)
   ```powershell
   ./scripts/check-and-setup-dependencies.ps1
   ```

## One-Command Migration

Run the complete migration with one command:

```powershell
./scripts/migrate.ps1 `
  -SubscriptionId "YOUR_SUBSCRIPTION_ID" `
  -Phases @("Discovery", "Planning", "Refactoring", "Deployment", "Governance", "Validation") `
  -Verbose
```

This script will:
1. ✓ Discover all OpenAI and Foundry resources
2. ✓ Generate detailed migration plan
3. ✓ Refactor all agents (offline, non-destructive)
4. ✓ Create Foundry project if needed
5. ✓ Deploy refactored agents
6. ✓ Apply governance policies
7. ✓ Validate end-to-end migration

**Expected Duration:** 2-3 hours total

## Step-by-Step Quick Start

### Step 1: Audit Existing Resources (30 minutes)

```powershell
# Discover all AI resources
./scripts/discover-resources.ps1 `
  -SubscriptionId "YOUR_SUBSCRIPTION_ID" `
  -OutputDir "./audit"

# Review the audit report
notepad ./audit/resource-audit-report_*.md
```

**Expected Output:**
- `resource-audit-report_*.md` — Human-readable summary
- `resources_*.json` — Machine-readable data
- `models-deployed_*.json` — Model inventory

### Step 2: Create Migration Plan (15 minutes)

```powershell
# Generate detailed migration strategy
$latestAudit = Get-ChildItem "./audit/resources_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1

./scripts/generate-migration-plan.ps1 `
  -AuditFile $latestAudit.FullName `
  -OutputDir "./migration-plan"

# Review the strategy
notepad ./migration-plan/MIGRATION_STRATEGY.md
```

**Expected Output:**
- `MIGRATION_STRATEGY.md` — Detailed step-by-step plan
- `resource-migration-map.json` — Resource mapping
- `phased-rollout.json` — Deployment sequence

### Step 3: Set Up Foundry Project (If New) (30 minutes)

**Option A: Create New Project**

```powershell
./scripts/create-foundry-project.ps1 `
  -ProjectName "energy-transfer-prod" `
  -Location "eastus" `
  -EnableHostedAgents $true `
  -Verbose

# After creation, extract the project endpoint and set environment variables
$env:AZURE_AI_PROJECT_ENDPOINT = "https://YOUR_ENDPOINT"
$env:AZURE_AI_PROJECT_NAME = "energy-transfer-prod"
```

**Option B: Use Existing Project**

```powershell
# Set these environment variables to your existing project:
$env:AZURE_AI_PROJECT_ENDPOINT = "https://YOUR_ENDPOINT"
$env:AZURE_AI_PROJECT_NAME = "YOUR_PROJECT_NAME"
$env:AZURE_RESOURCE_GROUP = "YOUR_RESOURCE_GROUP"
$env:AZURE_AI_ACCOUNT_NAME = "YOUR_ACCOUNT_NAME"
```

### Step 4: Refactor Agents (1-2 hours, fully automated)

```powershell
# Transform all agents (offline, non-destructive)
./scripts/refactor-agents.ps1 `
  -MigrationPlanDir "./migration-plan" `
  -OutputDir "./refactored-agents" `
  -ValidateOnly $false `
  -Verbose

# Review generated agents
Get-ChildItem ./refactored-agents -Recurse -Filter "*.py" | Select-Object FullName
```

**Expected Output:**
```
refactored-agents/
├── agent-1/
│   ├── main.py                  (refactored agent code)
│   ├── agent-config.yaml        (Foundry configuration)
│   ├── requirements.txt          (dependencies)
│   └── README.md               (documentation)
├── agent-2/
│   └── ...
```

### Step 5: Deploy to Foundry (1-2 hours, mostly automated)

```powershell
# Deploy all refactored agents
./scripts/deploy-agents.ps1 `
  -AgentSourceDir "./refactored-agents" `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT `
  -SmokeTest $true `
  -Verbose

# This will:
# - Deploy each agent
# - Run smoke tests
# - Generate deployment report
# - Show deployment status
```

**Expected Output:**
```
[Success] Deployed: energy-analysis-assistant (v1.0.0)
[Success] Deployed: compliance-reporter (v1.0.0)
[Success] Deployed: demand-forecaster (v1.0.0)
...
```

### Step 6: Apply Governance Policies (15 minutes)

```powershell
# Configure guardrails, RBAC, and audit logging
./scripts/apply-governance.ps1 `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT `
  -GovernanceConfigFile "./governance/default-governance.json" `
  -Verbose

# This will:
# - Enable content filters
# - Set up RBAC roles
# - Enable audit logging
# - Configure guardrails
```

### Step 7: Validate Migration (30 minutes)

```powershell
# Run comprehensive validation tests
./scripts/validate-migration.ps1 `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT `
  -AgentSourceDir "./refactored-agents" `
  -OutputDir "./reports" `
  -Verbose

# Review validation report
notepad ./reports/validation-report-*.md
```

**Expected Output:**
- ✓ All agents deployed successfully
- ✓ Governance policies applied
- ✓ Audit logging active
- ✓ Performance baseline established

## What If Something Fails?

### Troubleshooting Common Issues

**Issue: "Dependency check failed"**

```powershell
# Manually install missing dependencies
# Azure CLI: https://aka.ms/installazurecli
# Azure Developer CLI: https://aka.ms/azure-dev/install
# Python 3.9+: https://www.python.org/downloads/
# Then re-run: ./scripts/check-and-setup-dependencies.ps1
```

**Issue: "Resource discovery failed - permission denied"**

```powershell
# Verify you have required permissions
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" `
  --query "[].roleDefinitionName" -o table

# Required: Owner or Contributor role
# If missing: Request elevated access from admin
```

**Issue: "Foundry project endpoint not accessible"**

```powershell
# Verify endpoint format
Write-Host $env:AZURE_AI_PROJECT_ENDPOINT

# Should be: https://<region>.api.cognitive.microsoft.com/

# Test connectivity
curl -I $env:AZURE_AI_PROJECT_ENDPOINT

# If behind VNet: Ensure you're inside VNet or using private endpoint
```

**Issue: "Agent deployment timed out"**

```powershell
# Check ACR space and quota
az cognitiveservices account show `
  --name <account-name> `
  --resource-group <resource-group> `
  --query "properties.quotaLimit"

# Try deploying agents one at a time
./scripts/deploy-agents.ps1 `
  -AgentSourceDir "./refactored-agents/agent-1" `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT
```

**Issue: "Validation test failed"**

```powershell
# Check validation report for details
notepad ./reports/validation-report-*.md

# Common issues:
# - Model not deployed
# - Configuration error
# - Integration test failed
# - Governance policy conflict

# Fix and re-run validation
./scripts/validate-migration.ps1 `
  -FoundryProjectEndpoint $env:AZURE_AI_PROJECT_ENDPOINT `
  -AgentSourceDir "./refactored-agents"
```

## Monitoring After Deployment

### Health Check

```powershell
# Check deployed agents
az ai agent list --resource-group <resource-group>

# View recent invocations
az monitor log query --workspace <workspace-id> `
  --query "event_type == 'agent-invoked'" `
  --time-range "24h"

# Check for errors
az monitor log query --workspace <workspace-id> `
  --query "event_type == 'error-occurred'" `
  --time-range "24h"
```

### Performance Monitoring

View Foundry console:
1. Navigate to [Azure Portal](https://portal.azure.com)
2. Go to your Foundry project
3. View agent metrics and logs
4. Monitor latency, errors, token usage

### Alerts Configuration

Alerts are automatically configured for:
- High error rates (>5%)
- High latency (>2 seconds)
- Guardrail violations (content filters triggered)
- Quota exceeded
- Service degradation

## Rollback Procedure

If you need to rollback to OpenAI Studio:

```powershell
# 1. Stop routing new requests to Foundry agents
# 2. Update application configuration to use OpenAI endpoints
# 3. Keep Foundry agents deployed for reference (don't delete)
# 4. Run validation to ensure OpenAI endpoints are responsive
# 5. Monitor OpenAI usage to confirm traffic shift

# Foundry agents remain available for future re-enablement
```

## Success Confirmation

Migration is successful when:

✓ All agents deployed to Foundry  
✓ Smoke tests pass  
✓ Validation report shows green status  
✓ Governance policies active  
✓ Monitoring and alerts functioning  
✓ No errors in first 24 hours of operation  

## Next: Production Cutover

After successful validation in staging:

1. **Plan cutover window** — identify low-traffic period
2. **Brief operations team** — runbooks and escalation paths
3. **Enable monitoring** — set up real-time dashboards
4. **Start canary deployment** — route small % of traffic to Foundry (5%)
5. **Monitor closely** — watch for errors and latency
6. **Gradually increase traffic** — 10% → 25% → 50% → 100% (2-4 hours per step)
7. **Decommission OpenAI** — after 24-48 hours of stable operation
8. **Document lessons learned** — update procedures and runbooks

## Support

For issues or questions:

1. Check troubleshooting section above
2. Review logs in `./logs/` directory
3. Check generated reports in `./audit/`, `./migration-plan/`, `./reports/`
4. Contact Azure support for Foundry-specific issues

---

**Estimated Total Time:** 4-6 hours  
**Hands-On Time Required:** Minimal (mostly automated)  
**Risk Level:** Low (non-destructive, can rollback)  
**Support Level:** Fully automated with detailed reporting
