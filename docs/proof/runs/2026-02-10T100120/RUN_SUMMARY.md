# Evidence Run Summary

**Timestamp:** 2026-02-10T100120
**Region:** westus
**Resource Group:** azure-ops-lab-rg-westus
**Subscription:** Azure subscription 1
**Resources Deployed:** 5
**Teardown:** Complete (RG exists: true)
**Estimated Cost:** $0.00 (F1 Free tier, ephemeral deployment)

## Artifacts

| File | Description |
|------|-------------|
| `00-quota-status.txt` | Region support and precheck signals |
| `01-region-decision.md` | Region selection rationale |
| `02-pre-deploy-check.txt` | Pre-deploy resource state |
| `03-deploy-whatif-output.txt` | Bicep what-if preview |
| `04-deploy-log.txt` | Full deployment log |
| `05-sku-verification.txt` | App Service Plan F1/Free confirmation |
| `06-resource-inventory.txt` | Deployed resources with tags |
| `07-tag-audit.json` | Tag compliance audit results |
| `08-teardown-log.txt` | Teardown execution log |
| `09-post-teardown-check.txt` | RG deletion confirmation |

## Manual Artifacts (capture separately)

- `budget-config.png` — Subscription budget alert configuration
- `daily-caps.png` — Log Analytics and App Insights daily cap settings
