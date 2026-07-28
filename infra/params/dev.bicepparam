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

param location = 'eastus2'
param environmentName = 'dev'

param hubResourceGroupName = 'rg-hub-dev'
param spokeResourceGroupName = 'rg-spoke-dev'
param avdResourceGroupName = 'rg-avd-dev'

// Bastion stays off by default; the deploy.yml dev job only runs what-if, so
// this has no cost impact until someone flips it and applies for real.
param deployBastion = false

// PLACEHOLDER — replace with your real admin source CIDR (e.g. office/VPN
// egress IP as x.x.x.x/32) before ever deploying for real. 192.0.2.0/24
// (TEST-NET-1) is genuinely non-routable, unlike a real RFC1918 range.
param trustedAdminSourceCidr = '192.0.2.0/24'

param hubVnetAddressPrefix = '10.0.0.0/22'
param bastionSubnetPrefix = '10.0.0.0/26'
param sharedServicesSubnetPrefix = '10.0.1.0/24'
param spokeVnetAddressPrefix = '10.1.0.0/22'
param workloadSubnetPrefix = '10.1.0.0/24'
param avdSubnetPrefix = '10.1.1.0/24'

param logAnalyticsWorkspaceName = 'log-portfolio-hub-dev'
param logAnalyticsDailyQuotaGb = 1

param avdAdminUsername = 'avdlocaladmin'
// Local admin password is intentionally NOT hardcoded here. Sourced from the
// AVD_LOCAL_ADMIN_PASSWORD environment variable when present (CI what-if/
// deploy steps export it from the AVD_LOCAL_ADMIN_PASSWORD GitHub secret —
// see .github/workflows/*.yml); falls back to an inert 12+ char placeholder
// so `az bicep build-params` keeps compiling cleanly with no env var set
// (e.g. this lint job, local validation) and to satisfy the @minLength(12)
// constraint on avdAdminPassword in main.bicep. The workflow's explicit
// `--parameters avdAdminPassword="$AVD_LOCAL_ADMIN_PASSWORD"` CLI override
// on the what-if/deploy commands is the real source of truth at deploy
// time; this fallback only matters when that override isn't supplied.
param avdAdminPassword = readEnvironmentVariable('AVD_LOCAL_ADMIN_PASSWORD', 'Local-Dev-Placeholder-Pwd1')
param avdVmSize = 'Standard_D2s_v5'
param avdHostPoolName = 'hp-portfolio-pooled-dev'
param avdMaxSessionLimit = 4

// Deallocated nightly at 19:00 UTC by default; startVMOnConnect powers the
// host back on when a user launches the desktop (see
// scripts/session-host-deallocate-notes.md).
param avdAutoShutdownTimeUtc = '1900'
param avdAutoShutdownTimeZoneId = 'UTC'

// PLACEHOLDER — object ID of the tenant's "Azure Virtual Desktop" enterprise
// application. See README "Placeholders you must supply". Left empty: the
// startVMOnConnect role assignment is skipped until this is filled in.
param avdServicePrincipalObjectId = '1d2ed920-2c3a-4b30-80d9-9480bd594272' // "Azure Virtual Desktop" SP in spdcdev01

param budgetAmountUsd = 30
// PLACEHOLDER — replace with a real distribution list/email before relying
// on budget alerts.
param budgetContactEmails = [
  'kwasi.spreadcom@gmail.com'
]
// Empty = auto-computed 'budget-portfolio-landingzone-dev'.
param budgetNameOverride = ''
// Fixed literal, not utcNow()-derived — see budget.bicep for why. Update
// only if intentionally recreating the budget (Consumption budgets treat
// startDate as immutable after creation).
param budgetStartDate = '2026-07-01'

param tags = {
  environment: 'dev'
  project: 'azure-landing-zone'
  costCenter: 'engineering-portfolio'
}
