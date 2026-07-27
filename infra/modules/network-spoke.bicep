// ---------------------------------------------------------------------------
// network-spoke.bicep
// Spoke NSGs and vnet-spoke (workload + AVD subnets). Resource-group scoped
// — deployed into rg-spoke by network.bicep with an explicit `scope:`
// override. Peering is created separately by network-peering.bicep.
// ---------------------------------------------------------------------------

@description('Azure region for spoke network resources.')
param location string

@description('Address space for vnet-spoke.')
param spokeVnetAddressPrefix string = '10.1.0.0/22'

@description('Subnet prefix for general workloads in the spoke.')
param workloadSubnetPrefix string = '10.1.0.0/24'

@description('Subnet prefix for AVD session hosts in the spoke.')
param avdSubnetPrefix string = '10.1.1.0/24'

@description('PLACEHOLDER — CIDR allowed to reach management ports on spoke resources. Defaults to 192.0.2.0/24 (TEST-NET-1, RFC 5737) — genuinely non-routable, unlike a real RFC1918 range.')
param trustedAdminSourceCidr string = '192.0.2.0/24'

@description('Tags applied to spoke network resources.')
param tags object = {}

resource nsgWorkload 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-spoke-workload'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource nsgAvd 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-spoke-avd'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Mgmt-From-Trusted'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: trustedAdminSourceCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnetSpoke 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-spoke'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: nsgWorkload.id
          }
        }
      }
      {
        name: 'snet-avd'
        properties: {
          addressPrefix: avdSubnetPrefix
          networkSecurityGroup: {
            id: nsgAvd.id
          }
        }
      }
    ]
  }
}

output vnetId string = vnetSpoke.id
output vnetName string = vnetSpoke.name
output avdSubnetId string = '${vnetSpoke.id}/subnets/snet-avd'
output workloadSubnetId string = '${vnetSpoke.id}/subnets/snet-workload'
