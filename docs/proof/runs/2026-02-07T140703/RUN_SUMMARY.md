# Evidence Run Summary

**Timestamp:** 2026-02-07T140703
**Region:** eastus2
**Resource Group:** azure-ops-lab-rg-eastus2
**Subscription:** Azure subscription 1
**Resources Deployed:** 5 (+ 1 Azure-managed action group)
**Teardown:** Verified complete at 15:39:11 (`az group exists` returned `false`)
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
| `08-teardown-log.txt` | Teardown request and polling evidence |
| `09-post-teardown-check.txt` | RG deletion confirmation (`false`) |
| `budget-config.png` | Subscription budget alert configuration ($1 threshold) |
| `daily-caps-loganalytics.png` | Log Analytics daily cap (0.5 GB/day) |
| `daily-caps-appinsights.png` | App Insights daily cap (0.5 GB/day) |

## Notes

- **Tag audit exit code 1:** One non-compliant resource was detected — `Application Insights Smart Detection` (`microsoft.insights/actiongroups`). This is an Azure-managed action group auto-created by Application Insights. It is not defined in our Bicep template and cannot be tagged via IaC. All 5 IaC-controlled resources passed tag compliance (environment, owner, project).
- **F1 SKU verified:** App Service Plan tier confirmed as Free (F1) post-deploy.
- **Region:** eastus2 selected as operational primary due to F1 quota availability (see `01-region-decision.md`).
