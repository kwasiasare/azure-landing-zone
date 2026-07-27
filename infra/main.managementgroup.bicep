// ---------------------------------------------------------------------------
// main.managementgroup.bicep
// STAGE 1 (one-time bootstrap, tenant scope): creates mg-portfolio and
// assigns the governance policies that need to inherit down to every
// subscription/RG under it. Re-run whenever policy/mg parameters change —
// it is idempotent.
//
// Deploy with:
//   az deployment tenant create \
//     --name azure-landing-zone-mg \
//     --location <region> \
//     --template-file infra/main.managementgroup.bicep \
//     --parameters infra/params/managementgroup.bicepparam
//
// Requires: Owner (or Management Group Contributor + Policy Contributor) on
// the parent management group, and Owner on the subscription being placed.
//
// NOTE: this file creates mg-portfolio and then assigns policy to it in one
// deployment, relying on Bicep to sequence the nested module (policy.bicep)
// after the management group exists via the implicit output dependency. If
// your tenant/CLI combination rejects a management-group-scoped module
// nested this deeply, fall back to a two-phase apply: deploy
// modules/management-groups.bicep alone first, then modules/policy.bicep
// alone with --management-group-id mg-portfolio.
// ---------------------------------------------------------------------------
targetScope = 'tenant'

@description('ID of the parent management group mg-portfolio is created under. Defaults to the tenant root group.')
param parentManagementGroupId string = tenant().tenantId

@description('ID (name) of the portfolio management group.')
param portfolioManagementGroupId string = 'mg-portfolio'

@description('Display name of the portfolio management group.')
param portfolioManagementGroupDisplayName string = 'Engineering Portfolio'

@description('PLACEHOLDER — subscription ID (GUID) to place under mg-portfolio. Leave empty until the target subscription is confirmed.')
param subscriptionIdToPlace string = ''

@description('Locations resources are allowed to be deployed to.')
param allowedLocations array = [
  'uksouth'
  'ukwest'
]

@description('Location used for policy assignment managed identities.')
param policyAssignmentLocation string = 'uksouth'

@description('Tag key that must be present on resources, inherited from the resource group when missing.')
param requiredTagName string = 'CostCenter'

@description('PLACEHOLDER — resource ID of the central Log Analytics workspace, once monitoring.bicep has been deployed once. Leave empty on first run.')
param logAnalyticsWorkspaceResourceId string = ''

module managementGroups 'modules/management-groups.bicep' = {
  name: 'deploy-management-groups'
  params: {
    parentManagementGroupId: parentManagementGroupId
    portfolioManagementGroupId: portfolioManagementGroupId
    portfolioManagementGroupDisplayName: portfolioManagementGroupDisplayName
    subscriptionIdToPlace: subscriptionIdToPlace
  }
}

module policies 'modules/policy.bicep' = {
  name: 'deploy-policy-assignments'
  // NOTE: scope must reference the input parameter (resolvable at the start
  // of the deployment), not managementGroups.outputs.* (a runtime value) —
  // they hold the same value since management-groups.bicep uses this same
  // parameter as the group's name.
  scope: managementGroup(portfolioManagementGroupId)
  params: {
    allowedLocations: allowedLocations
    policyAssignmentLocation: policyAssignmentLocation
    requiredTagName: requiredTagName
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
  }
  // Explicit dependency: the scope above is derived from a parameter (not
  // managementGroups.outputs), so Bicep would otherwise have no implicit
  // ordering guarantee that mg-portfolio exists before this deploys.
  dependsOn: [
    managementGroups
  ]
}

output portfolioManagementGroupId string = managementGroups.outputs.portfolioManagementGroupId
output portfolioManagementGroupResourceId string = managementGroups.outputs.portfolioManagementGroupResourceId
