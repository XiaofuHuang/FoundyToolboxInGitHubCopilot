#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Get-AzdValue([string] $name) {
    $value = & azd env get-value $name
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read azd environment value $name."
    }
    return ($value | Out-String).Trim()
}

function Invoke-CheckedRequest {
    param(
        [string] $Operation,
        [string] $Method,
        [string] $Uri,
        [hashtable] $Headers,
        [object] $Body,
        [string] $ContentType = 'application/json',
        [int[]] $ExpectedStatus = @(200)
    )
    $parameters = @{
        Method = $Method
        Uri = $Uri
        Headers = $Headers
        ContentType = $ContentType
        SkipHttpErrorCheck = $true
        TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $parameters.Body = if ($ContentType -eq 'application/json') {
            $Body | ConvertTo-Json -Depth 8 -Compress
        } else {
            $Body
        }
    }
    try {
        $response = Invoke-WebRequest @parameters -Verbose:$false -Debug:$false
    }
    catch {
        throw "$Operation could not complete. Request and response details are suppressed to protect credentials."
    }
    if ([int]$response.StatusCode -notin $ExpectedStatus) {
        throw "$Operation failed with HTTP $($response.StatusCode). Response content is not logged because it may contain credentials."
    }
    return $response
}

function ConvertFrom-CheckedJson([string] $Content, [string] $Operation) {
    try {
        return ConvertFrom-Json -InputObject $Content
    }
    catch {
        throw "$Operation returned invalid JSON. Response content is suppressed to protect credentials."
    }
}

