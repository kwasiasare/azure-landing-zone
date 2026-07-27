// ---------------------------------------------------------------------------
// managementgroup.bicepparam
// Parameters for infra/main.managementgroup.bicep (STAGE 1, tenant scope).
// This stage is deployed once (and re-run only when governance parameters
// change) — it is not part of the dev/prod branch split.
//
// PLACEHOLDER values below MUST be filled in before the first deploy:
//   - subscriptionIdToPlace: the GUID of the subscription this landing zone
//     targets. Unknown until the subscription is chosen (see README TODOs).
// ---------------------------------------------------------------------------
using '../main.managementgroup.bicep'

// Defaults to the tenant root group via main.managementgroup.bicep's own
// default; override only if mg-portfolio should nest under an existing
// mg-platform/mg-landingzones structure.
// param parentManagementGroupId = '<PARENT_MANAGEMENT_GROUP_ID>'

param portfolioManagementGroupId = 'mg-portfolio'
param portfolioManagementGroupDisplayName = 'Engineering Portfolio'

// PLACEHOLDER — fill in once the target subscription is confirmed. Leave
// empty ('') to deploy the management group without moving a subscription
// into it yet.
param subscriptionIdToPlace = ''

param allowedLocations = [
  'uksouth'
  'ukwest'
]
param policyAssignmentLocation = 'uksouth'
param requiredTagName = 'CostCenter'

// PLACEHOLDER — set once modules/monitoring.bicep has been deployed at
// least once, to the Log Analytics workspace resource ID it produced. The
// NSG-diagnostics DINE policy is skipped while this is empty.
param logAnalyticsWorkspaceResourceId = ''
