// ---------------------------------------------------------------------------
// budget.bicep
// Subscription-level consumption budget with a small set of email alert
// thresholds. Cost-control guardrail for a demo landing zone.
// ---------------------------------------------------------------------------
targetScope = 'subscription'

@description('Name of the budget.')
param budgetName string = 'budget-portfolio-landingzone'

@description('Monthly budget amount in USD.')
param amount int = 30

@description('Budget time grain.')
@allowed([
  'Monthly'
  'Quarterly'
  'Annually'
])
param timeGrain string = 'Monthly'

@description('First day of the month the budget starts tracking from (yyyy-MM-01). Defaults to the first day of the current month at deploy time; override for a fixed, reproducible value if needed.')
param startDate string = '${utcNow('yyyy-MM')}-01'

@description('PLACEHOLDER — email address(es) that receive budget alerts. Replace before deploying; alerts are silently useless if left as the default.')
param contactEmails array = [
  'CHANGE_ME@example.com'
]

@description('Percent-of-budget thresholds that trigger an actual-cost alert.')
param actualThresholdPercentages array = [
  50
  80
]

@description('Percent-of-budget threshold that triggers a forecasted-cost alert.')
param forecastedThresholdPercentage int = 100

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: timeGrain
    timePeriod: {
      startDate: startDate
    }
    notifications: {
      Actual_GreaterThan_Threshold1: {
        enabled: true
        operator: 'GreaterThan'
        threshold: actualThresholdPercentages[0]
        contactEmails: contactEmails
        thresholdType: 'Actual'
      }
      Actual_GreaterThan_Threshold2: {
        enabled: true
        operator: 'GreaterThan'
        threshold: actualThresholdPercentages[1]
        contactEmails: contactEmails
        thresholdType: 'Actual'
      }
      Forecasted_GreaterThan_Threshold: {
        enabled: true
        operator: 'GreaterThan'
        threshold: forecastedThresholdPercentage
        contactEmails: contactEmails
        thresholdType: 'Forecasted'
      }
    }
  }
}

output budgetId string = budget.id
