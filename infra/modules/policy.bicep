// ---------------------------------------------------------------------------
// policy.bicep
// Governance guardrails for mg-portfolio. Assigned at management group scope
// so every policy inherits down to every subscription/RG placed underneath.
// Deploy at management group scope:
//   az deployment mg create --management-group-id mg-portfolio ...
// ---------------------------------------------------------------------------
targetScope = 'managementGroup'

@description('Locations resources are allowed to be deployed to. PLACEHOLDER — set to the regions you actually intend to use before assigning.')
param allowedLocations array = [
  'uksouth'
  'ukwest'
]

@description('Location used for the (Modify/DeployIfNotExists) policy assignment identities themselves. Must be a location, not a region list.')
param policyAssignmentLocation string = 'uksouth'

@description('Tag key that must be present on resources, inherited from the resource group when missing.')
param requiredTagName string = 'CostCenter'

@description('PLACEHOLDER: full resource ID of the central Log Analytics workspace that the diagnostic-settings DINE policy deploys diagnostics to. Leave empty to skip assigning that policy (e.g. before monitoring.bicep has run once). Example: /subscriptions/<subId>/resourceGroups/rg-hub/providers/Microsoft.OperationalInsights/workspaces/log-portfolio-hub')
param logAnalyticsWorkspaceResourceId string = ''

@description('Name of the diagnostic setting the DINE policy creates on non-compliant NSGs.')
param diagnosticSettingName string = 'deployed-by-policy'

// "Inherit a tag from the resource group if missing" — matches the Modify
// behaviour described below (copy the tag from the parent RG only when the
// resource doesn't already carry it). The previously-referenced definition
// ID here did not correspond to that display name/behaviour; corrected per
// peer review.
var builtInInheritTagPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070'
var builtInAllowedLocationsPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
var builtInRequireTagOnResourceGroupsPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
var tagContributorRoleId = '/providers/Microsoft.Authorization/roleDefinitions/4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
var monitoringContributorRoleId = '/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa'
// DINE policies that write diagnostic settings pointing at a Log Analytics
// workspace need both roles: Monitoring Contributor to create the
// diagnostic setting resource, and Log Analytics Contributor to grant data
// access to the target workspace itself.
var logAnalyticsContributorRoleId = '/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293'

// ---------------------------------------------------------------------------
// 1. Allowed locations (built-in, Deny effect baked into the definition)
// ---------------------------------------------------------------------------
resource allowedLocationsAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'allowed-locations'
  properties: {
    displayName: 'Allowed locations'
    description: 'Restricts resource deployments to approved regions.'
    policyDefinitionId: builtInAllowedLocationsPolicyId
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: {
        value: allowedLocations
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 2. Required tag, inherited from the resource group when missing on the
//    resource (built-in Modify policy). Needs a managed identity + Tag
//    Contributor at this scope so the policy engine can write the tag.
// ---------------------------------------------------------------------------
resource inheritTagAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'inherit-tag-from-rg'
  location: policyAssignmentLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Inherit required tag from resource group'
    description: 'Ensures resources carry the ${requiredTagName} tag by copying it from the parent resource group when absent.'
    policyDefinitionId: builtInInheritTagPolicyId
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: requiredTagName
      }
    }
  }
}

resource inheritTagRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managementGroup().id, 'inherit-tag-from-rg', tagContributorRoleId)
  properties: {
    principalId: inheritTagAssignment.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: tagContributorRoleId
  }
}

// ---------------------------------------------------------------------------
// 2b. Require a tag on resource groups (built-in, Deny effect). Belt-and-
//     braces alongside the inherit-tag Modify policy above: inherit-tag
//     only fixes *resources*, so this catches resource groups themselves
//     being created without the required tag in the first place. PM ruling
//     (see peer review) — assigned unconditionally, always-on.
// ---------------------------------------------------------------------------
resource requireTagOnResourceGroupsAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'require-tag-on-resource-groups'
  properties: {
    displayName: 'Require a tag on resource groups'
    description: 'Denies creation of resource groups that do not carry the ${requiredTagName} tag.'
    policyDefinitionId: builtInRequireTagOnResourceGroupsPolicyId
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: requiredTagName
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 3. Deny public blob access on storage accounts (custom Deny definition)
// ---------------------------------------------------------------------------
resource denyPublicBlobDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: 'deny-storage-public-blob-access'
  properties: {
    policyType: 'Custom'
    mode: 'Indexed'
    displayName: 'Deny public blob access on storage accounts'
    description: 'Blocks creation or update of storage accounts that allow anonymous/public blob access.'
    // Tradeoff (documented per peer review): this custom policy only
    // evaluates storage accounts whose request body explicitly sets
    // allowBlobPublicAccess. An account created without the property set at
    // all (e.g. via the portal, or another IaC tool that omits it) is
    // skipped by this rule rather than denied, even though the platform
    // default for an omitted property is functionally "public access
    // allowed". Without the `exists` guard, Azure Policy's field-comparison
    // semantics treat a missing field as "not equal to false", which denies
    // every implicitly-created storage account — including perfectly valid
    // ones that simply didn't set the property — which is too aggressive
    // for this project's demo scope. Pair with the built-in "Storage
    // account public network access should be disabled" policy (or add an
    // `auditIfNotExists` companion here) for defense in depth against the
    // omitted-property gap this leaves.
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Storage/storageAccounts'
          }
          {
            field: 'Microsoft.Storage/storageAccounts/allowBlobPublicAccess'
            exists: 'true'
          }
          {
            not: {
              field: 'Microsoft.Storage/storageAccounts/allowBlobPublicAccess'
              equals: 'false'
            }
          }
        ]
      }
      then: {
        effect: 'deny'
      }
    }
  }
}

