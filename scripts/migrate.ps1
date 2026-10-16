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
Which phases to run: All, Discovery, Planning, Refactoring, Deployment, Governance, Validation.
Defaults to All.

.PARAMETER DryRun
If true, validates but doesn't deploy (safe for testing).

.EXAMPLE
./migrate.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -Phases "Discovery","Planning" -Verbose

#>

#Requires -Version 7.4
[CmdletBinding()]
param(
    [string]$SubscriptionId = $null,
    [string]$FoundryProjectEndpoint = $env:AZURE_AI_PROJECT_ENDPOINT,
    [ValidateNotNullOrEmpty()]
    [ValidateSet("All", "Discovery", "Planning", "Refactoring", "Deployment", "Governance", "Validation")]
    [string[]]$Phases = @("Discovery", "Planning", "Refactoring", "Deployment", "Governance", "Validation"),
    [switch]$DryRun = $false,
    [string]$OutputDir = ".\migration-workspace",
    [string]$AgentConfigDir,
    [string]$ProjectName = "migrated-agents",
    [string]$Location = "eastus",
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$AccountName = $env:AZURE_AI_ACCOUNT_NAME,
    [string]$GovernanceConfigFile = (Join-Path $PSScriptRoot "..\governance\default-governance.json")
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")
if ($Phases -contains "All") {
    $Phases = @("Discovery", "Planning", "Refactoring", "Deployment", "Governance", "Validation")
}
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
$phaseScripts = @{
    Discovery = "discover-resources.ps1"
    Planning = "generate-migration-plan.ps1"
    Refactoring = "refactor-agents.ps1"
    Deployment = "deploy-agents.ps1"
    Governance = "apply-governance.ps1"
    Validation = "validate-migration.ps1"
}
foreach ($phase in $Phases) {
    $scriptPath = Join-Path $PSScriptRoot $phaseScripts[$phase]
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Missing script for ${phase}: $scriptPath"
    }
}
if (-not $DryRun -and $Phases -contains "Governance") {
    $null = Get-MigrationGovernanceDeployment $GovernanceConfigFile $FoundryProjectEndpoint
}
if (-not $DryRun -and $Phases -contains "Deployment" -and -not $FoundryProjectEndpoint) {
    if (-not $ResourceGroup -or -not $AccountName) {
        throw "Deployment without a project endpoint requires -ResourceGroup and -AccountName (or their Azure environment variables)."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "create-foundry-project.ps1") -PathType Leaf)) {
        throw "Missing project creation script: create-foundry-project.ps1"
    }
}
$needsAzure = ($Phases -contains "Discovery") -or
    (-not $DryRun -and (($Phases -contains "Deployment") -or ($Phases -contains "Governance") -or
    (($Phases -contains "Validation") -and $FoundryProjectEndpoint)))
& (Join-Path $PSScriptRoot "check-and-setup-dependencies.ps1") `
    -RequireAzure:$needsAzure -RequirePython:($Phases -contains "Refactoring")
if ($needsAzure -and $SubscriptionId) {
    $null = Invoke-MigrationAz @("account", "set", "--subscription", $SubscriptionId)
}

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
        & (Join-Path $PSScriptRoot "discover-resources.ps1") `
            -SubscriptionId $SubscriptionId `
            -OutputDir "$OutputDir\audit" `
            -Verbose:($VerbosePreference -eq "Continue")
    }
}

