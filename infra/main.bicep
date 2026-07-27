// ---------------------------------------------------------------------------
// main.bicep
// STAGE 2 (recurring, subscription scope): creates rg-hub / rg-spoke /
// rg-avd and deploys network, monitoring, AVD, and the budget into them.
// This is the file CI/CD (ci.yml what-if, deploy.yml) targets day to day.
// Run main.managementgroup.bicep at least once, against the target
// subscription, before this file — see README "Deployment order".
//
// Deploy with:
//   az deployment sub create \
//     --name azure-landing-zone \
//     --location <region> \
//     --template-file infra/main.bicep \
//     --parameters infra/params/dev.bicepparam
// ---------------------------------------------------------------------------
targetScope = 'subscription'

@description('Azure region for every resource this stage deploys.')
param location string = 'uksouth'

@description('Environment tag/suffix used for naming and tagging (e.g. dev, prod).')
param environmentName string = 'dev'

@description('Name of the hub resource group.')
param hubResourceGroupName string = 'rg-hub'

@description('Name of the spoke resource group.')
param spokeResourceGroupName string = 'rg-spoke'

@description('Name of the AVD resource group.')
param avdResourceGroupName string = 'rg-avd'

// --- Network ---
@description('Deploy Azure Bastion in the hub. Keep false outside of live demos.')
param deployBastion bool = false

@description('PLACEHOLDER — CIDR allowed to reach management ports on workload/AVD subnets. Set to your real admin source before relying on it.')
param trustedAdminSourceCidr string = '10.0.0.0/8'

// --- Monitoring ---
@description('Name of the central Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'log-portfolio-hub'

@description('Daily Log Analytics ingestion cap in GB.')
param logAnalyticsDailyQuotaGb int = 1

// --- AVD ---
@description('Local admin username for the session host VM (Entra join is used for interactive sign-in; this account is provisioning-only).')
param avdAdminUsername string = 'avdlocaladmin'

@secure()
@description('PLACEHOLDER — local admin password for the AVD session host. Supply via pipeline secret; never commit a real value.')
param avdAdminPassword string = ''

@description('VM size for the single AVD session host.')
param avdVmSize string = 'Standard_D2s_v5'

// --- Budget ---
@description('Monthly budget amount in USD.')
param budgetAmountUsd int = 30

@description('PLACEHOLDER — email address(es) that receive budget alerts.')
param budgetContactEmails array = [
  'CHANGE_ME@example.com'
]

@description('Tags applied to every resource this stage deploys.')
param tags object = {
  environment: environmentName
  project: 'azure-landing-zone'
  costCenter: 'engineering-portfolio'
}

resource rgHub 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: hubResourceGroupName
  location: location
  tags: tags
}

resource rgSpoke 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: spokeResourceGroupName
  location: location
  tags: tags
}

resource rgAvd 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: avdResourceGroupName
  location: location
  tags: tags
}

module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    hubResourceGroupName: hubResourceGroupName
    spokeResourceGroupName: spokeResourceGroupName
    location: location
    deployBastion: deployBastion
    trustedAdminSourceCidr: trustedAdminSourceCidr
    tags: tags
  }
  dependsOn: [
    rgHub
    rgSpoke
  ]
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    dailyQuotaGb: logAnalyticsDailyQuotaGb
    tags: tags
  }
  dependsOn: [
    rgHub
  ]
}

module avd 'modules/avd.bicep' = {
  name: 'deploy-avd'
  scope: resourceGroup(avdResourceGroupName)
  params: {
    location: location
    subnetResourceId: network.outputs.avdSubnetId
    adminUsername: avdAdminUsername
    adminPassword: avdAdminPassword
    vmSize: avdVmSize
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceResourceId
    dataCollectionRuleResourceId: monitoring.outputs.dataCollectionRuleResourceId
    tags: tags
  }
  dependsOn: [
    rgAvd
  ]
}

module budget 'modules/budget.bicep' = {
  name: 'deploy-budget'
  params: {
    amount: budgetAmountUsd
    contactEmails: budgetContactEmails
  }
}

output hubVnetId string = network.outputs.hubVnetId
output spokeVnetId string = network.outputs.spokeVnetId
output logAnalyticsWorkspaceResourceId string = monitoring.outputs.logAnalyticsWorkspaceResourceId
output hostPoolId string = avd.outputs.hostPoolId
output budgetId string = budget.outputs.budgetId
