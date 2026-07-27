// ---------------------------------------------------------------------------
// avd.bicep
// AVD proof of concept: one pooled host pool, one desktop application group,
// one workspace, and a single Windows 11 multi-session session host that is
// Entra-joined (no AD DS / no domain join extension) and deallocated nightly
// by an auto-shutdown schedule. Deployed into rg-avd at resource group scope.
// ---------------------------------------------------------------------------

@description('Azure region for all AVD and compute resources.')
param location string

@description('Name of the pooled host pool.')
param hostPoolName string = 'hp-portfolio-pooled'

@description('Name of the desktop application group.')
param applicationGroupName string = 'ag-portfolio-desktop'

@description('Name of the AVD workspace.')
param workspaceName string = 'ws-portfolio-avd'

@description('Max sessions per session host (pooled, breadth-first).')
param maxSessionLimit int = 4

@description('NetBIOS-safe name for the session host VM (<= 15 chars).')
@maxLength(15)
param sessionHostVmName string = 'avd-sh-01'

@description('VM size for the session host. D2s_v5 keeps a single multi-session host affordable for a demo.')
param vmSize string = 'Standard_D2s_v5'

@description('Resource ID of the subnet the session host NIC attaches to (spoke AVD subnet, from network.bicep output).')
param subnetResourceId string

@description('Local admin username required by the VM provisioning API even on an Entra-joined VM. Not used for day-to-day sign-in.')
param adminUsername string = 'avdlocaladmin'

@secure()
@description('PLACEHOLDER — local admin password. Never commit a real value. Supply via a pipeline secret (e.g. AZURE_AVD_LOCAL_ADMIN_PASSWORD) mapped to a bicepparam using readEnvironmentVariable(), or a Key Vault reference. Deployment fails fast if left as the empty default.')
param adminPassword string = ''

@description('PLACEHOLDER — resource ID of the central Log Analytics workspace (monitoring.bicep output). Leave empty to skip the monitoring agent + DCR association.')
param logAnalyticsWorkspaceResourceId string = ''

@description('PLACEHOLDER — resource ID of the Data Collection Rule the session host associates with (monitoring.bicep output). Leave empty to skip.')
param dataCollectionRuleResourceId string = ''

@description('24h HHmm time (in autoShutdownTimeZoneId) the session host is deallocated every day.')
param autoShutdownTimeUtc string = '1900'

@description('Time zone ID for the auto-shutdown schedule.')
param autoShutdownTimeZoneId string = 'UTC'

@description('PLACEHOLDER — public URL of the AVD RDAgentBootLoader DSC configuration zip. This URL is versioned by Microsoft and changes periodically; verify the current link at https://learn.microsoft.com/azure/virtual-desktop/create-host-pools-arm-template before deploying.')
#disable-next-line no-hardcoded-env-urls // fixed Microsoft-hosted public artifact, not an environment-specific endpoint; see description above
param avdAgentDscPackageUrl string = 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02790.577.zip'

@description('Tags applied to AVD and compute resources.')
param tags object = {}

// Registration token is short-lived (2h) and regenerated on every deployment
// of this module — expected/standard for AVD host pools driven from IaC.
param hostPoolRegistrationTokenExpirationUtc string = dateTimeAdd(utcNow(), 'PT2H')

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: hostPoolName
  location: location
  tags: tags
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: 'Desktop'
    maxSessionLimit: maxSessionLimit
    startVMOnConnect: true
    // Required so the AVD client can discover this is an Entra-joined (not
    // hybrid/AD-joined) host pool and skip the domain-join sign-in prompt.
    customRdpProperty: 'targetisaadjoined:i:1;'
    registrationInfo: {
      expirationTime: hostPoolRegistrationTokenExpirationUtc
      registrationTokenOperation: 'Update'
    }
  }
}

resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2023-09-05' = {
  name: applicationGroupName
  location: location
  tags: tags
  properties: {
    hostPoolArmPath: hostPool.id
    applicationGroupType: 'Desktop'
  }
}

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2023-09-05' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    applicationGroupReferences: [
      applicationGroup.id
    ]
  }
}

