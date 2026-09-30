targetScope = 'resourceGroup'

@description('Globally unique API Management service name.')
param apimName string

@description('Organization name shown by API Management.')
param publisherName string

@description('Administrator email used by API Management.')
param publisherEmail string

@description('Resource group containing the provisioned Foundry account and project.')
param foundryResourceGroupName string

@description('Microsoft Foundry account name.')
param foundryAccountName string

@description('Microsoft Foundry project name.')
param foundryProjectName string

var foundryOrigin = 'https://${foundryAccountName}.services.ai.azure.com'
var toolboxPath = '/api/projects/${foundryProjectName}/toolboxes/tools/mcp'
var mcpUrl = 'https://${apimName}.azure-api.net/toolbox/mcp'

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

module foundryAccess 'modules/foundry-access.bicep' = {
  name: 'apim-foundry-access'
  scope: resourceGroup(foundryResourceGroupName)
  params: {
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    principalId: apim.identity.principalId
  }
}

resource toolboxApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'foundry-toolbox'
  properties: {
    displayName: 'Foundry Toolbox - API key and managed identity'
    apiRevision: '1'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    serviceUrl: foundryOrigin
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
        loadTextContent('policies/toolbox-policy.xml'),
        '__FOUNDRY_ORIGIN__',
        foundryOrigin
      ),
      '__TOOLBOX_PATH__',
      toolboxPath
    )
  }
}

resource clientSubscription 'Microsoft.ApiManagement/service/subscriptions@2025-09-01-preview' = {
  parent: apim
  name: 'toolbox-client'
  properties: {
    displayName: 'Foundry Toolbox MCP client'
    scope: toolboxApi.id
    state: 'active'
    allowTracing: false
  }
}

output APIM_TOOLBOX_MCP_URL string = mcpUrl
output APIM_MANAGED_IDENTITY_PRINCIPAL_ID string = apim.identity.principalId
output APIM_TOOLBOX_SUBSCRIPTION_ID string = clientSubscription.id
output APIM_TOOLBOX_SUBSCRIPTION_NAME string = clientSubscription.name
output APIM_FOUNDRY_ROLE_ASSIGNMENT_ID string = foundryAccess.outputs.roleAssignmentId
