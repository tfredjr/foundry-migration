#Requires -Version 7.4
<#
.SYNOPSIS
Creates a Foundry account and project and returns its project endpoint.
.DESCRIPTION
Requires an explicit resource group and account name (parameters or environment).
Does not deploy models, configure private networking, or enable hosted-agent infrastructure.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectName,
    [string]$Location = "eastus",
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [string]$AccountName = $env:AZURE_AI_ACCOUNT_NAME,
    [string]$SubscriptionId,
    [bool]$EnableHostedAgents = $false
)
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")
if ($EnableHostedAgents) { throw "Hosted agents require separately provisioned infrastructure. This script creates prompt-agent projects only." }
if (-not $ResourceGroup -or -not $AccountName) {
    throw "Set AZURE_RESOURCE_GROUP and AZURE_AI_ACCOUNT_NAME or supply -ResourceGroup and -AccountName."
}
if ($ProjectName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$') { throw "Invalid project name: $ProjectName" }
& (Join-Path $PSScriptRoot "check-and-setup-dependencies.ps1") -RequireAzure
if ($SubscriptionId) { $null = Invoke-MigrationAz @("account", "set", "--subscription", $SubscriptionId) }
$null = Invoke-MigrationAz @("group", "create", "--name", $ResourceGroup, "--location", $Location)
$accounts = @(Invoke-MigrationAz @("cognitiveservices", "account", "list", "--resource-group", $ResourceGroup))
$existing = @($accounts | Where-Object { $_.name -eq $AccountName })
if ($existing.Count -gt 0) {
    if ($existing[0].kind -ne "AIServices" -or -not $existing[0].properties.allowProjectManagement) {
        throw "Existing account '$AccountName' is not a project-enabled Foundry account. Review it before continuing."
    }
} else {
    $null = Invoke-MigrationAz @("cognitiveservices", "account", "create", "--name", $AccountName,
        "--resource-group", $ResourceGroup, "--location", $Location, "--kind", "AIServices", "--sku", "S0",
        "--custom-domain", $AccountName, "--assign-identity", "--allow-project-management", "true")
}
$project = Invoke-MigrationAz @("cognitiveservices", "account", "project", "create", "--name", $AccountName,
    "--resource-group", $ResourceGroup, "--project-name", $ProjectName, "--location", $Location)
$endpoints = @($project.properties.endpoints.Values | Where-Object { $_ -match '/api/projects/' })
if ($endpoints.Count -ne 1) { throw "Azure did not return a unique project endpoint. Inspect the created project before continuing." }
$endpoint = Get-MigrationEndpoint $endpoints[0]
$env:AZURE_AI_PROJECT_ENDPOINT = $endpoint
$env:AZURE_AI_PROJECT_NAME = $ProjectName
[pscustomobject]@{ Endpoint = $endpoint; ProjectName = $ProjectName; ResourceGroup = $ResourceGroup; AccountName = $AccountName }
