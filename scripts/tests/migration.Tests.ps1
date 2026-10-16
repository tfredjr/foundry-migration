#Requires -Version 7.4
<#
.SYNOPSIS
Runs offline regression tests with mocked Azure CLI calls. No Azure resources are accessed.
#>
$ErrorActionPreference = "Stop"
$scripts = Split-Path -Parent $PSScriptRoot
. (Join-Path $scripts "helpers\migration-common.ps1")
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "foundry-migration-tests-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $testRoot
$global:MigrationTestCalls = [Collections.Generic.List[object]]::new()
$global:MigrationTestFail = $false
$global:MigrationTestSmokeFail = $false
$global:MigrationTestEndpoint = "https://test.services.ai.azure.com/api/projects/test-project"
$script:checks = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:checks++
}

function Assert-Fails {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action } catch {
        Assert ($_.Exception.Message -like "*$Pattern*") "Expected '$Pattern', got '$($_.Exception.Message)'"
        return
    }
    throw "Expected failure: $Pattern"
}

function global:az {
    $arguments = @($args)
    $global:MigrationTestCalls.Add($arguments)
    $global:LASTEXITCODE = 0
    if ($global:MigrationTestFail) {
        $global:LASTEXITCODE = 7
        return
    }
    $command = $arguments -join " "
    if ($command -like "account show*") { return '{"id":"test-subscription"}' }
    if ($command -like "account set*") { return }
    if ($command -like "graph query*") {
        $query = $arguments[$arguments.IndexOf("-q") + 1]
        if ($query -like "*kind =~ 'OpenAI'*") {
            if ($arguments -contains "--skip-token") { return '{"data":[],"skip_token":null}' }
            return '{"data":[{"id":"account-id","name":"source","resourceGroup":"test-rg","location":"eastus","kind":"OpenAI"}],"skip_token":"page2"}'
        }
        if ($query -eq "Resources | where type == 'microsoft.cognitiveservices/accounts'") {
            return '{"data":[{"id":"account-id","name":"source","resourceGroup":"test-rg","location":"eastus"}]}'
        }
        return '{"data":[]}'
    }
    if ($command -like "cognitiveservices account deployment list*") {
        return '[{"name":"custom-model","properties":{"model":{"name":"gpt-4o","version":"test-version"}}}]'
    }
    if ($command -like "cognitiveservices account project create*") {
        return (@{ properties = @{ endpoints = @{ "AI Foundry API" = $global:MigrationTestEndpoint } } } | ConvertTo-Json -Depth 10)
    }
    if ($command -like "cognitiveservices account list*") { return '[]' }
    if ($command -like "cognitiveservices account create*" -or $command -like "group create*") { return '{}' }
    if ($command -like "deployment group create*") {
        return '{"id":"/subscriptions/test/deployments/governance","properties":{"provisioningState":"Succeeded"}}'
    }
    if ($command -like "rest*") {
        $url = $arguments[$arguments.IndexOf("--url") + 1]
        if ($url -eq "$global:MigrationTestEndpoint/openai/v1/responses") {
            $bodyPath = $arguments[$arguments.IndexOf("--body") + 1].Substring(1)
            $request = Read-MigrationJson $bodyPath
            if ($request.agent_reference.name -ne "sample-agent" -or $request.agent_reference.version -ne "1") {
                throw "Smoke request must use an explicit agent_reference and version."
            }
            if ($global:MigrationTestSmokeFail) { return '{"status":"failed","error":{"message":"test failure"}}' }
            return '{"status":"completed","error":null,"output":[{"type":"message","content":[{"text":"OK"}]}]}'
        }
        if ($url -ne "$global:MigrationTestEndpoint/agents?api-version=v1" -and
            $url -ne "$global:MigrationTestEndpoint/agents/sample-agent/versions/1?api-version=v1") {
            throw "Unexpected Foundry API URL: $url"
        }
        if ($arguments -contains "--body") {
            $bodyPath = $arguments[$arguments.IndexOf("--body") + 1].Substring(1)
            $global:MigrationTestLastBody = Get-Content -LiteralPath $bodyPath -Raw | ConvertFrom-Json -AsHashtable
        }
        return '{"name":"sample-agent","version":"1"}'
    }
    throw "Unexpected mock command: $command"
}

