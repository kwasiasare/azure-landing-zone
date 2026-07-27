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
// 192.0.2.0/24 (TEST-NET-1) is genuinely non-routable, unlike a real
// RFC1918 range.
param trustedAdminSourceCidr = '192.0.2.0/24'

param hubVnetAddressPrefix = '10.0.0.0/22'
param bastionSubnetPrefix = '10.0.0.0/26'
param sharedServicesSubnetPrefix = '10.0.1.0/24'
param spokeVnetAddressPrefix = '10.1.0.0/22'
param workloadSubnetPrefix = '10.1.0.0/24'
param avdSubnetPrefix = '10.1.1.0/24'

param logAnalyticsWorkspaceName = 'log-portfolio-hub'
param logAnalyticsDailyQuotaGb = 1

param avdAdminUsername = 'avdlocaladmin'
// See dev.bicepparam for the full explanation — password is sourced from
// AVD_LOCAL_ADMIN_PASSWORD (env var fallback here, explicit CLI override at
// deploy time from the GitHub Actions secret), never committed here.
param avdAdminPassword = readEnvironmentVariable('AVD_LOCAL_ADMIN_PASSWORD', 'Local-Dev-Placeholder-Pwd1')
param avdVmSize = 'Standard_D2s_v5'
param avdHostPoolName = 'hp-portfolio-pooled'
param avdMaxSessionLimit = 4

param avdAutoShutdownTimeUtc = '1900'
param avdAutoShutdownTimeZoneId = 'UTC'

// PLACEHOLDER — object ID of the tenant's "Azure Virtual Desktop" enterprise
// application. See README "Placeholders you must supply". Left empty: the
// startVMOnConnect role assignment is skipped until this is filled in.
param avdServicePrincipalObjectId = ''

param budgetAmountUsd = 30
// PLACEHOLDER — replace with a real distribution list/email before relying
// on budget alerts.
param budgetContactEmails = [
  'CHANGE_ME@example.com'
]
// Empty = auto-computed 'budget-portfolio-landingzone-prod'.
param budgetNameOverride = ''
// Fixed literal, not utcNow()-derived — see budget.bicep for why. Update
// only if intentionally recreating the budget (Consumption budgets treat
// startDate as immutable after creation).
param budgetStartDate = '2026-07-01'

param tags = {
  environment: 'prod'
  project: 'azure-landing-zone'
  costCenter: 'engineering-portfolio'
}
