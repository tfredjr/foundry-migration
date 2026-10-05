#!/usr/bin/env pwsh
<#
.SYNOPSIS
Main orchestration script for the complete OpenAI to Foundry migration.

.DESCRIPTION
This script orchestrates the entire migration workflow:
1. Validate prerequisites
2. Discover resources
3. Generate migration plan
4. Refactor agents
5. Deploy to Foundry
6. Apply governance
7. Validate migration

Run this for hands-off, end-to-end migration.

.PARAMETER SubscriptionId
Azure subscription ID (defaults to current subscription).

.PARAMETER FoundryProjectEndpoint
Foundry project endpoint URL. If not provided, creates new project.

.PARAMETER Phases
Which phases to run: All, Discovery, Planning, Deployment, Governance, Validation.
Defaults to All.

.PARAMETER DryRun
If true, validates but doesn't deploy (safe for testing).

.EXAMPLE
./migrate.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -Phases "Discovery","Planning" -Verbose

#>

param(
    [string]$SubscriptionId = $null,
    [string]$FoundryProjectEndpoint = $null,
    [string[]]$Phases = @("Discovery", "Planning", "Refactoring", "Deployment", "Governance", "Validation"),
    [switch]$DryRun = $false,
    [string]$OutputDir = "./migration-workspace",
    [switch]$Verbose = $false
)

$ErrorActionPreference = "Stop"

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Invoke-Phase {
    param(
        [string]$Phase,
        [scriptblock]$Block
    )
    
    Write-Host ""
    Log "╔════════════════════════════════════════════════════════════════╗" -Level "PHASE"
    Log "║ PHASE: $Phase" -Level "PHASE"
    Log "╚════════════════════════════════════════════════════════════════╝" -Level "PHASE"
    Write-Host ""
    
    try {
        & $Block
        Log "✓ Phase complete: $Phase" -Level "SUCCESS"
    } catch {
        Log "✗ Phase failed: $Phase - $_" -Level "ERROR"
        throw
    }
}

# Initialize
Log "Starting end-to-end OpenAI to Foundry migration" -Level "INFO"
Log "Dry Run Mode: $DryRun" -Level "INFO"
Write-Host ""

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Phase 1: Discovery
if ($Phases -contains "Discovery") {
    Invoke-Phase "Discovery" {
        Log "Discovering Azure AI resources..." -Level "INFO"
        & ".\scripts\discover-resources.ps1" `
            -SubscriptionId $SubscriptionId `
            -OutputDir "$OutputDir/audit" `
            -Verbose:$Verbose
    }
}

# Phase 2: Planning
if ($Phases -contains "Planning") {
    Invoke-Phase "Planning" {
        Log "Generating migration plan..." -Level "INFO"
        $auditFile = Get-ChildItem "$OutputDir/audit" -Filter "resources_*.json" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        if ($auditFile) {
            & ".\scripts\generate-migration-plan.ps1" `
                -AuditFile $auditFile.FullName `
                -OutputDir "$OutputDir/migration-plan" `
                -Verbose:$Verbose
        } else {
            Log "⚠ No audit file found - skipping migration plan generation" -Level "WARN"
        }
    }
}

# Phase 3: Refactoring
if ($Phases -contains "Refactoring") {
    Invoke-Phase "Refactoring" {
        Log "Refactoring agents..." -Level "INFO"
        & ".\scripts\refactor-agents.ps1" `
            -MigrationPlanDir "$OutputDir/migration-plan" `
            -OutputDir "$OutputDir/refactored-agents" `
            -ValidateOnly $DryRun `
            -Verbose:$Verbose
    }
}

# Phase 4: Deployment
if ($Phases -contains "Deployment" -and -not $DryRun) {
    Invoke-Phase "Deployment" {
        if (-not $FoundryProjectEndpoint) {
            Log "Creating new Foundry project..." -Level "INFO"
            & ".\scripts\create-foundry-project.ps1" `
                -ProjectName "energy-transfer-ai-$(Get-Random -Minimum 1000 -Maximum 9999)" `
                -Location "eastus" `
                -EnableHostedAgents $true `
                -Verbose:$Verbose
            
            # After creation, user needs to set endpoint
            Log "⚠ Please set AZURE_AI_PROJECT_ENDPOINT environment variable and re-run" -Level "WARN"
            return
        }
        
        Log "Deploying agents to Foundry..." -Level "INFO"
        & ".\scripts\deploy-agents.ps1" `
            -AgentSourceDir "$OutputDir/refactored-agents" `
            -FoundryProjectEndpoint $FoundryProjectEndpoint `
            -SmokeTest $true `
            -Verbose:$Verbose
    }
}

# Phase 5: Governance
if ($Phases -contains "Governance" -and -not $DryRun) {
    Invoke-Phase "Governance" {
        if (-not $FoundryProjectEndpoint) {
            Log "⚠ Cannot apply governance without Foundry endpoint - skipping" -Level "WARN"
            return
        }
        
        Log "Applying governance policies..." -Level "INFO"
        & ".\scripts\apply-governance.ps1" `
            -FoundryProjectEndpoint $FoundryProjectEndpoint `
            -GovernanceConfigFile ".\governance\default-governance.json" `
            -Verbose:$Verbose
    }
}

# Phase 6: Validation
if ($Phases -contains "Validation") {
    Invoke-Phase "Validation" {
        if ($DryRun -or -not $FoundryProjectEndpoint) {
            Log "Performing offline validation..." -Level "INFO"
            & ".\scripts\validate-migration.ps1" `
                -AgentSourceDir "$OutputDir/refactored-agents" `
                -OutputDir "$OutputDir/reports" `
                -Verbose:$Verbose
        } else {
            Log "Performing full end-to-end validation..." -Level "INFO"
            & ".\scripts\validate-migration.ps1" `
                -FoundryProjectEndpoint $FoundryProjectEndpoint `
                -AgentSourceDir "$OutputDir/refactored-agents" `
                -OutputDir "$OutputDir/reports" `
                -Verbose:$Verbose
        }
    }
}

# Summary
Write-Host ""
Log "╔════════════════════════════════════════════════════════════════╗" -Level "SUCCESS"
Log "║ MIGRATION COMPLETE                                              ║" -Level "SUCCESS"
Log "╚════════════════════════════════════════════════════════════════╝" -Level "SUCCESS"
Write-Host ""

Log "Output Directory: $OutputDir" -Level "INFO"
Log "Audit Reports: $OutputDir/audit" -Level "INFO"
Log "Migration Plan: $OutputDir/migration-plan" -Level "INFO"
Log "Refactored Agents: $OutputDir/refactored-agents" -Level "INFO"
Log "Validation Reports: $OutputDir/reports" -Level "INFO"

Log "Next Steps:" -Level "INFO"
Log "1. Review audit reports in $OutputDir/audit" -Level "INFO"
Log "2. Review migration strategy in $OutputDir/migration-plan" -Level "INFO"
Log "3. Test refactored agents locally before deployment" -Level "INFO"
if (-not $DryRun -and $FoundryProjectEndpoint) {
    Log "4. Monitor deployed agents in Foundry console" -Level "INFO"
    Log "5. Review validation report in $OutputDir/reports" -Level "INFO"
} else {
    Log "4. To deploy: Set AZURE_AI_PROJECT_ENDPOINT and run migrate.ps1 with -Phases Deployment" -Level "INFO"
}

Write-Host ""
Log "Migration framework complete!" -Level "SUCCESS"
