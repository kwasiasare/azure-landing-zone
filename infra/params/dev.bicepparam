// ---------------------------------------------------------------------------
// dev.bicepparam
// Parameters for infra/main.bicep (STAGE 2, subscription scope) — dev
// environment. Used by ci.yml (what-if on PR) and deploy.yml (what-if on
// pushes to the dev branch; dev never deploys for real).
//
// PLACEHOLDER values below (marked inline) must be filled in once the
// target subscription/tenant is chosen. Nothing here is a secret — the
// admin password and subscription/tenant IDs used for `az deployment`
// context come from pipeline variables, not this file.
// ---------------------------------------------------------------------------
using '../main.bicep'

param location = 'uksouth'
param environmentName = 'dev'

param hubResourceGroupName = 'rg-hub-dev'
param spokeResourceGroupName = 'rg-spoke-dev'
param avdResourceGroupName = 'rg-avd-dev'

// Bastion stays off by default; the deploy.yml dev job only runs what-if, so
// this has no cost impact until someone flips it and applies for real.
param deployBastion = false

// PLACEHOLDER — replace with your real admin source CIDR (e.g. office/VPN
// egress IP as x.x.x.x/32) before ever deploying for real.
param trustedAdminSourceCidr = '10.0.0.0/8'

param logAnalyticsWorkspaceName = 'log-portfolio-hub-dev'
param logAnalyticsDailyQuotaGb = 1

param avdAdminUsername = 'avdlocaladmin'
// Local admin password is intentionally NOT set here. Supply it at deploy
// time only, e.g.:
//   az deployment sub create ... --parameters avdAdminPassword=$AVD_ADMIN_PASSWORD
// sourced from a GitHub Actions secret. Leaving it unset here keeps the repo
// secret-free; the module param default is also '' so `bicep build` still
// compiles cleanly without a real value.
param avdVmSize = 'Standard_D2s_v5'

param budgetAmountUsd = 30
// PLACEHOLDER — replace with a real distribution list/email before relying
// on budget alerts.
param budgetContactEmails = [
  'CHANGE_ME@example.com'
]

param tags = {
  environment: 'dev'
  project: 'azure-landing-zone'
  costCenter: 'engineering-portfolio'
}