$oldEndpoint = $env:AZURE_AI_PROJECT_ENDPOINT
Push-Location $testRoot
try {
    $parseErrors = @(
        Get-ChildItem -LiteralPath $scripts -Recurse -Filter "*.ps1" | ForEach-Object {
            $tokens = $null
            $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
            $errors
        }
    )
    Assert ($parseErrors.Count -eq 0) "All PowerShell files parse: $parseErrors"
    $sourceDir = Join-Path $testRoot "exported"
    Write-MigrationJson @{
        name = "sample-agent"; model = "custom-model"; instructions = "Answer questions accurately."; temperature = 0.2
    } (Join-Path $sourceDir "sample.json")
    $workspace = Join-Path $testRoot "workspace"
    $env:AZURE_AI_PROJECT_ENDPOINT = $null
    & (Join-Path $scripts "migrate.ps1") -Phases All -DryRun -AgentConfigDir $sourceDir -OutputDir ".\workspace" -Verbose
    $agentDir = Join-Path $workspace "refactored-agents"
    $agentFile = Join-Path $agentDir "sample-agent\agent-config.json"
    $config = Read-MigrationJson $agentFile
    Assert ($config.modelConfiguration.modelDeployment -eq "custom-model") "Custom deployment is preserved"
    Assert ($config.systemPrompt.template -eq "Answer questions accurately.") "Instructions are preserved"
    $report = Read-MigrationJson (Join-Path $workspace "reports\validation-report.json")
    Assert ($report.passed -and $report.mode -eq "offline") "DryRun generates artifacts and validates offline"
    Assert (@($global:MigrationTestCalls | Where-Object { $_[0] -in @("rest", "group", "deployment") }).Count -eq 0) "DryRun does not mutate Azure"
    $graphCalls = @($global:MigrationTestCalls | Where-Object { $_[0] -eq "graph" })
    Assert (@($graphCalls | Where-Object { $_ -contains "--skip-token" }).Count -eq 1) "Discovery follows pagination"
    Assert (@($graphCalls | Where-Object { $_ -notcontains "--subscriptions" }).Count -eq 0) "Discovery scopes all queries"
    $modelFile = Get-ChildItem (Join-Path $workspace "audit") -Filter "models-deployed_*.json"
    Assert ((Read-MigrationJson $modelFile.FullName)[0].deploymentName -eq "custom-model") "Discovery writes model inventory"
    $auditReport = Get-ChildItem (Join-Path $workspace "audit") -Filter "resource-audit-report_*.md"
    Assert ((Get-Content $auditReport.FullName -Raw) -like "*Name:** source*") "Discovery renders inventory instead of script text"

    $before = $global:MigrationTestCalls.Count
    & (Join-Path $scripts "migrate.ps1") -Phases Validation -DryRun -OutputDir $workspace
    Assert ($global:MigrationTestCalls.Count -eq $before) "Offline validation needs no Azure login"
    $validateOnlyDir = Join-Path $testRoot "validate-only"
    & (Join-Path $scripts "refactor-agents.ps1") -MigrationPlanDir (Join-Path $workspace "migration-plan") `
        -AgentConfigDir $sourceDir -OutputDir $validateOnlyDir -ValidateOnly $true
    Assert (-not (Test-Path -LiteralPath $validateOnlyDir)) "ValidateOnly checks full transformation without writing output"
    Write-MigrationJson @{ name = "../escape"; model = "custom"; instructions = "Test" } (Join-Path $testRoot "unsafe\agent.json")
    Assert-Fails {
        & (Join-Path $scripts "refactor-agents.ps1") -MigrationPlanDir (Join-Path $workspace "migration-plan") `
            -AgentConfigDir (Join-Path $testRoot "unsafe") -OutputDir (Join-Path $testRoot "unsafe-output")
    } "safe name"
    Write-MigrationJson @{ name = "invalid"; model = "custom"; instructions = "Test"; temperature = 3 } (Join-Path $testRoot "invalid\agent.json")
    Assert-Fails {
        & (Join-Path $scripts "refactor-agents.ps1") -MigrationPlanDir (Join-Path $workspace "migration-plan") `
            -AgentConfigDir (Join-Path $testRoot "invalid") -OutputDir (Join-Path $testRoot "invalid-output") -ValidateOnly $true
    } "at most 2"
    Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot "invalid-output"))) "Invalid transformation does not leave partial output"
    Assert-Fails { & (Join-Path $scripts "migrate.ps1") -Phases Invalid } "ValidateSet"
    Assert-Fails {
        & (Join-Path $scripts "refactor-agents.ps1") -MigrationPlanDir (Join-Path $workspace "migration-plan") -OutputDir (Join-Path $testRoot "empty")
    } "No exported agents"
    Assert-Fails {
        & (Join-Path $scripts "refactor-agents.ps1") -MigrationPlanDir (Join-Path $workspace "migration-plan") -AgentConfigDir $sourceDir -OutputDir $agentDir
    } "already exists"
    Assert-Fails {
        & (Join-Path $scripts "apply-governance.ps1") -FoundryProjectEndpoint $global:MigrationTestEndpoint `
            -GovernanceConfigFile (Join-Path $scripts "..\governance\default-governance.json")
    } "not executable"
    $before = $global:MigrationTestCalls.Count
    Assert-Fails {
        & (Join-Path $scripts "migrate.ps1") -Phases All -AccountName test -ResourceGroup test -AgentConfigDir $sourceDir
    } "not executable"
    Assert ($global:MigrationTestCalls.Count -eq $before) "Invalid governance configuration is rejected before Azure side effects"
    Assert-Fails { Get-MigrationEndpoint "http://example.com/api/projects/test" } "HTTPS"

    Write-MigrationJson @{ azureDeployment = @{ resourceGroup = "test-rg"; templateFile = "policies.json"; parametersFile = "parameters.json" } } (Join-Path $testRoot "governance.json")
    Write-MigrationJson @{ resources = @() } (Join-Path $testRoot "policies.json")
    Write-MigrationJson @{ parameters = @{ foundryProjectEndpoint = @{ value = $global:MigrationTestEndpoint } } } (Join-Path $testRoot "parameters.json")
    & (Join-Path $scripts "migrate.ps1") -Phases Deployment,Governance,Validation `
        -OutputDir $workspace -ResourceGroup "test-rg" -AccountName "test" -ProjectName "test-project" `
        -GovernanceConfigFile (Join-Path $testRoot "governance.json")
    $receipt = Read-MigrationJson (Join-Path $agentDir "sample-agent\deployment.json")
    Assert ($receipt.endpoint -eq $global:MigrationTestEndpoint) "New project endpoint reaches deployment"
    Assert ($global:MigrationTestLastBody.definition.model -eq "custom-model") "Deployment uses exported deployment name"
    Assert ($global:MigrationTestLastBody.definition.temperature -eq 0.2) "Deployment preserves explicit sampling settings"
    $report = Read-MigrationJson (Join-Path $workspace "reports\validation-report.json")
    Assert ($report.passed -and $report.mode -eq "online") "Online handoffs and smoke test succeed with mocked Azure"
    Assert ((Read-MigrationJson (Join-Path $workspace "reports\governance-status.json")).provisioningState -eq "Succeeded") "Governance records actual deployment status"
    $posts = @($global:MigrationTestCalls | Where-Object { ($_ -join " ") -like "*--method POST*agents?*" }).Count
    & (Join-Path $scripts "deploy-agents.ps1") -AgentSourceDir $agentDir -FoundryProjectEndpoint $global:MigrationTestEndpoint
    Assert (@($global:MigrationTestCalls | Where-Object { ($_ -join " ") -like "*--method POST*agents?*" }).Count -eq $posts) "Rerunning deployment reuses receipts"
    $global:MigrationTestSmokeFail = $true
    Assert-Fails {
        & (Join-Path $scripts "validate-migration.ps1") -AgentSourceDir $agentDir -FoundryProjectEndpoint $global:MigrationTestEndpoint -OutputDir (Join-Path $testRoot "failed")
    } "Smoke test failed"
    Assert (-not (Read-MigrationJson (Join-Path $testRoot "failed\validation-report.json")).passed) "Failed validation persists a failed report"
    $global:MigrationTestSmokeFail = $false
    $config.tools = @(@{ type = "function"; function = @{ name = "lookup"; parameters = @{ type = "object" } } })
    Write-MigrationJson $config $agentFile
    Assert-Fails {
        & (Join-Path $scripts "deploy-agents.ps1") -AgentSourceDir $agentDir -FoundryProjectEndpoint $global:MigrationTestEndpoint
    } "tool runtime"
    $config.tools = @()
    Write-MigrationJson $config $agentFile
    Assert-Fails {
        & (Join-Path $scripts "deploy-agents.ps1") -AgentSourceDir $agentDir -FoundryProjectEndpoint $global:MigrationTestEndpoint
    } "receipt does not match"
    Write-MigrationJson @{
        name = "tool-agent"; model = "custom-model"; instructions = "Use lookup."
        tools = @(@{ type = "function"; function = @{ name = "lookup"; parameters = @{ type = "object"; properties = @{ key = @{ type = "string" } } } } })
    } (Join-Path $testRoot "tools\source.json")
    & (Join-Path $scripts "refactor-agents.ps1") -MigrationPlanDir (Join-Path $workspace "migration-plan") `
        -AgentConfigDir (Join-Path $testRoot "tools") -OutputDir (Join-Path $testRoot "tool-output")
    $toolConfig = Read-MigrationJson (Join-Path $testRoot "tool-output\tool-agent\agent-config.json")
    Assert ($toolConfig.tools[0].function.parameters.properties.key.type -eq "string") "Transformation preserves function parameter schemas"
    $global:MigrationTestFail = $true
    Assert-Fails { Invoke-MigrationAz @("account", "show") } "exit 7"
    Assert-Fails {
        & (Join-Path $scripts "discover-resources.ps1") -OutputDir (Join-Path $testRoot "failed-audit")
    } "exit 7"
    Assert (@(Get-ChildItem (Join-Path $testRoot "failed-audit") -Filter "*.json").Count -eq 0) "Failed Azure discovery does not write a success-shaped audit"
    Write-Host "Passed $script:checks migration regression checks (Azure CLI mocked)."
} finally {
    Pop-Location
    $env:AZURE_AI_PROJECT_ENDPOINT = $oldEndpoint
    Remove-Item -LiteralPath $testRoot -Recurse -Force
    Remove-Item Function:\az
    Remove-Variable MigrationTestCalls,MigrationTestFail,MigrationTestSmokeFail,MigrationTestEndpoint,MigrationTestLastBody -Scope Global -ErrorAction SilentlyContinue
}
