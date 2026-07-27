// ---------------------------------------------------------------------------
// monitoring.bicep
// Central Log Analytics workspace + a basic Data Collection Rule for the AVD
// session host (Windows event logs + performance counters). Deployed into
// rg-hub at resource group scope.
// ---------------------------------------------------------------------------

@description('Azure region for the workspace and DCR.')
param location string

@description('Name of the central Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'log-portfolio-hub'

@description('Log retention in days.')
param retentionInDays int = 30

@description('Daily ingestion cap in GB — cost control guardrail for a demo environment. Set -1 to disable the cap.')
param dailyQuotaGb int = 1

@description('Name of the Data Collection Rule used by the AVD session host.')
param dataCollectionRuleName string = 'dcr-avd-session-hosts'

@description('Tags applied to monitoring resources.')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
  }
}

// Minimal DCR: Windows event logs (System/Application) + a handful of
// performance counters, routed to the central workspace. Associate this with
// the AVD session host VM from avd.bicep.
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dataCollectionRuleName
  location: location
  tags: tags
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'systemAndAppLogs'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
      performanceCounters: [
        {
          name: 'basicPerfCounters'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\LogicalDisk(_Total)\\% Free Space'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'centralWorkspace'
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          'centralWorkspace'
        ]
      }
      {
        streams: [
          'Microsoft-Perf'
        ]
        destinations: [
          'centralWorkspace'
        ]
      }
    ]
  }
}

output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
output dataCollectionRuleResourceId string = dataCollectionRule.id