resource sessionHostNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'nic-${sessionHostVmName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetResourceId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// Windows 11 multi-session, Entra-joined, Trusted Launch (secure boot + vTPM
// — required for the Windows 11 gallery image).
resource sessionHostVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: sessionHostVmName
  location: location
  tags: tags
  // System-assigned identity is not consumed by any resource in this
  // module directly — it exists because the AADLoginForWindows and
  // AzureMonitorWindowsAgent VM extensions below use it under the hood for
  // Entra join and Azure Monitor authentication respectively (both
  // extensions require the host VM to have a managed identity present).
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    // Azure Hybrid Benefit for the Windows 11 multi-session/client image —
    // required licensing declaration for this SKU family even though no
    // benefit is actually being redeemed in this demo.
    licenseType: 'Windows_Client'
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        // Periodic review: Microsoft retires older win11-*-avd SKUs on its
        // own cadence — confirm this is still a supported/current SKU at
        // https://learn.microsoft.com/azure/virtual-desktop/prepare-windows-11
        // before each redeploy and bump if a newer one has shipped.
        sku: 'win11-24h2-avd'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: sessionHostVmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: sessionHostNic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
  }
}

// Entra join (no on-prem AD required).
resource aadLoginExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: sessionHostVm
  name: 'AADLoginForWindows'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '2.2'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

// Registers the VM as an AVD session host via the published DSC package.
// Must run after Entra join. The DSC extension type does not support
// enableAutomaticUpgrade (not in the platform's auto-upgrade allowlist for
// legacy PowerShell DSC handlers), so only autoUpgradeMinorVersion applies
// here.
resource avdAgentDscExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: sessionHostVm
  name: 'Microsoft.PowerShell.DSC'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.83'
    autoUpgradeMinorVersion: true
    settings: {
      modulesUrl: avdAgentDscPackageUrl
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
    }
    // The registration token is a secret credential the DSC configuration
    // uses to join the host pool — it must live in protectedSettings (only
    // ever visible to the extension runtime inside the VM, never persisted
    // in plain text in the deployment's activity log/resource properties),
    // not settings.
    protectedSettings: {
      properties: {
        hostPoolName: hostPool.name
        // listRegistrationTokens() invokes the runtime action that returns
        // the current token; hostPool.properties.registrationInfo.token is
        // null on a GET for this API version and must not be used.
        registrationInfoToken: hostPool.listRegistrationTokens().value[0].token
        aadJoin: true
      }
    }
  }
  dependsOn: [
    aadLoginExtension
  ]
}

resource monitoringAgentExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (!empty(logAnalyticsWorkspaceResourceId)) {
  parent: sessionHostVm
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
  // Not functionally required by the agent itself, but keeps VM extension
  // provisioning deterministic/sequential rather than racing the DSC
  // extension for the VM's single extension-handler slot.
  dependsOn: [
    avdAgentDscExtension
  ]
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = if (!empty(dataCollectionRuleResourceId)) {
  name: 'dcr-association-${sessionHostVmName}'
  scope: sessionHostVm
  properties: {
    dataCollectionRuleId: dataCollectionRuleResourceId
  }
  // Associating the DCR before the monitor agent is installed is harmless
  // but pointless (nothing is running yet to honor it) — order after the
  // agent extension for a clean, readable provisioning sequence.
  dependsOn: [
    monitoringAgentExtension
  ]
}

// Cost control: deallocate the session host every night. Works for any
// Azure VM (not just DevTest Labs) via the microsoft.devtestlab/schedules
// "ComputeVmShutdownTask" resource scoped to a plain resource group.
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${sessionHostVmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTimeUtc
    }
    timeZoneId: autoShutdownTimeZoneId
    targetResourceId: sessionHostVm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

output hostPoolId string = hostPool.id
output applicationGroupId string = applicationGroup.id
output workspaceId string = workspace.id
output sessionHostVmId string = sessionHostVm.id
