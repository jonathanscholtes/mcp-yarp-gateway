param managedIdentityName string
param keyVaultName string

@description('User Object ID for secret read access')
param userObjectId string

@description('AKS Key Vault Secrets Provider identity object ID (optional)')
param aksKeyVaultSecretsProviderPrincipalId string = ''

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing= {
  name: managedIdentityName
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}



// Key Vault Secrets User role
var keyVaultSecretsUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

// Key Vault Secrets Officer role (allows set/delete in addition to read)
var keyVaultSecretsOfficerRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')

// Grant user Secrets Officer access so the deploying user can write secrets (e.g. proxy-api-key)
resource userSecretReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userObjectId)) {
  name: guid(keyVault.id, userObjectId, keyVaultSecretsOfficerRole)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRole
    principalId: userObjectId
    principalType: 'User'
  }
  dependsOn:[keyVault]
}


resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(managedIdentity.id, keyVault.id, 'key-vault-secrets-officer')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer role ID
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  scope:keyVault
  dependsOn:[keyVault]
}


resource roleUserAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(managedIdentity.id, keyVault.id, 'key-vault-secrets-user')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User role ID
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  scope:keyVault
  dependsOn:[keyVault]
}

// Grant AKS Key Vault Secrets Provider access to Key Vault
resource kvSecretsProviderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aksKeyVaultSecretsProviderPrincipalId)) {
  name: guid(keyVault.id, aksKeyVaultSecretsProviderPrincipalId, keyVaultSecretsUserRole)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole
    principalId: aksKeyVaultSecretsProviderPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output userRoleAssigned bool = !empty(userObjectId)
output userObjectIdReceived string = userObjectId
