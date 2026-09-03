Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AzdValue([string] $name) {
    $value = & azd env get-value $name
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read azd environment value $name."
    }
    return ($value | Out-String).Trim()
}

function Get-OptionalAzdValue([string] $name) {
    $value = & azd env get-value $name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return ($value | Out-String).Trim()
}

$servicePrincipalIds = @(@(
    (Get-AzdValue 'MCP_COPILOT_SERVICE_PRINCIPAL_OBJECT_ID')
    (Get-OptionalAzdValue 'MCP_RESOURCE_SERVICE_PRINCIPAL_OBJECT_ID')
) | Where-Object { $_ } | Select-Object -Unique)
$applicationIds = @(@(
    (Get-AzdValue 'MCP_COPILOT_APP_OBJECT_ID')
    (Get-OptionalAzdValue 'MCP_RESOURCE_APP_OBJECT_ID')
) | Where-Object { $_ } | Select-Object -Unique)

function Remove-GraphObject([string] $resourceType, [string] $objectId) {
    $output = & az rest `
        --method delete `
        --url "https://graph.microsoft.com/v1.0/$resourceType/$objectId" `
        --only-show-errors 2>&1
    if ($LASTEXITCODE -eq 0) {
        return $null
    }

    $message = ($output | Out-String).Trim()
    if ($message -match 'Request_ResourceNotFound|ResourceNotFound|404') {
        Write-Host "$resourceType/$objectId is already removed."
        return $null
    }

    return "Unable to delete $resourceType/$objectId. $message"
}

$failures = [System.Collections.Generic.List[string]]::new()

foreach ($objectId in $servicePrincipalIds) {
    $failure = Remove-GraphObject 'servicePrincipals' $objectId
    if ($null -ne $failure) {
        $failures.Add($failure)
    }
}

foreach ($objectId in $applicationIds) {
    $failure = Remove-GraphObject 'applications' $objectId
    if ($null -ne $failure) {
        $failures.Add($failure)
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Removed the MCP Entra applications and service principals.'
