#Requires -Version 7.4
<#
.SYNOPSIS
Deploys reviewed prompt-agent configurations using the Foundry v1 API.
.DESCRIPTION
Referenced models must already be deployed. Tools require manual runtime migration.
Writes one deployment receipt per agent; rerunning verifies and reuses the recorded version.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AgentSourceDir,
    [Parameter(Mandatory)][string]$FoundryProjectEndpoint,
    [bool]$SmokeTest = $true
)
. (Join-Path $PSScriptRoot "helpers\migration-common.ps1")
$endpoint = Get-MigrationEndpoint $FoundryProjectEndpoint
$agents = @(Get-MigrationAgents $AgentSourceDir)
# Validate the entire batch before any remote writes.
foreach ($agent in $agents) { $null = Get-MigrationDefinition $agent.Config }
& (Join-Path $PSScriptRoot "check-and-setup-dependencies.ps1") -RequireAzure
foreach ($agent in $agents) {
    $receiptPath = Join-Path $agent.Directory "deployment.json"
    $hash = (Get-FileHash -LiteralPath (Join-Path $agent.Directory "agent-config.json") -Algorithm SHA256).Hash
    if (Test-Path -LiteralPath $receiptPath) {
        $receipt = Read-MigrationJson $receiptPath
        if ($receipt.endpoint -ne $endpoint -or $receipt.configHash -ne $hash -or -not $receipt.version) {
            throw "Deployment receipt does not match '$($agent.Name)'. Use a fresh source directory for an intentional new version."
        }
        $version = [string]$receipt.version
        $null = Invoke-MigrationApi -Endpoint $endpoint -Path "agents/$($agent.Name)/versions/$version"
    } else {
        $deployed = Invoke-MigrationApi -Endpoint $endpoint -Path "agents" -Method POST -Body @{
            name = $agent.Name
            definition = Get-MigrationDefinition $agent.Config
        }
        if (-not $deployed.version) { throw "No deployment version returned for $($agent.Name)." }
        $version = [string]$deployed.version
        Write-MigrationJson @{
            endpoint = $endpoint; name = $agent.Name; version = $version; configHash = $hash
        } $receiptPath
    }
    if ($SmokeTest) { $null = Test-MigrationAgent $endpoint $agent.Name $version }
    Write-Host "Deployed: $($agent.Name) (version $version)"
}
