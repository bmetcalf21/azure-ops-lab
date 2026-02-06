// Azure Operations Lab - Infrastructure as Code
// Author: Brandon Metcalf
// Project: azure-ops-lab

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment tag value')
param environmentTag string = 'lab'

@description('Owner tag value')
param ownerTag string = 'brandon-metcalf'

@description('Project tag value')
param projectTag string = 'azure-ops-lab'

@description('App Service Plan SKU')
param appServicePlanSku string = 'F1'

@description('Python runtime version')
param pythonVersion string = '3.11'

// Variables for resource naming
var uniqueSuffix = uniqueString(resourceGroup().id)
var appServicePlanName = 'asp-${projectTag}-${uniqueSuffix}'
var webAppName = 'app-${projectTag}-${uniqueSuffix}'
var storageAccountName = take('st${replace(projectTag, '-', '')}${uniqueSuffix}', 24)
var appInsightsName = 'appi-${projectTag}-${uniqueSuffix}'
var logAnalyticsName = 'log-${projectTag}-${uniqueSuffix}'

// Common tags applied to all resources
var commonTags = {
  environment: environmentTag
  owner: ownerTag
  project: projectTag
}

// Log Analytics Workspace - required for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights - for monitoring and telemetry
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
  }
}

// App Service Plan - F1 Free Tier
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: appServicePlanSku
    tier: 'Free'
    size: appServicePlanSku
    family: 'F'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux
  }
}

// Web App - Python application
resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  tags: commonTags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      alwaysOn: false // Not available in F1 tier
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Storage Account - for blob/table/queue storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Role Assignment - Contributor role for demonstration of RBAC
// In production, this would be assigned to a specific service principal or user
// For lab purposes, we assign it to the Web App's managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, webApp.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for reference and automation
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output storageAccountName string = storageAccount.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output webAppPrincipalId string = webApp.identity.principalId
