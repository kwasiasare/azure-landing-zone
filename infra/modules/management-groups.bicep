// ---------------------------------------------------------------------------
// management-groups.bicep
// Creates the mg-portfolio management group under an existing parent
// (normally the Tenant Root Group) and, optionally, places a subscription
// under it. Deploy at tenant scope: `az deployment tenant create`.
// ---------------------------------------------------------------------------
targetScope = 'tenant'

@description('ID of the parent management group. Defaults to the tenant ID, which is the ID of the built-in Tenant Root Group. Override if mg-portfolio should hang off an existing mg-platform/mg-landingzones structure instead.')
param parentManagementGroupId string = tenant().tenantId

@description('ID (name) of the management group this project creates. Must be unique within the tenant.')
param portfolioManagementGroupId string = 'mg-portfolio'

@description('Display name for the portfolio management group.')
param portfolioManagementGroupDisplayName string = 'Engineering Portfolio'

@description('PLACEHOLDER: subscription ID (GUID) to place under mg-portfolio. Leave empty to skip subscription placement (e.g. on first apply before the subscription is chosen). Fill in via bicepparam once the target subscription is confirmed.')
param subscriptionIdToPlace string = ''

resource mgPortfolio 'Microsoft.Management/managementGroups@2021-04-01' = {
  name: portfolioManagementGroupId
  properties: {
    displayName: portfolioManagementGroupDisplayName
    details: {
      parent: {
        id: '/providers/Microsoft.Management/managementGroups/${parentManagementGroupId}'
      }
    }
  }
}

// Associates an existing subscription with mg-portfolio. This is an alias
// resource — it does not create a subscription, only moves an existing one
// into this management group. Requires Owner (or Management Group
// Contributor + subscription Owner) on the target subscription.
resource subscriptionPlacement 'Microsoft.Management/managementGroups/subscriptions@2021-04-01' = if (!empty(subscriptionIdToPlace)) {
  parent: mgPortfolio
  name: subscriptionIdToPlace
}

@description('Name (ID) of the mg-portfolio management group, for use as a module `scope:` target.')
output portfolioManagementGroupId string = mgPortfolio.name

@description('Full ARM resource ID of mg-portfolio.')
output portfolioManagementGroupResourceId string = mgPortfolio.id
