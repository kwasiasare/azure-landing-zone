// ---------------------------------------------------------------------------
// avd-startvm-roleassignment.bicep
// startVMOnConnect (set on the pooled host pool in avd.bicep) requires the
// Azure Virtual Desktop resource provider's service principal to hold
// "Desktop Virtualization Power On Contributor" at SUBSCRIPTION scope —
// without it, a user launching the desktop from the AVD client cannot
// auto-power-on a deallocated session host. Deployed at subscription scope
// (this module has no targetScope override, so it inherits the caller's;
// main.bicep is already 'subscription').
//
// The AVD service principal's object ID is tenant-specific — it is the
// enterprise application "Azure Virtual Desktop" that Entra creates the
// first time AVD is used in a tenant. See README "Placeholders you must
// supply" for how to look it up. This module deploys conditionally: skipped
// entirely (no-op) when avdServicePrincipalObjectId is left empty, so it is
// safe to leave unset until the tenant-specific value is known.
// ---------------------------------------------------------------------------
targetScope = 'subscription'

@description('PLACEHOLDER — object ID of the Azure Virtual Desktop resource provider service principal (enterprise application "Azure Virtual Desktop") in this tenant. Tenant-specific; find it with: az ad sp list --display-name "Azure Virtual Desktop" --query "[0].id" -o tsv. Leave empty to skip this assignment — startVMOnConnect will then fail to power on deallocated hosts until this is assigned (manually, or by re-running this deployment with the value filled in).')
param avdServicePrincipalObjectId string = ''

// Built-in role: Desktop Virtualization Power On Contributor.
var desktopVirtualizationPowerOnContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '489581de-a3bd-480d-9518-53dea7416b33'
)

resource startVmOnConnectRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(avdServicePrincipalObjectId)) {
  name: guid(subscription().id, avdServicePrincipalObjectId, 'desktop-virtualization-power-on-contributor')
  properties: {
    principalId: avdServicePrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: desktopVirtualizationPowerOnContributorRoleId
  }
}

output roleAssignmentId string = !empty(avdServicePrincipalObjectId) ? startVmOnConnectRoleAssignment!.id : ''
