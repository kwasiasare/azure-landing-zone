// ---------------------------------------------------------------------------
// prod.bicepparam
// Parameters for infra/main.bicep (STAGE 2, subscription scope) — prod
// (master branch) environment. deploy.yml deploys this for real, gated by a
// GitHub Environment protection rule.
//
// PLACEHOLDER values below (marked inline) must be filled in once the
// target subscription/tenant is chosen and before the first real deploy.
// ---------------------------------------------------------------------------
using '../main.bicep'

param location = 'uksouth'
param environmentName = 'prod'

param hubResourceGroupName = 'rg-hub'
param spokeResourceGroupName = 'rg-spoke'
param avdResourceGroupName = 'rg-avd'

// Leave Bastion off between demos — flip to true (and re-deploy) only while
// interactive access is actually needed, then flip back.
param deployBastion = false

// PLACEHOLDER — replace with your real admin source CIDR before deploying.
param trustedAdminSourceCidr = '10.0.0.0/8'

param logAnalyticsWorkspaceName = 'log-portfolio-hub'
param logAnalyticsDailyQuotaGb = 1

param avdAdminUsername = 'avdlocaladmin'
// See dev.bicepparam — password is supplied at deploy time from a GitHub
// Actions secret, never committed here.
param avdVmSize = 'Standard_D2s_v5'

param budgetAmountUsd = 30
// PLACEHOLDER — replace with a real distribution list/email before relying
// on budget alerts.
param budgetContactEmails = [
  'CHANGE_ME@example.com'
]

param tags = {
  environment: 'prod'
  project: 'azure-landing-zone'
  costCenter: 'engineering-portfolio'
}
