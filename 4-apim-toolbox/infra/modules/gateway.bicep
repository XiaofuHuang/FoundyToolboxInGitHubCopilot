extension microsoftGraphV1

targetScope = 'resourceGroup'

param apimName string
param apimOrigin string
param mcpAppUniqueName string
param mcpScope string
param mcpUrl string
param tenantId string
param toolboxUrl string

resource apim 'Microsoft.ApiManagement/service@2025-09-01-preview' existing = {
  name: apimName
}

resource mcpApp 'Microsoft.Graph/applications@v1.0' existing = {
  uniqueName: mcpAppUniqueName
}

resource toolboxApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'foundry-toolbox'
  properties: {
    displayName: 'Microsoft Foundry Toolbox'
    apiRevision: '1'
    subscriptionRequired: false
    serviceUrl: toolboxUrl
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
}

resource toolboxPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: toolboxApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(
      replace(
        replace(
          replace(
            loadTextContent('../policies/toolbox-policy.xml'),
            '__TENANT_ID__',
            tenantId
          ),
          '__MCP_APP_ID__',
          mcpApp.appId
        ),
        '__TOOLBOX_MCP_URL__',
        '${toolboxUrl}/mcp?api-version=v1'
      ),
      '__MCP_RESOURCE__',
      mcpUrl
    )
  }
}

resource metadataApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'oauth-authorization-server-metadata'
  properties: {
    displayName: 'OAuth Metadata'
    apiRevision: '1'
    subscriptionRequired: false
    path: '.well-known'
    protocols: [
      'https'
    ]
  }
}

resource protectedResourceOperation 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: metadataApi
  name: 'protected-resource'
  properties: {
    displayName: 'OAuth Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/oauth-protected-resource/toolbox/mcp'
  }
}

resource protectedResourcePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: protectedResourceOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(
      replace(
        replace(
          replace(
            loadTextContent('../policies/oauth-metadata-policy.xml'),
            '__TENANT_ID__',
            tenantId
          ),
          '__MCP_URL__',
          mcpUrl
        ),
        '__APIM_ORIGIN__',
        apimOrigin
      ),
      '__MCP_SCOPE__',
      mcpScope
    )
  }
}

resource authorizationServerOperation 'Microsoft.ApiManagement/service/apis/operations@2025-09-01-preview' = {
  parent: metadataApi
  name: 'oauth-authorization-server'
  properties: {
    displayName: 'OAuth Authorization Server Metadata'
    method: 'GET'
    urlTemplate: '/oauth-authorization-server'
  }
}

resource authorizationServerPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2025-09-01-preview' = {
  parent: authorizationServerOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: replace(
      replace(
        replace(
          loadTextContent('../policies/authorization-server-metadata-policy.xml'),
          '__TENANT_ID__',
          tenantId
        ),
        '__APIM_ORIGIN__',
        apimOrigin
      ),
      '__MCP_SCOPE__',
      mcpScope
    )
  }
}
