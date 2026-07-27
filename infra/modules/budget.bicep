// ---------------------------------------------------------------------------
// budget.bicep
// Subscription-level consumption budget with a small set of email alert
// thresholds. Cost-control guardrail for a demo landing zone.
// ---------------------------------------------------------------------------
targetScope = 'subscription'

@description('Environment tag/suffix used to build the default budget name when budgetName is not explicitly overridden (e.g. dev, prod). Keeps dev/prod budgets from colliding — Microsoft.Consumption/budgets names are unique per subscription.')
param environmentName string = 'dev'

@description('Name of the budget. Defaults to budget-portfolio-landingzone-<environmentName> so dev and prod never collide on the same budget name at subscription scope.')
param budgetName string = 'budget-portfolio-landingzone-${environmentName}'

@description('Monthly budget amount in USD.')
param amount int = 30

@description('Budget time grain.')
@allowed([
  'Monthly'
  'Quarterly'
  'Annually'
])
param timeGrain string = 'Monthly'

@description('REQUIRED — first day of the month the budget starts tracking from (yyyy-MM-01), e.g. 2026-07-01. Deliberately has no utcNow()-derived default: a value that changes on every deployment based on "today" breaks idempotency (every re-deploy would attempt to change timePeriod.startDate, which Microsoft.Consumption/budgets treats as immutable after creation and rejects). Supply a fixed literal in the calling bicepparam and only change it if you are intentionally recreating the budget.')
param startDate string

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
