extension microsoftGraphV1

targetScope = 'resourceGroup'

@description('Globally unique API Management service name.')
param apimName string

@description('Organization name shown by API Management.')
param publisherName string

@description('Administrator email used by API Management.')
param publisherEmail string

@description('Microsoft Foundry account name.')
param foundryAccountName string

@description('Microsoft Foundry project name.')
param foundryProjectName string

var resourceSuffix = uniqueString(subscription().id, resourceGroup().id)
var apimOrigin = 'https://${apimName}.azure-api.net'
var mcpUrl = '${apimOrigin}/toolbox/mcp'
var mcpScopeId = guid(subscription().id, resourceGroup().id, 'toolbox-mcp-user-impersonate')
var mcpScope = '${mcpUrl}/user_impersonate'
var clientAppUniqueName = 'foundry-toolbox-vscode-${resourceSuffix}'
var toolboxUrl = 'https://${foundryAccountName}.services.ai.azure.com/api/projects/${foundryProjectName}/toolboxes/tools'
var azureMachineLearningAppId = '18a66f5f-dbdf-4c17-9dd7-1634712a9cbe'
var azureMachineLearningUserImpersonationScopeId = '1a7925b5-f871-417a-9b8b-303f9f29fa10'

resource apim 'Microsoft.ApiManagement/service@2025-09-01-preview' = {
  name: apimName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

resource clientApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: clientAppUniqueName
  displayName: 'Foundry Toolbox Client ${resourceSuffix}'
  signInAudience: 'AzureADMyOrg'
  isFallbackPublicClient: true
  identifierUris: [
    mcpUrl
  ]
  publicClient: {
    redirectUris: [
      'http://127.0.0.1:33418/'
      'https://vscode.dev/redirect'
    ]
  }
  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: [
      {
        id: mcpScopeId
        adminConsentDescription: 'Access the Foundry toolbox through API Management on behalf of the signed-in user.'
        adminConsentDisplayName: 'Access the Foundry toolbox'
        isEnabled: true
        type: 'User'
        userConsentDescription: 'Access the Foundry toolbox on your behalf.'
        userConsentDisplayName: 'Access the Foundry toolbox'
        value: 'user_impersonate'
      }
    ]
  }
  requiredResourceAccess: [
    {
      resourceAppId: azureMachineLearningAppId
      resourceAccess: [
        {
          id: azureMachineLearningUserImpersonationScopeId
          type: 'Scope'
        }
      ]
    }
  ]

  resource apimFederatedCredential 'federatedIdentityCredentials@v1.0' = {
    name: '${clientApp.uniqueName}/apim-managed-identity'
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
    subject: apim.identity.principalId
  }
}

resource clientServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: clientApp.appId
}

resource azureMachineLearningServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: azureMachineLearningAppId
}

resource foundryConsent 'Microsoft.Graph/oauth2PermissionGrants@v1.0' = {
  clientId: clientServicePrincipal.id
  consentType: 'AllPrincipals'
  resourceId: azureMachineLearningServicePrincipal.id
  scope: 'user_impersonation'
}

resource mcpConsent 'Microsoft.Graph/oauth2PermissionGrants@v1.0' = {
  clientId: clientServicePrincipal.id
  consentType: 'AllPrincipals'
  resourceId: clientServicePrincipal.id
  scope: 'user_impersonate'
}

module gateway 'modules/gateway.bicep' = {
  name: 'gateway'
  params: {
    apimName: apim.name
    apimOrigin: apimOrigin
    mcpAppUniqueName: clientAppUniqueName
    mcpScope: mcpScope
    mcpUrl: mcpUrl
    tenantId: tenant().tenantId
    toolboxUrl: toolboxUrl
  }
  dependsOn: [
    foundryConsent
  ]
}

output APIM_TOOLBOX_MCP_URL string = mcpUrl
output MCP_COPILOT_CLIENT_ID string = clientApp.appId
output MCP_COPILOT_APP_OBJECT_ID string = clientApp.id
output MCP_COPILOT_SERVICE_PRINCIPAL_OBJECT_ID string = clientServicePrincipal.id
