#Requires -Version 7.0
<#
.SYNOPSIS
    Safe, targeted teardown of the azure-landing-zone subscription-stage
    resources (rg-hub, rg-spoke, rg-avd) for a given environment.

.DESCRIPTION
    Deletes ONLY the three resource groups this project creates, for ONE
    named environment, and ONLY after an explicit interactive confirmation
    (or -Yes). It never touches management groups, policy assignments, or
    the budget - those are STAGE 1 (tenant/mg scope) and are deliberately
    left alone; tear them down manually if you really mean to (see README).

    Defaults to a dry run: pass -Execute to actually delete. Before deleting
    each resource group, the script asserts it carries the tag
    project=azure-landing-zone (the tag every resource group this project
    creates is given - see main.bicep's `tags` default/param). A resource
    group that exists but is missing/mismatched on that tag is SKIPPED with
    a warning rather than deleted, so this script cannot accidentally delete
    a same-named resource group some other project happens to own.

    Does not mutate the operator's ambient `az account` context: every az
    CLI call below is explicit about --subscription rather than relying on
    (or changing) `az account set`.

.PARAMETER SubscriptionId
    Subscription ID to operate in. Required - there is no default, so you
    cannot accidentally run this against whatever subscription happens to
    be your current `az account show` context.

.PARAMETER Environment
    'dev' or 'prod'. Selects the rg-*-dev vs rg-* (no suffix) resource group
    names used by infra/params/dev.bicepparam and prod.bicepparam.

.PARAMETER Execute
    Actually perform the deletion. Without this switch the script only
    prints what it WOULD delete (and how many resources are currently in
    each resource group). Replaces the old -Confirm switch name, which
    shadowed PowerShell's built-in common parameter of the same name.

.PARAMETER Yes
    Skip the interactive "type the environment name to confirm" prompt.
    Only effective together with -Execute. Intended for non-interactive/CI
    use - use deliberately, this removes the last manual safety check.

.PARAMETER NoWait
    Submit the resource group deletions asynchronously (`az group delete
    --no-wait`) and return immediately, as this script always did
    previously. By default (without this switch) the script now waits
    synchronously for each deletion to finish before moving to the next,
    so a plain run reports real completion/failure instead of merely
    "request submitted".

.EXAMPLE
    ./teardown.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Environment dev
    # Dry run: lists the resource groups that would be deleted, their
    # project tag status, and their current resource counts.

.EXAMPLE
    ./teardown.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Environment dev -Execute
    # Deletes rg-hub-dev, rg-spoke-dev, rg-avd-dev (synchronously) after a
    # typed confirmation, skipping any that aren't tagged project=azure-landing-zone.

.EXAMPLE
    ./teardown.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Environment dev -Execute -Yes -NoWait
    # Non-interactive, fire-and-forget teardown - e.g. from a scheduled
    # cleanup job. No prompt, deletions submitted with --no-wait.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment,

    [switch]$Execute,

    [switch]$Yes,

    [switch]$NoWait
)

$ErrorActionPreference = 'Stop'

# Every resource group this project creates is tagged with this value (see
# the `tags` param/default in infra/main.bicep and infra/params/*.bicepparam).
# A resource group with the right name but the wrong/missing tag is left
# alone rather than deleted.
$expectedProjectTag = 'azure-landing-zone'

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

# Confirm the caller actually has access to this subscription before doing
# anything else. This does NOT call `az account set` - every az command
# below passes --subscription explicitly instead, so the operator's ambient
# `az account show` default context is left untouched by this script.
$resolvedSubId = az account show --subscription $SubscriptionId --query id -o tsv
if ($resolvedSubId -ne $SubscriptionId) {
    throw "Could not resolve subscription $SubscriptionId via 'az account show --subscription'. Aborting."
}

# [name, exists, tagOk, resourceCount]
$rgStatus = @()

foreach ($rg in $resourceGroups) {
    $exists = az group exists --name $rg --subscription $SubscriptionId
    if ($exists -eq 'true') {
        $projectTag = az group show --name $rg --subscription $SubscriptionId --query "tags.project" -o tsv 2>$null
        $tagOk = ($projectTag -eq $expectedProjectTag)
        $resourceCount = az resource list --resource-group $rg --subscription $SubscriptionId --query 'length(@)' -o tsv

        $rgStatus += [pscustomobject]@{
            Name          = $rg
            Exists        = $true
            TagOk         = $tagOk
            ResourceCount = $resourceCount
        }

        if ($tagOk) {
            Write-Host "[found]   $rg  (tag project=$expectedProjectTag OK, $resourceCount resource(s))" -ForegroundColor Green
        }
        else {
            $actualTag = if ([string]::IsNullOrEmpty($projectTag)) { '<missing>' } else { $projectTag }
            Write-Host "[found]   $rg  (WARNING: tag project=$actualTag, expected '$expectedProjectTag' - will be SKIPPED, not deleted)" -ForegroundColor Yellow
        }
    }
    else {
        $rgStatus += [pscustomobject]@{
            Name          = $rg
            Exists        = $false
            TagOk         = $false
            ResourceCount = 0
        }
        Write-Host "[missing] $rg (nothing to delete)" -ForegroundColor DarkGray
    }
}

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Dry run only - re-run with -Execute to actually delete the resource groups listed [found] above (excluding any flagged for a tag mismatch).' -ForegroundColor Yellow
    return
}

$toDelete = $rgStatus | Where-Object { $_.Exists -and $_.TagOk }
if ($toDelete.Count -eq 0) {
    Write-Host ''
    Write-Host 'Nothing eligible to delete (no matching resource groups found, or all found were tag-mismatched). Nothing to do.' -ForegroundColor Yellow
    return
}

if (-not $Yes) {
    Write-Host ''
    $typed = Read-Host "Type the exact environment name ('$Environment') to proceed with deletion"
    if ($typed -ne $Environment) {
        throw "Confirmation text '$typed' did not match '$Environment'. Aborting - nothing deleted."
    }
}

Write-Host ''
foreach ($status in $toDelete) {
    $rg = $status.Name
    if ($NoWait) {
        Write-Host "Deleting $rg (async, --no-wait) ..." -ForegroundColor Red
        az group delete --name $rg --subscription $SubscriptionId --yes --no-wait
    }
    else {
        Write-Host "Deleting $rg (synchronous, this will block until complete) ..." -ForegroundColor Red
        az group delete --name $rg --subscription $SubscriptionId --yes
        Write-Host "Deleted $rg." -ForegroundColor Green
    }
}

Write-Host ''
if ($NoWait) {
    Write-Host 'Deletion requests submitted with --no-wait. Track progress with:' -ForegroundColor Cyan
}
else {
    Write-Host 'All deletions completed. Verify with:' -ForegroundColor Cyan
}
Write-Host ('  az group list --subscription {0} --query "[?starts_with(name,''rg-hub'') || starts_with(name,''rg-spoke'') || starts_with(name,''rg-avd'')].{{name:name,state:properties.provisioningState}}" -o table' -f $SubscriptionId)
