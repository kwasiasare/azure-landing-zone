#Requires -Version 7.0
<#
.SYNOPSIS
    Safe, targeted teardown of the azure-landing-zone subscription-stage
    resources (rg-hub, rg-spoke, rg-avd) for a given environment.

.DESCRIPTION
    Deletes ONLY the three resource groups this project creates, for ONE
    named environment, and ONLY after an explicit interactive confirmation
    (or -Force). It never touches management groups, policy assignments, or
    the budget — those are STAGE 1 (tenant/mg scope) and are deliberately
    left alone; tear them down manually if you really mean to (see README).

    Defaults to -WhatIf-style dry run: pass -Confirm to actually delete.

.PARAMETER SubscriptionId
    Subscription ID to operate in. Required — there is no default, so you
    cannot accidentally run this against whatever subscription happens to
    be your current `az account show` context.

.PARAMETER Environment
    'dev' or 'prod'. Selects the rg-*-dev vs rg-* (no suffix) resource group
    names used by infra/params/dev.bicepparam and prod.bicepparam.

.PARAMETER Confirm
    Actually perform the deletion. Without this switch the script only
    prints what it WOULD delete.

.EXAMPLE
    ./teardown.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Environment dev
    # Dry run: lists the resource groups that would be deleted.

.EXAMPLE
    ./teardown.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Environment dev -Confirm
    # Deletes rg-hub-dev, rg-spoke-dev, rg-avd-dev after a typed confirmation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment,

    [switch]$Confirm
)

$ErrorActionPreference = 'Stop'

if ($Environment -eq 'dev') {
    $resourceGroups = @('rg-hub-dev', 'rg-spoke-dev', 'rg-avd-dev')
}
else {
    $resourceGroups = @('rg-hub', 'rg-spoke', 'rg-avd')
}

Write-Host "Target subscription : $SubscriptionId" -ForegroundColor Cyan
Write-Host "Target environment  : $Environment" -ForegroundColor Cyan
Write-Host "Resource groups     : $($resourceGroups -join ', ')" -ForegroundColor Cyan
Write-Host ''
Write-Host 'This script does NOT touch:' -ForegroundColor Yellow
Write-Host '  - mg-portfolio or any policy assignment (STAGE 1 / tenant scope)'
Write-Host '  - the consumption budget (subscription scope, outside these RGs)'
Write-Host '  - any other resource group in the subscription'
Write-Host ''

# Confirm the az CLI is pointed at the subscription we expect before doing
# anything else, so a stale `az account set` context cannot surprise us.
az account set --subscription $SubscriptionId
$currentSub = az account show --query id -o tsv
if ($currentSub -ne $SubscriptionId) {
    throw "az CLI context ($currentSub) does not match -SubscriptionId ($SubscriptionId) after 'az account set'. Aborting."
}

foreach ($rg in $resourceGroups) {
    $exists = az group exists --name $rg --subscription $SubscriptionId
    if ($exists -eq 'true') {
        Write-Host "[found]   $rg" -ForegroundColor Green
    }
    else {
        Write-Host "[missing] $rg (nothing to delete)" -ForegroundColor DarkGray
    }
}

if (-not $Confirm) {
    Write-Host ''
    Write-Host 'Dry run only — re-run with -Confirm to actually delete the resource groups listed [found] above.' -ForegroundColor Yellow
    return
}

Write-Host ''
$typed = Read-Host "Type the exact environment name ('$Environment') to proceed with deletion"
if ($typed -ne $Environment) {
    throw "Confirmation text '$typed' did not match '$Environment'. Aborting — nothing deleted."
}

foreach ($rg in $resourceGroups) {
    $exists = az group exists --name $rg --subscription $SubscriptionId
    if ($exists -eq 'true') {
        Write-Host "Deleting $rg ..." -ForegroundColor Red
        az group delete --name $rg --subscription $SubscriptionId --yes --no-wait
    }
}

Write-Host ''
Write-Host 'Deletion requests submitted with --no-wait. Track progress with:' -ForegroundColor Cyan
Write-Host "  az group list --subscription $SubscriptionId --query \"[?starts_with(name,'rg-hub') || starts_with(name,'rg-spoke') || starts_with(name,'rg-avd')].{name:name,state:properties.provisioningState}\" -o table"
