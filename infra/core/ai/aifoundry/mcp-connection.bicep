@description('Name of the existing AI Foundry CognitiveServices account')
param accountName string

@description('Display name for the MCP tool connection')
param connectionName string = 'yarp-proxy-mcp'

@description('Target URL of the MCP proxy (e.g. http://<ip>/mcp)')
param mcpProxyUrl string

@secure()
@description('API key for authenticating to the MCP proxy')
param mcpApiKey string

resource account 'Microsoft.CognitiveServices/accounts@2025-09-01' existing = {
  name: accountName
}

resource mcpConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: account
  name: connectionName
  properties: {
    category: 'RemoteTool'
    target: mcpProxyUrl
    authType: 'CustomKeys'
    isSharedToAll: true
    credentials: any({
      type: 'CustomKeys'
      keys: {
        'api-key': mcpApiKey
      }
    })
    metadata: {
      type: 'custom_MCP'
    }
  }
}
