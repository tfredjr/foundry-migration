#Requires -Version 7.4
<#
.SYNOPSIS
Applies an explicitly configured resource-group governance ARM/Bicep deployment.
.DESCRIPTION
The default governance JSON is a requirements baseline, not an Azure API payload.
Add azureDeployment with resourceGroup, templateFile, and parametersFile. Paths
are relative to GovernanceConfigFile; parameters must bind foundryProjectEndpoint.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FoundryProjectEndpoint,
    [Parameter(Mandatory)][string]$GovernanceConfigFile,
    [string]$OutputDir = ".\reports"
)
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")
$endpoint = Get-MigrationEndpoint $FoundryProjectEndpoint
$deployment = Get-MigrationGovernanceDeployment $GovernanceConfigFile $endpoint
& (Join-Path $PSScriptRoot "check-and-setup-dependencies.ps1") -RequireAzure
$result = Invoke-MigrationAz @("deployment", "group", "create", "--resource-group", $deployment.ResourceGroup,
    "--name", "foundry-migration-governance", "--template-file", $deployment.Template, "--parameters", "@$($deployment.Parameters)")
if ($result.properties.provisioningState -ne "Succeeded") { throw "Governance deployment did not succeed." }
Write-MigrationJson @{
    endpoint = $endpoint
    deploymentId = $result.id
    provisioningState = $result.properties.provisioningState
    scope = "Only resources declared in the reviewed template; not a compliance certification."
} (Join-Path $OutputDir "governance-status.json")
