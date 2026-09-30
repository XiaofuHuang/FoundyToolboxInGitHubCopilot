extension microsoftGraphV1

targetScope = 'resourceGroup'

@description('Globally unique name for a new API Management instance.')
param apimName string

param publisherName string
param publisherEmail string
param foundryResourceGroupName string
param foundryAccountName string
param foundryProjectName string

var resourceSuffix = uniqueString(subscription().id, resourceGroup().id)
var toolboxMcpUrl = 'https://${foundryAccountName}.services.ai.azure.com/api/projects/${foundryProjectName}/toolboxes/tools/mcp?api-version=v1'

resource backendApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'foundry-toolbox-backend-${resourceSuffix}'
  displayName: 'Foundry Toolbox Backend ${resourceSuffix}'
  signInAudience: 'AzureADMyOrg'
  isFallbackPublicClient: false
}

resource backendPrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: backendApp.appId
}

resource apim 'Microsoft.ApiManagement/service@2025-09-01-preview' = {
  name: apimName
  location: resourceGroup().location
  identity: {
    type: 'None'
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

module foundryAccess 'modules/foundry-access.bicep' = {
  name: 'app-foundry-access'
  scope: resourceGroup(foundryResourceGroupName)
  params: {
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    principalId: backendPrincipal.id
  }
}

resource appSecret 'Microsoft.ApiManagement/service/namedValues@2025-09-01-preview' = {
  parent: apim
  name: 'foundry-app-client-secret'
  properties: {
    displayName: 'foundry-app-client-secret'
    secret: true
    // The postprovision hook installs the real secret without putting it in deployment parameters.
    value: 'UNCONFIGURED'
    tags: [
      'sample-4-app-credential'
    ]
  }
}

resource toolboxApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'foundry-toolbox'
  properties: {
    displayName: 'Foundry Toolbox - API key and Entra application'
    apiRevision: '1'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    serviceUrl: 'https://${foundryAccountName}.services.ai.azure.com'
    path: 'toolbox'
    protocols: [
      'https'
    ]
    type: 'mcp'
    mcpProperties: {
      transportType: 'streamable'
      endpoints: {
        message: {
          uriTemplate: '/mcp'
        }
      }
    }
  }
  dependsOn: [
    foundryAccess
  ]
}

resource toolboxPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: toolboxApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(
      replace(
        replace(
          loadTextContent('policies/toolbox-policy.xml'),
          '__TENANT_ID__',
          tenant().tenantId
        ),
        '__APP_CLIENT_ID__',
        backendApp.appId
      ),
      '__TOOLBOX_MCP_URL__',
      toolboxMcpUrl
    )
  }
  dependsOn: [
    appSecret
  ]
}

resource clientSubscription 'Microsoft.ApiManagement/service/subscriptions@2025-09-01-preview' = {
  parent: apim
  name: 'toolbox-client'
  properties: {
    displayName: 'Foundry Toolbox Entra app client'
    scope: toolboxApi.id
    state: 'active'
    allowTracing: false
  }
}

output APIM_TOOLBOX_MCP_URL string = 'https://${apimName}.azure-api.net/toolbox/mcp'
output APIM_TOOLBOX_SUBSCRIPTION_ID string = clientSubscription.id
output APIM_APP_SECRET_NAMED_VALUE_ID string = appSecret.id
output APIM_FOUNDRY_ROLE_ASSIGNMENT_ID string = foundryAccess.outputs.roleAssignmentId
output ENTRA_APP_CLIENT_ID string = backendApp.appId
output ENTRA_APP_OBJECT_ID string = backendApp.id
output ENTRA_SERVICE_PRINCIPAL_OBJECT_ID string = backendPrincipal.id
output ENTRA_TENANT_ID string = tenant().tenantId
