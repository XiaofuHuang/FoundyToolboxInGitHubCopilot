#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Get-AzdValue([string] $name) {
    $value = & azd env get-value $name
    if ($LASTEXITCODE -ne 0) { throw "Unable to read azd environment value $name." }
    return ($value | Out-String).Trim()
}

$tenantId = Get-AzdValue 'ENTRA_TENANT_ID'
$accountTenant = & az account show --query tenantId --output tsv
if ($LASTEXITCODE -ne 0 -or $accountTenant -ne $tenantId) {
    throw 'Sign Azure CLI into the deployment tenant before removing Entra objects.'
}
$objects = @{
    servicePrincipals = (Get-AzdValue 'ENTRA_SERVICE_PRINCIPAL_OBJECT_ID')
    applications = (Get-AzdValue 'ENTRA_APP_OBJECT_ID')
}
foreach ($id in $objects.Values) {
    $parsedId = [guid]::Empty
    if (-not [guid]::TryParse($id, [ref]$parsedId)) { throw 'Invalid Entra object ID in this environment.' }
}
$token = $null
$headers = $null
try {
    $token = & az account get-access-token --tenant $tenantId `
        --resource https://graph.microsoft.com/ --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0) { throw 'Microsoft Graph authentication failed.' }
    $headers = @{ Authorization = "Bearer $token" }
    foreach ($resourceType in @('servicePrincipals', 'applications')) {
        $id = $objects[$resourceType]
        try {
            $response = Invoke-WebRequest -Method DELETE `
                -Uri "https://graph.microsoft.com/v1.0/$resourceType/$id" `
                -Headers $headers -SkipHttpErrorCheck -TimeoutSec 60 -Verbose:$false -Debug:$false
        }
        catch {
            throw "Unable to delete $resourceType/$id. Request details are suppressed to protect credentials."
        }
        if ([int]$response.StatusCode -eq 404) {
            Write-Host "$resourceType/$id is already removed."
        } elseif ([int]$response.StatusCode -ne 204) {
            throw "Unable to delete $resourceType/$id (HTTP $($response.StatusCode))."
        }
    }
    Write-Host 'Removed this environment application and service principal.'
}
finally {
    $token = $null
    $headers = $null
}
