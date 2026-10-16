$ErrorActionPreference = "Stop"

function Read-MigrationJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file not found: $Path"
    }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -NoEnumerate
}

function Write-MigrationJson {
    param($Value, [string]$Path)
    $Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    ConvertTo-Json -InputObject $Value -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-MigrationAz {
    param([string[]]$Arguments)
    $output = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed (exit $LASTEXITCODE): az $($Arguments[0])"
    }
    if ($output) {
        ($output -join "`n") | ConvertFrom-Json -AsHashtable
    }
}

function Get-MigrationEndpoint {
    param([string]$Endpoint)
    $uri = $null
    if (-not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne "https" -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        $uri.AbsolutePath.TrimEnd("/") -notmatch '^/api/projects/[^/]+$') {
        throw "Expected an HTTPS Foundry project endpoint: https://<account>.services.ai.azure.com/api/projects/<project>"
    }
    $uri.AbsoluteUri.TrimEnd("/")
}

function Invoke-MigrationApi {
    param(
        [string]$Endpoint,
        [string]$Path,
        [ValidateSet("GET", "POST")][string]$Method = "GET",
        $Body
    )
    $endpointUrl = Get-MigrationEndpoint $Endpoint
    $url = "$endpointUrl/$Path"
    if ($Path -notlike "openai/v1/*") { $url += "?api-version=v1" }
    $arguments = @("rest", "--method", $Method, "--url", $url,
        "--resource", "https://ai.azure.com")
    $bodyFile = $null
    try {
        if ($null -ne $Body) {
            $bodyFile = [IO.Path]::GetTempFileName()
            Write-MigrationJson $Body $bodyFile
            $arguments += @("--body", "@$bodyFile", "--headers", "Content-Type=application/json")
        }
        Invoke-MigrationAz $arguments
    } finally {
        if ($bodyFile) { Remove-Item -LiteralPath $bodyFile -Force }
    }
}

function Get-MigrationAgents {
    param([string]$AgentSourceDir)
    if (-not (Test-Path -LiteralPath $AgentSourceDir -PathType Container)) {
        throw "Agent source directory not found: $AgentSourceDir. Run Refactoring first."
    }
    $files = @(Get-ChildItem -LiteralPath $AgentSourceDir -Recurse -File -Filter "agent-config.json")
    if ($files.Count -eq 0) { throw "No agent-config.json files found in $AgentSourceDir." }
    $names = @{}
    foreach ($file in $files) {
        $config = Read-MigrationJson $file.FullName
        $schema = Join-Path $PSScriptRoot "..\..\templates\agent-spec.json"
        if (-not (Test-Json -Json ($config | ConvertTo-Json -Depth 100) -SchemaFile $schema)) {
            throw "Invalid agent configuration: $($file.FullName)"
        }
        $name = $config.metadata.name
        if ($name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$') {
            throw "Agent name must contain 1-63 letters, digits, underscores or hyphens: $name"
        }
        if ($names.ContainsKey($name)) { throw "Duplicate agent name: $name" }
        $names[$name] = $true
        [pscustomobject]@{ Name = $name; Config = $config; Directory = $file.DirectoryName }
    }
}

function Get-MigrationDefinition {
    param($Config)
    if (@($Config.tools).Count -gt 0) {
        throw "Agent '$($Config.metadata.name)' has tools. Port and review its tool runtime before deployment; automatic tool deployment is not supported."
    }
    # Prompt directives are not a substitute for platform-enforced governance.
    $definition = @{
        kind = "prompt"
        model = $Config.modelConfiguration.modelDeployment
        instructions = $Config.systemPrompt.template
    }
    if ($Config.modelConfiguration.ContainsKey("temperature")) {
        $definition.temperature = $Config.modelConfiguration.temperature
    }
    if ($Config.modelConfiguration.ContainsKey("topP")) {
        $definition.top_p = $Config.modelConfiguration.topP
    }
    $definition
}

function Get-MigrationGovernanceDeployment {
    param([string]$ConfigFile, [string]$Endpoint)
    $config = Read-MigrationJson $ConfigFile
    $deployment = $config.azureDeployment
    if (-not $deployment -or -not $deployment.resourceGroup -or -not $deployment.templateFile -or -not $deployment.parametersFile) {
        throw "Governance baseline is not executable. Configure azureDeployment.resourceGroup, templateFile and parametersFile with a reviewed ARM/Bicep template implementing your policies. No governance was applied."
    }
    $configDir = Split-Path -Parent (Resolve-Path -LiteralPath $ConfigFile).Path
    $template = Join-Path $configDir $deployment.templateFile
    $parameters = Join-Path $configDir $deployment.parametersFile
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Governance template not found: $template" }
    $parameterData = Read-MigrationJson $parameters
    $boundEndpoint = Get-MigrationEndpoint $parameterData.parameters.foundryProjectEndpoint.value
    if ($Endpoint -and $boundEndpoint -ne (Get-MigrationEndpoint $Endpoint)) {
        throw "Governance parameters must bind foundryProjectEndpoint to the selected project endpoint."
    }
    @{ ResourceGroup = $deployment.resourceGroup; Template = $template; Parameters = $parameters }
}

function Test-MigrationAgent {
    param([string]$Endpoint, [string]$Name, [string]$Version)
    $reference = @{ type = "agent_reference"; name = $Name; version = $Version }
    $response = Invoke-MigrationApi -Endpoint $Endpoint -Path "openai/v1/responses" -Method POST -Body @{
        agent_reference = $reference
        input = "Reply with OK."
    }
    if ($response.status -ne "completed" -or $response.error) {
        throw "Smoke test failed for agent '$Name': $($response | ConvertTo-Json -Depth 20 -Compress)"
    }
    $response
}
