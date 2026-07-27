// ---------------------------------------------------------------------------
// network-peering.bicep
// Generic one-directional vnet peering, deployed into the resource group
// that owns the *local* vnet. network.bicep calls this twice (hub->spoke,
// scoped to rg-hub; spoke->hub, scoped to rg-spoke) after both vnets exist,
// which avoids a circular output dependency between the hub and spoke
// network modules.
// ---------------------------------------------------------------------------

@description('Name of the vnet in this resource group that the peering is attached to.')
param localVnetName string

@description('Resource ID of the remote vnet being peered to.')
param remoteVnetId string

@description('Name of the peering resource.')
param peeringName string

@description('Allow gateway transit from this vnet to the remote vnet. Keep false — no gateway is deployed in v1.')
param allowGatewayTransit bool = false

@description('Use the remote vnet\'s gateway for transit. Keep false — no gateway is deployed in v1.')
param useRemoteGateways bool = false

resource localVnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: localVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  parent: localVnet
  name: peeringName
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
  }
}

output peeringId string = peering.id