$tenantId = Get-AzdValue 'ENTRA_TENANT_ID'
$subscriptionId = Get-AzdValue 'AZURE_SUBSCRIPTION_ID'
$applicationId = Get-AzdValue 'ENTRA_APP_OBJECT_ID'
$clientId = Get-AzdValue 'ENTRA_APP_CLIENT_ID'
$namedValueId = Get-AzdValue 'APIM_APP_SECRET_NAMED_VALUE_ID'
$resourceGroup = Get-AzdValue 'AZURE_RESOURCE_GROUP'
$apimName = Get-AzdValue 'APIM_NAME'
$expectedId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/namedValues/foundry-app-client-secret"
if (-not $namedValueId.Equals($expectedId, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The named value does not belong to the selected deployment.'
}
$accountTenant = & az account show --query tenantId --output tsv
if ($LASTEXITCODE -ne 0 -or $accountTenant -ne $tenantId) {
    throw 'Sign Azure CLI into the deployment tenant before configuring the credential.'
}

$graphToken = $null
$armToken = $null
$credential = $null
$tokenResponse = $null
$tokenBody = $null
$namedValueBody = $null
try {
    $graphToken = & az account get-access-token --tenant $tenantId `
        --resource https://graph.microsoft.com/ --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0) { throw 'Microsoft Graph authentication failed.' }
    $armToken = & az account get-access-token --subscription $subscriptionId `
        --resource https://management.azure.com/ --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0) { throw 'Azure management authentication failed.' }
    $graphHeaders = @{ Authorization = "Bearer $graphToken" }
    $armHeaders = @{ Authorization = "Bearer $armToken"; 'If-Match' = '*' }
    $applicationUrl = "https://graph.microsoft.com/v1.0/applications/$applicationId"
    $applicationResponse = Invoke-CheckedRequest -Operation 'Read application' `
        -Method GET -Uri $applicationUrl -Headers $graphHeaders
    $application = ConvertFrom-CheckedJson $applicationResponse.Content 'Read application'
    if ($application.appId -ne $clientId) {
        throw 'Application object ID and client ID do not match.'
    }

    $credentialName = 'sample-4-apim-backend'
    $previousCredentials = @($application.passwordCredentials |
        Where-Object { $_.displayName -eq $credentialName })
    $namedValueUri = "https://management.azure.com${namedValueId}?api-version=2024-05-01"
    $previousNamedValue = Invoke-CheckedRequest -Operation 'Read current credential metadata' `
        -Method GET -Uri $namedValueUri -Headers $armHeaders
    $previousMetadata = ConvertFrom-CheckedJson $previousNamedValue.Content 'Read current credential metadata'
    if (-not $previousMetadata.properties.secret) {
        throw 'The backend credential named value must be marked secret.'
    }
    $unexpiredCount = 0
    # Gateway propagation has no fleet-wide acknowledgement. Never automatically revoke an unexpired password.
    foreach ($previous in $previousCredentials) {
        if ([DateTimeOffset]$previous.endDateTime -gt [DateTimeOffset]::UtcNow) {
            $unexpiredCount++
            continue
        }
        $null = Invoke-CheckedRequest -Operation 'Remove an expired generated application credential' `
            -Method POST -Uri "$applicationUrl/removePassword" -Headers $graphHeaders `
            -Body @{ keyId = $previous.keyId } -ExpectedStatus @(204)
    }
    if ($unexpiredCount -gt 0) {
        Write-Warning "Retaining $unexpiredCount unexpired generated credential(s). Only expired credentials are removed automatically. Avoid repeated rotations; use the documented operator-controlled revocation process if directory credential limits are reached."
    }
    $expiresAt = [DateTimeOffset]::UtcNow.AddDays(30).ToString('o')
    $created = Invoke-CheckedRequest -Operation 'Create short-lived application credential (check directory permissions, password policy, and credential limits)' `
        -Method POST -Uri "$applicationUrl/addPassword" -Headers $graphHeaders `
        -Body @{ passwordCredential = @{ displayName = $credentialName; endDateTime = $expiresAt } }
    $credential = ConvertFrom-CheckedJson $created.Content 'Create application credential'
    $created = $null
    if ([string]::IsNullOrWhiteSpace($credential.secretText)) {
        throw 'Microsoft Graph did not return a client secret.'
    }

    $tokenBody = @{
        grant_type = 'client_credentials'
        client_id = $clientId
        client_secret = $credential.secretText
        scope = 'https://ai.azure.com/.default'
    }
    $tokenUri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $tokenResponse = Invoke-CheckedRequest -Operation 'Acquire application token' `
            -Method POST -Uri $tokenUri -Headers @{} -Body $tokenBody `
            -ContentType 'application/x-www-form-urlencoded' -ExpectedStatus @(200, 400, 401)
        if ([int]$tokenResponse.StatusCode -eq 200) { break }
        if ($attempt -lt 11) { Start-Sleep -Seconds 5 }
    }
    if ([int]$tokenResponse.StatusCode -ne 200) {
        throw "The new application credential could not acquire a Foundry token (HTTP $($tokenResponse.StatusCode))."
    }
    $issuedToken = ConvertFrom-CheckedJson $tokenResponse.Content 'Acquire application token'
    if ([string]::IsNullOrWhiteSpace($issuedToken.access_token)) {
        throw 'The token endpoint did not return an access token.'
    }
    $issuedToken = $null
    $tokenResponse = $null
    $tokenBody = $null

    $namedValueBody = @{
        properties = @{
            displayName = 'foundry-app-client-secret'
            secret = $true
            value = $credential.secretText
            tags = @('sample-4-app-credential', "credential-$($credential.keyId)", "expires-$($expiresAt.Substring(0, 10))")
        }
    }
    $null = Invoke-CheckedRequest -Operation 'Store the application credential in APIM' `
        -Method PUT -Uri $namedValueUri -Headers $armHeaders -Body $namedValueBody `
        -ExpectedStatus @(200, 201, 202)
    $namedValueBody = $null

    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $stateResponse = Invoke-CheckedRequest -Operation 'Read named value provisioning state' `
            -Method GET -Uri $namedValueUri -Headers $armHeaders
        $state = (ConvertFrom-CheckedJson $stateResponse.Content 'Read named value provisioning state').properties.provisioningState
        if ($state -eq 'Succeeded') { $ready = $true; break }
        if ($state -eq 'Failed') { throw 'APIM named value provisioning failed.' }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        throw 'Timed out waiting for APIM to store the credential. The new credential was retained for recovery.'
    }

    & azd env set ENTRA_APP_SECRET_EXPIRES_AT $expiresAt
    if ($LASTEXITCODE -ne 0) { throw 'Unable to save the non-secret credential expiry.' }
    Write-Host "Configured the APIM backend application credential. Expires: $expiresAt"
}
catch {
    if ($null -ne $credential) {
        Write-Warning 'Credential setup did not finish. The new credential was retained for recovery; rerun this hook and verify the gateway before treating it as ready.'
    }
    throw
}
finally {
    $graphToken = $null
    $armToken = $null
    $graphHeaders = $null
    $armHeaders = $null
    $credential = $null
    $tokenResponse = $null
    $tokenBody = $null
    $namedValueBody = $null
    $issuedToken = $null
    $created = $null
    $stateResponse = $null
    $previousNamedValue = $null
}