# Phase 2: Planning
if ($Phases -contains "Planning") {
    Invoke-Phase "Planning" {
        Log "Generating migration plan..." -Level "INFO"
        $auditFile = Get-ChildItem "$OutputDir\audit" -Filter "resources_*.json" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        if ($auditFile) {
            & (Join-Path $PSScriptRoot "generate-migration-plan.ps1") `
                -AuditFile $auditFile.FullName `
                -OutputDir "$OutputDir\migration-plan" `
                -Verbose:($VerbosePreference -eq "Continue")
        } else {
            throw "No audit file found in $OutputDir\audit. Run Discovery first."
        }
    }
}

# Phase 3: Refactoring
if ($Phases -contains "Refactoring") {
    Invoke-Phase "Refactoring" {
        Log "Refactoring agents..." -Level "INFO"
        & (Join-Path $PSScriptRoot "refactor-agents.ps1") `
            -MigrationPlanDir "$OutputDir\migration-plan" `
            -OutputDir "$OutputDir\refactored-agents" `
            -AgentConfigDir $AgentConfigDir `
            -Verbose:($VerbosePreference -eq "Continue")
    }
}

# Phase 4: Deployment
if ($Phases -contains "Deployment" -and -not $DryRun) {
    Invoke-Phase "Deployment" {
        if (-not $FoundryProjectEndpoint) {
            Log "Creating new Foundry project..." -Level "INFO"
            $project = & (Join-Path $PSScriptRoot "create-foundry-project.ps1") `
                -ProjectName $ProjectName -Location $Location `
                -ResourceGroup $ResourceGroup -AccountName $AccountName `
                -SubscriptionId $SubscriptionId `
                -Verbose:($VerbosePreference -eq "Continue")
            $script:FoundryProjectEndpoint = $project.Endpoint
        }
        
        Log "Deploying agents to Foundry..." -Level "INFO"
        & (Join-Path $PSScriptRoot "deploy-agents.ps1") `
            -AgentSourceDir "$OutputDir\refactored-agents" `
            -FoundryProjectEndpoint $FoundryProjectEndpoint `
            -SmokeTest $true `
            -Verbose:($VerbosePreference -eq "Continue")
    }
}

# Phase 5: Governance
if ($Phases -contains "Governance" -and -not $DryRun) {
    Invoke-Phase "Governance" {
        if (-not $FoundryProjectEndpoint) {
            throw "Governance requires -FoundryProjectEndpoint or AZURE_AI_PROJECT_ENDPOINT."
        }
        
        Log "Applying governance policies..." -Level "INFO"
        & (Join-Path $PSScriptRoot "apply-governance.ps1") `
            -FoundryProjectEndpoint $FoundryProjectEndpoint `
            -GovernanceConfigFile $GovernanceConfigFile `
            -OutputDir "$OutputDir\reports" `
            -Verbose:($VerbosePreference -eq "Continue")
    }
}

# Phase 6: Validation
if ($Phases -contains "Validation") {
    Invoke-Phase "Validation" {
        if ($DryRun -or -not $FoundryProjectEndpoint) {
            Log "Performing offline validation..." -Level "INFO"
            & (Join-Path $PSScriptRoot "validate-migration.ps1") `
                -AgentSourceDir "$OutputDir\refactored-agents" `
                -OutputDir "$OutputDir\reports" `
                -Verbose:($VerbosePreference -eq "Continue")
        } else {
            Log "Performing full end-to-end validation..." -Level "INFO"
            & (Join-Path $PSScriptRoot "validate-migration.ps1") `
                -FoundryProjectEndpoint $FoundryProjectEndpoint `
                -AgentSourceDir "$OutputDir\refactored-agents" `
                -OutputDir "$OutputDir\reports" `
                -Verbose:($VerbosePreference -eq "Continue")
        }
    }
}

# Summary
Write-Host ""
Log "╔════════════════════════════════════════════════════════════════╗" -Level "SUCCESS"
Log "║ REQUESTED PHASES COMPLETE                                       ║" -Level "SUCCESS"
Log "╚════════════════════════════════════════════════════════════════╝" -Level "SUCCESS"
Write-Host ""

Log "Output Directory: $OutputDir" -Level "INFO"
Log "Audit Reports: $OutputDir\audit" -Level "INFO"
Log "Migration Plan: $OutputDir\migration-plan" -Level "INFO"
Log "Refactored Agents: $OutputDir\refactored-agents" -Level "INFO"
Log "Validation Reports: $OutputDir\reports" -Level "INFO"

Log "Next Steps:" -Level "INFO"
Log "1. Review audit reports in $OutputDir\audit" -Level "INFO"
Log "2. Review migration strategy in $OutputDir\migration-plan" -Level "INFO"
Log "3. Test refactored agents locally before deployment" -Level "INFO"
if (-not $DryRun -and $FoundryProjectEndpoint) {
    Log "4. Monitor deployed agents in Foundry console" -Level "INFO"
    Log "5. Review validation report in $OutputDir\reports" -Level "INFO"
} else {
    Log "4. To deploy: Set AZURE_AI_PROJECT_ENDPOINT and run migrate.ps1 with -Phases Deployment" -Level "INFO"
}

Write-Host ""
if ($DryRun) {
    Log "Dry run complete. Deployment and governance were not executed." -Level "INFO"
}
