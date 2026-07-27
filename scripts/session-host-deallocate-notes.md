# AVD session host: deallocate / start notes

The single pooled session host (`avd-sh-01`, deployed by
`infra/modules/avd.bicep`) is deallocated automatically every night by a
`Microsoft.DevTestLab/schedules` resource named
`shutdown-computevm-avd-sh-01`, driven by these `main.bicep` parameters
(plumbed all the way through from `dev.bicepparam`/`prod.bicepparam` — see
`avdAutoShutdownTimeUtc`/`avdAutoShutdownTimeZoneId` in `main.bicep`, passed
to `avd.bicep`'s `autoShutdownTimeUtc`/`autoShutdownTimeZoneId` params):

| Behaviour | Parameter (`main.bicep` -> `avd.bicep`) | Default |
|---|---|---|
| Shutdown time | `avdAutoShutdownTimeUtc` -> `autoShutdownTimeUtc` | `1900` (19:00) |
| Time zone | `avdAutoShutdownTimeZoneId` -> `autoShutdownTimeZoneId` | `UTC` |

The host pool name (`avdHostPoolName` -> `hostPoolName`, default
`hp-portfolio-pooled`/`hp-portfolio-pooled-dev`) and max session limit
(`avdMaxSessionLimit` -> `maxSessionLimit`, default `4`) are similarly
plumbed through `main.bicep` if you need to override them; the session
host VM name itself (`avd-sh-01`) is not currently parameterized past
`avd.bicep`'s own `sessionHostVmName` default.

This is the same "auto-shutdown" feature available in the Azure Portal for
any VM (not a DevTest Labs–only feature) — it stops **and deallocates** the
VM, so compute billing stops (storage/disk cost continues while stopped).

`startVMOnConnect: true` is set on the host pool, so a user launching the
desktop from the AVD client/web client will automatically power the VM back
on — no manual intervention needed for the demo to keep working during
business hours.

## Manual deallocate / start (az CLI)

```powershell
# Deallocate immediately (e.g. right after a demo)
az vm deallocate --resource-group rg-avd --name avd-sh-01

# Start it back up
az vm start --resource-group rg-avd --name avd-sh-01

# Check current power state
az vm get-instance-view `
  --resource-group rg-avd --name avd-sh-01 `
  --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayName" `
  -o tsv
```

Swap `rg-avd` for `rg-avd-dev` when operating on the dev environment's
resource group naming (`infra/params/dev.bicepparam`).

## Changing the schedule

Edit `avdAutoShutdownTimeUtc` / `avdAutoShutdownTimeZoneId` in
`infra/params/dev.bicepparam` or `prod.bicepparam` (they are passed through
`main.bicep` -> `avd.bicep`) and re-run the subscription-stage deployment;
the schedule resource is idempotent and updates in place.

## Why not just delete the VM between demos?

Re-provisioning would re-run the AVD agent DSC registration and Entra join
extensions every time, which is slower and adds churn to the host pool
registration token. Deallocating keeps the VM (and its AVD registration)
intact at effectively zero compute cost, which fits this project's
cost-control goal better than delete/recreate.