resource denyPublicBlobAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'deny-public-blob-access'
  properties: {
    displayName: 'Deny public blob access on storage accounts'
    description: 'Prevents storage accounts with public blob access enabled.'
    policyDefinitionId: denyPublicBlobDefinition.id
    enforcementMode: 'Default'
  }
}

// ---------------------------------------------------------------------------
// 4. Deploy diagnostic settings on Network Security Groups via policy
//    (custom DeployIfNotExists definition). Skipped until a Log Analytics
//    workspace resource ID is supplied.
// ---------------------------------------------------------------------------
resource deployNsgDiagnosticsDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: 'deploy-nsg-diagnostics-to-la'
  properties: {
    policyType: 'Custom'
    mode: 'Indexed'
    displayName: 'Deploy diagnostic settings for NSGs to Log Analytics'
    description: 'Deploys a diagnostic setting that routes NSG logs to the central Log Analytics workspace when one is missing.'
    parameters: {
      logAnalyticsWorkspaceId: {
        type: 'String'
        metadata: {
          displayName: 'Log Analytics workspace resource ID'
        }
      }
      diagnosticSettingName: {
        type: 'String'
        defaultValue: diagnosticSettingName
        metadata: {
          displayName: 'Diagnostic setting name'
        }
      }
    }
    policyRule: {
      if: {
        field: 'type'
        equals: 'Microsoft.Network/networkSecurityGroups'
      }
      then: {
        effect: 'deployIfNotExists'
        details: {
          type: 'Microsoft.Insights/diagnosticSettings'
          name: '[parameters(\'diagnosticSettingName\')]'
          existenceCondition: {
            field: 'Microsoft.Insights/diagnosticSettings/workspaceId'
            equals: '[parameters(\'logAnalyticsWorkspaceId\')]'
          }
          roleDefinitionIds: [
            monitoringContributorRoleId
            logAnalyticsContributorRoleId
          ]
          deployment: {
            properties: {
              mode: 'incremental'
              parameters: {
                resourceName: {
                  value: '[field(\'name\')]'
                }
                logAnalyticsWorkspaceId: {
                  value: '[parameters(\'logAnalyticsWorkspaceId\')]'
                }
                diagnosticSettingName: {
                  value: '[parameters(\'diagnosticSettingName\')]'
                }
              }
              template: {
                '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
                contentVersion: '1.0.0.0'
                parameters: {
                  resourceName: {
                    type: 'string'
                  }
                  logAnalyticsWorkspaceId: {
                    type: 'string'
                  }
                  diagnosticSettingName: {
                    type: 'string'
                  }
                }
                resources: [
                  {
                    type: 'Microsoft.Network/networkSecurityGroups/providers/diagnosticSettings'
                    apiVersion: '2021-05-01-preview'
                    name: '[concat(parameters(\'resourceName\'), \'/Microsoft.Insights/\', parameters(\'diagnosticSettingName\'))]'
                    properties: {
                      workspaceId: '[parameters(\'logAnalyticsWorkspaceId\')]'
                      logs: [
                        {
                          category: 'NetworkSecurityGroupEvent'
                          enabled: true
                        }
                        {
                          category: 'NetworkSecurityGroupRuleCounter'
                          enabled: true
                        }
                      ]
                    }
                  }
                ]
              }
            }
          }
        }
      }
    }
  }
}

resource deployNsgDiagnosticsAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: 'deploy-nsg-diagnostics'
  location: policyAssignmentLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Deploy NSG diagnostic settings to Log Analytics'
    description: 'Ensures every NSG under mg-portfolio ships flow/event logs to the central workspace.'
    policyDefinitionId: deployNsgDiagnosticsDefinition.id
    enforcementMode: 'Default'
    parameters: {
      logAnalyticsWorkspaceId: {
        value: logAnalyticsWorkspaceResourceId
      }
      diagnosticSettingName: {
        value: diagnosticSettingName
      }
    }
  }
}

resource deployNsgDiagnosticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: guid(managementGroup().id, 'deploy-nsg-diagnostics', monitoringContributorRoleId)
  properties: {
    // Non-null assertion: this resource shares the same `if` condition as
    // deployNsgDiagnosticsAssignment, so whenever this role assignment is
    // deployed, that resource (and its identity) is guaranteed to exist.
    principalId: deployNsgDiagnosticsAssignment!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: monitoringContributorRoleId
  }
}

// Second role assignment matching the second entry now listed in the DINE
// definition's roleDefinitionIds — the identity needs both Monitoring
// Contributor (create the diagnostic setting) and Log Analytics Contributor
// (write access to the target workspace) to actually remediate.
resource deployNsgDiagnosticsLogAnalyticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  name: guid(managementGroup().id, 'deploy-nsg-diagnostics', logAnalyticsContributorRoleId)
  properties: {
    principalId: deployNsgDiagnosticsAssignment!.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: logAnalyticsContributorRoleId
  }
}

output allowedLocationsAssignmentId string = allowedLocationsAssignment.id
output inheritTagAssignmentId string = inheritTagAssignment.id
output requireTagOnResourceGroupsAssignmentId string = requireTagOnResourceGroupsAssignment.id
output denyPublicBlobAssignmentId string = denyPublicBlobAssignment.id
