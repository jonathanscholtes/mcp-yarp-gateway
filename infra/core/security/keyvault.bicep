param location string
param keyVaultName string

@description('MongoDB admin username')
param mongoDbUsername string = 'mongoadmin'

@secure()
@description('MongoDB admin password')
param mongoDbPassword string

@secure()
@description('MongoDB connection string')
param mongoDbConnectionString string

@secure()
@description('API key for the YARP proxy')
param proxyApiKey string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    createMode: 'default'
    publicNetworkAccess: 'enabled'
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: false
    enableRbacAuthorization: true
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
  }
}

// Store MongoDB credentials
resource mongoDbUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'mongodb-username'
  properties: {
    value: mongoDbUsername
  }
}

resource mongoDbPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'mongodb-password'
  properties: {
    value: mongoDbPassword
  }
}

resource mongoDbConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'mongodb-connection-string'
  properties: {
    value: mongoDbConnectionString
  }
}

resource proxyApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'proxy-api-key'
  properties: {
    value: proxyApiKey
  }
}

output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVaultName
