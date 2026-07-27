// ---------------------------------------------------------------------------
// network.bicep
// Hub-spoke network orchestrator: deploys vnet-hub (network-hub.bicep) and
// vnet-spoke (network-spoke.bicep) into their respective resource groups,
// then peers them bidirectionally (network-peering.bicep). Deployed at
// subscription scope because it fans out into two different resource
// groups (rg-hub, rg-spoke) that main.bicep creates just before calling it.
//
// Direct (non-module) resources cannot use a `scope:` override in Bicep —
// only `module` blocks can — which is why the hub/spoke resources live in
// their own resource-group-scoped module files rather than inline here.
// ---------------------------------------------------------------------------
targetScope = 'subscription'

@description('Name of the existing/just-created resource group that holds the hub network.')
param hubResourceGroupName string

@description('Name of the existing/just-created resource group that holds the spoke network.')
param spokeResourceGroupName string

@description('Azure region for all network resources.')
param location string

@description('Address space for vnet-hub.')
param hubVnetAddressPrefix string = '10.0.0.0/22'

@description('AzureBastionSubnet prefix. Must be /26 or larger per Azure Bastion requirements.')
param bastionSubnetPrefix string = '10.0.0.0/26'

@description('Subnet prefix for shared services in the hub (e.g. future DNS resolvers, jumpboxes).')
param sharedServicesSubnetPrefix string = '10.0.1.0/24'

@description('Address space for vnet-spoke.')
param spokeVnetAddressPrefix string = '10.1.0.0/22'

@description('Subnet prefix for general workloads in the spoke.')
param workloadSubnetPrefix string = '10.1.0.0/24'

@description('Subnet prefix for AVD session hosts in the spoke.')
param avdSubnetPrefix string = '10.1.1.0/24'

@description('Deploy Azure Bastion in the hub. Keep false by default to control cost; flip to true only while demoing interactive access.')
param deployBastion bool = false

@description('PLACEHOLDER: CIDR allowed to reach management ports (RDP/SSH) on workload/AVD subnets, e.g. your own public IP as x.x.x.x/32. Left as a private RFC1918 range by default so the rule is inert until you scope it down to something real — never leave this as 0.0.0.0/0.')
param trustedAdminSourceCidr string = '10.0.0.0/8'

@description('Tags applied to every network resource.')
param tags object = {}

module hubNetwork 'network-hub.bicep' = {
  name: 'deploy-network-hub'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    location: location
    hubVnetAddressPrefix: hubVnetAddressPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    sharedServicesSubnetPrefix: sharedServicesSubnetPrefix
    deployBastion: deployBastion
    trustedAdminSourceCidr: trustedAdminSourceCidr
    tags: tags
  }
}

module spokeNetwork 'network-spoke.bicep' = {
  name: 'deploy-network-spoke'
  scope: resourceGroup(spokeResourceGroupName)
  params: {
    location: location
    spokeVnetAddressPrefix: spokeVnetAddressPrefix
    workloadSubnetPrefix: workloadSubnetPrefix
    avdSubnetPrefix: avdSubnetPrefix
    trustedAdminSourceCidr: trustedAdminSourceCidr
    tags: tags
  }
}

module hubToSpokePeering 'network-peering.bicep' = {
  name: 'deploy-peering-hub-to-spoke'
  scope: resourceGroup(hubResourceGroupName)
  params: {
    localVnetName: hubNetwork.outputs.vnetName
    remoteVnetId: spokeNetwork.outputs.vnetId
    peeringName: 'hub-to-spoke'
  }
}

module spokeToHubPeering 'network-peering.bicep' = {
  name: 'deploy-peering-spoke-to-hub'
  scope: resourceGroup(spokeResourceGroupName)
  params: {
    localVnetName: spokeNetwork.outputs.vnetName
    remoteVnetId: hubNetwork.outputs.vnetId
    peeringName: 'spoke-to-hub'
  }
}

output hubVnetId string = hubNetwork.outputs.vnetId
output spokeVnetId string = spokeNetwork.outputs.vnetId
output avdSubnetId string = spokeNetwork.outputs.avdSubnetId
output workloadSubnetId string = spokeNetwork.outputs.workloadSubnetId
