Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OptionalAzdValue([string] $name) {
    $value = & azd env get-value $name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return ($value | Out-String).Trim()
}

$projectEndpoint = Get-OptionalAzdValue 'AZURE_AI_PROJECT_ENDPOINT'
if (-not $projectEndpoint) {
    $projectEndpoint = Get-OptionalAzdValue 'AZURE_AIPROJECT_ENDPOINT'
}
if (-not $projectEndpoint) {
    throw 'Unable to read the Foundry project endpoint from the azd environment.'
}

$arguments = @(
    'ai', 'connection', 'create', 'github-mcp-managed',
    '--kind', 'remote-tool',
    '--target', 'https://api.githubcopilot.com/mcp',
    '--auth-type', 'oauth2',
    '--connector-name', 'foundrygithubmcp',
    '--metadata', 'type=catalog_MCP',
    '--metadata', 'toolEntityId=azureml://location/eastus/apiCenter/registry-prod-bl/type/tools/objectId/github-mcp-server/version/1',
    '--project-endpoint', $projectEndpoint,
    '--force'
)

& azd @arguments
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to create the Foundry-managed GitHub MCP connection.'
}

Write-Host 'Created the Foundry-managed GitHub MCP connection.'
