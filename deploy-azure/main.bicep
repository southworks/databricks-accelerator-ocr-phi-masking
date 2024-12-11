param databricksResourceName string = 'pandora-dbw'

var deploymentId = guid(resourceGroup().id)
var deploymentIdShort = substring(deploymentId, 0, 8)

var acceleratorRepoName = 'databricks-accelerator-ocr-phi-masking'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'dbw-id-${deploymentIdShort}'
  location: resourceGroup().location
}

resource databricks 'Microsoft.Databricks/workspaces@2024-09-01-preview' existing = {
  name: databricksResourceName
}

resource databricksRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, 'Contributor')
  scope: databricks
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    )
    principalId: managedIdentity.properties.principalId
    // principalType: 'ServicePrincipal'
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'setup-databricks-script'
  location: resourceGroup().location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.9.1'
    scriptContent: '''
      cd ~
      curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
      databricks repos create https://github.com/southworks/${ACCELERATOR_REPO_NAME} gitHub
      databricks workspace export /Users/${ARM_CLIENT_ID}/${ACCELERATOR_REPO_NAME}/deploy-azure/job-template.json > job-template.json
      notebook_path="/Users/${ARM_CLIENT_ID}/${ACCELERATOR_REPO_NAME}/RUNME"
      jq ".tasks[0].notebook_task.notebook_path = \"${notebook_path}\"" job-template.json > job.json
      databricks jobs submit --json @./job.json
    '''
    environmentVariables: [
      {
        name: 'DATABRICKS_AZURE_RESOURCE_ID'
        value: databricks.id
      }
      {
        name: 'ARM_CLIENT_ID'
        value: managedIdentity.properties.clientId
      }
      {
        name: 'ARM_USE_MSI'
        value: 'true'
      }
      {
        name: 'ACCELERATOR_REPO_NAME'
        value: acceleratorRepoName
      }
    ]
    timeout: 'PT20M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  dependsOn: [
    databricksRoleAssignment
  ]
}
