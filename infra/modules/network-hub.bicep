// ---------------------------------------------------------------------------
// network-hub.bicep
// Hub NSGs, vnet-hub, and optional Bastion. Resource-group scoped — deployed
// into rg-hub by network.bicep with an explicit `scope:` override. Peering
// is created separately by network-peering.bicep once both hub and spoke
// vnets exist, to avoid a circular hub<->spoke output dependency.
// ---------------------------------------------------------------------------

@description('Azure region for hub network resources.')
param location string

@description('Address space for vnet-hub.')
param hubVnetAddressPrefix string = '10.0.0.0/22'

@description('AzureBastionSubnet prefix. Must be /26 or larger per Azure Bastion requirements.')
param bastionSubnetPrefix string = '10.0.0.0/26'

@description('Subnet prefix for shared services in the hub.')
param sharedServicesSubnetPrefix string = '10.0.1.0/24'

@description('Deploy Azure Bastion in the hub.')
param deployBastion bool = false

@description('PLACEHOLDER — CIDR allowed to reach management ports on hub resources. Defaults to 192.0.2.0/24 (TEST-NET-1, RFC 5737) — genuinely non-routable, unlike a real RFC1918 range.')
param trustedAdminSourceCidr string = '192.0.2.0/24'

@description('PLACEHOLDER — resource ID of the central Log Analytics workspace (monitoring.bicep output). Leave empty to skip the diagnostic setting below.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Tags applied to hub network resources.')
param tags object = {}

resource nsgSharedServices 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-hub-shared-services'
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
          destinationPortRanges: [
            '3389'
            '22'
          ]
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

// Required rule set for AzureBastionSubnet — see
// https://learn.microsoft.com/azure/bastion/bastion-nsg
resource nsgBastion 'Microsoft.Network/networkSecurityGroups@2023-05-01' = if (deployBastion) {
  name: 'nsg-hub-bastion'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Https-Inbound-Internet'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-GatewayManager-Inbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 140
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-BastionHostComms-Inbound'
        properties: {
          priority: 150
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
        }
      }
      {
        name: 'Allow-SshRdp-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '3389'
            '22'
          ]
        }
      }
      {
        name: 'Allow-AzureCloud-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-BastionHostComms-Outbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
        }
      }
      {
        name: 'Allow-GetSessionInformation-Outbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

resource vnetHub 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-hub'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressPrefix
      ]
    }
    subnets: concat(
      [
        {
          name: 'snet-shared-services'
          properties: {
            addressPrefix: sharedServicesSubnetPrefix
            networkSecurityGroup: {
              id: nsgSharedServices.id
            }
          }
        }
      ],
      deployBastion
        ? [
            {
              name: 'AzureBastionSubnet'
              properties: {
                addressPrefix: bastionSubnetPrefix
                networkSecurityGroup: {
                  id: nsgBastion.id
                }
              }
            }
          ]
        : []
    )
  }
}

// Worked example of a direct (non-policy) diagnostic setting: routes
// vnet-hub's platform metrics to the central Log Analytics workspace.
// Complements (does not replace) the NSG-diagnostics DeployIfNotExists
// policy in modules/policy.bicep, which handles NSGs tenant/mg-wide —
// virtual networks themselves only expose metrics (no resource log
// categories), so that's what this setting routes. Skipped when no
// workspace ID is supplied (e.g. before monitoring.bicep has run once).
resource vnetHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: 'diag-vnet-hub-to-la'
  scope: vnetHub
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource publicIpBastion 'Microsoft.Network/publicIPAddresses@2023-05-01' = if (deployBastion) {
  name: 'pip-bastion-hub'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-05-01' = if (deployBastion) {
  name: 'bas-hub'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnetHub.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: publicIpBastion.id
          }
        }
      }
    ]
  }
}

output vnetId string = vnetHub.id
output vnetName string = vnetHub.name
output sharedServicesSubnetId string = '${vnetHub.id}/subnets/snet-shared-services'
