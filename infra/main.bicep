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

@description('PLACEHOLDER — CIDR allowed to reach management ports on workload/AVD subnets. Defaults to 192.0.2.0/24 (TEST-NET-1, RFC 5737) — genuinely non-routable, unlike a real RFC1918 range. Set to your real admin source before relying on it.')
param trustedAdminSourceCidr string = '192.0.2.0/24'

@description('Address space for vnet-hub.')
param hubVnetAddressPrefix string = '10.0.0.0/22'

@description('AzureBastionSubnet prefix. Must be /26 or larger per Azure Bastion requirements.')
param bastionSubnetPrefix string = '10.0.0.0/26'

@description('Subnet prefix for shared services in the hub.')
param sharedServicesSubnetPrefix string = '10.0.1.0/24'

@description('Address space for vnet-spoke.')
param spokeVnetAddressPrefix string = '10.1.0.0/22'

@description('Subnet prefix for general workloads in the spoke.')
param workloadSubnetPrefix string = '10.1.0.0/24'

@description('Subnet prefix for AVD session hosts in the spoke.')
param avdSubnetPrefix string = '10.1.1.0/24'

// --- Monitoring ---
@description('Name of the central Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'log-portfolio-hub'

@description('Daily Log Analytics ingestion cap in GB.')
param logAnalyticsDailyQuotaGb int = 1

// --- AVD ---
@description('Local admin username for the session host VM (Entra join is used for interactive sign-in; this account is provisioning-only).')
param avdAdminUsername string = 'avdlocaladmin'

@secure()
@minLength(12)
@description('REQUIRED — local admin password for the AVD session host. Supply via pipeline secret; never commit a real value. No default: dev.bicepparam/prod.bicepparam source this from the AVD_LOCAL_ADMIN_PASSWORD environment variable (readEnvironmentVariable, with an inert placeholder fallback so build-params stays clean without it) and CI additionally overrides it explicitly on the what-if/deploy command line.')
param avdAdminPassword string

@description('VM size for the single AVD session host.')
param avdVmSize string = 'Standard_D2s_v5'

@description('Name of the pooled AVD host pool.')
param avdHostPoolName string = 'hp-portfolio-pooled'

@description('Max sessions per AVD session host (pooled, breadth-first).')
param avdMaxSessionLimit int = 4

@description('24h HHmm time (in avdAutoShutdownTimeZoneId) the AVD session host is deallocated every day.')
param avdAutoShutdownTimeUtc string = '1900'

@description('Time zone ID for the AVD session host auto-shutdown schedule.')
param avdAutoShutdownTimeZoneId string = 'UTC'

@description('PLACEHOLDER — object ID of the Azure Virtual Desktop resource provider service principal (enterprise application "Azure Virtual Desktop") in this tenant. Tenant-specific — see README "Placeholders you must supply" for how to look it up. Required for startVMOnConnect to actually be able to power on a deallocated session host (grants Desktop Virtualization Power On Contributor at subscription scope). Leave empty to skip that role assignment until the value is known.')
param avdServicePrincipalObjectId string = ''

// --- Budget ---
@description('Monthly budget amount in USD.')
param budgetAmountUsd int = 30

@description('PLACEHOLDER — email address(es) that receive budget alerts.')
param budgetContactEmails array = [
  'CHANGE_ME@example.com'
]

@description('Override for the budget name. Leave empty to use the default budget-portfolio-landingzone-<environmentName> (keeps dev/prod from colliding at subscription scope).')
param budgetNameOverride string = ''

@description('REQUIRED — first day of the month the budget starts tracking from (yyyy-MM-01), e.g. 2026-07-01. No default on purpose — see budget.bicep for why a utcNow()-derived default breaks idempotency. Set explicitly in dev.bicepparam/prod.bicepparam.')
param budgetStartDate string

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

module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    hubResourceGroupName: hubResourceGroupName
    spokeResourceGroupName: spokeResourceGroupName
    location: location
    deployBastion: deployBastion
    trustedAdminSourceCidr: trustedAdminSourceCidr
    hubVnetAddressPrefix: hubVnetAddressPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    sharedServicesSubnetPrefix: sharedServicesSubnetPrefix
    spokeVnetAddressPrefix: spokeVnetAddressPrefix
    workloadSubnetPrefix: workloadSubnetPrefix
    avdSubnetPrefix: avdSubnetPrefix
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceResourceId
    tags: tags
  }
  dependsOn: [
    rgHub
    rgSpoke
  ]
}

module avd 'modules/avd.bicep' = {
  name: 'deploy-avd'
  scope: resourceGroup(avdResourceGroupName)
  params: {
    location: location
    hostPoolName: avdHostPoolName
    maxSessionLimit: avdMaxSessionLimit
    subnetResourceId: network.outputs.avdSubnetId
    adminUsername: avdAdminUsername
    adminPassword: avdAdminPassword
    vmSize: avdVmSize
    autoShutdownTimeUtc: avdAutoShutdownTimeUtc
    autoShutdownTimeZoneId: avdAutoShutdownTimeZoneId
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceResourceId
    dataCollectionRuleResourceId: monitoring.outputs.dataCollectionRuleResourceId
    tags: tags
  }
  dependsOn: [
    rgAvd
  ]
}

// startVMOnConnect (avd.bicep host pool) needs the AVD resource provider's
// service principal to hold Desktop Virtualization Power On Contributor at
// subscription scope — see modules/avd-startvm-roleassignment.bicep. Skips
// entirely (no-op) until avdServicePrincipalObjectId is filled in.
module avdStartVmRoleAssignment 'modules/avd-startvm-roleassignment.bicep' = if (!empty(avdServicePrincipalObjectId)) {
  name: 'deploy-avd-startvm-roleassignment'
  params: {
    avdServicePrincipalObjectId: avdServicePrincipalObjectId
  }
}

module budget 'modules/budget.bicep' = {
  name: 'deploy-budget'
  params: {
    environmentName: environmentName
    budgetName: empty(budgetNameOverride) ? 'budget-portfolio-landingzone-${environmentName}' : budgetNameOverride
    amount: budgetAmountUsd
    startDate: budgetStartDate
    contactEmails: budgetContactEmails
  }
}

output hubVnetId string = network.outputs.hubVnetId
output spokeVnetId string = network.outputs.spokeVnetId
output logAnalyticsWorkspaceResourceId string = monitoring.outputs.logAnalyticsWorkspaceResourceId
output hostPoolId string = avd.outputs.hostPoolId
output budgetId string = budget.outputs.budgetId
