# Incident Report: F1 App Service Plan Regional Quota Constraints

**Incident ID:** INC-2026-02-07-001
**Date:** 2026-02-07
**Duration:** ~2 days (Feb 5 discovery through Feb 7 mitigation)
**Severity:** SEV-4 (Operational constraint; no outage, no cost impact)
**Status:** Mitigated (westus support request pending)

---

## Executive Summary

During Pay-As-You-Go subscription setup for the first live deployment proof cycle, F1 (Free tier) App Service Plan quota was unavailable in the originally planned regions (westus2, westus3). Quota was successfully obtained in eastus2. A manual support request was filed for westus F1 capacity.

**No cost impact occurred.** The constraint was discovered before any billable resources were deployed. The operational default was updated to eastus2 to unblock evidence capture.

---

## Impact Assessment

| Scope | Impact |
|-------|--------|
| **Deployment** | Blocked in westus2 (original default); unblocked via eastus2 |
| **Cost** | None — no resources deployed during constraint window |
| **CI/CD** | No impact; CI does not require Azure resources |
| **Evidence Capture** | Delayed until eastus2 quota was approved |
| **Data Loss** | None |

---

## Timeline

| Date / Time | Event |
|-------------|-------|
| Feb 5, 2026 | First quota failure encountered during westus2 deployment flow |
| Feb 7, 2026 | Subscription upgraded to Pay-As-You-Go |
| Feb 7, 2026 | Requested F1 quota in eastus2 — approved (1 of 1) |
| Feb 7, 2026 | Requested F1 quota in westus — auto-quota request failed |
| Feb 7, 2026, 11:47:12 AM | Filed manual support request for westus F1 quota (request #2602070010001016) |
| Feb 7, 2026 | Updated all runtime defaults to eastus2; documented region policy |

---

## Root Cause Analysis

### Failure Chain

```
Azure regional capacity constraints
    ↓
F1 (Free) App Service Plan SKU unavailable in westus2 and westus3
    ↓
Auto-quota request failed for westus
    ↓
First deployment proof cycle blocked in planned region
```

### Technical Details

- **Resource type:** Microsoft.Web/serverfarms (App Service Plan)
- **SKU requested:** F1 (Free, not zone-redundant)
- **Regions checked:** westus2, westus3, westus, eastus2
- **Result:** Only eastus2 had available F1 capacity for this subscription

### Root Cause Class

Azure regional capacity constraint. Free-tier SKUs have limited availability and are subject to regional capacity limits that vary by subscription and time. This is not a code defect or configuration error.

---

## Actions Taken

### Detection
- Attempted deployment in westus2 during PAYG setup
- Received quota unavailability error from Azure Resource Manager

### Investigation
- Checked F1 availability across four regions (westus, westus2, westus3, eastus2)
- Confirmed eastus2 had capacity; westus2 and westus3 did not
- westus auto-quota request was denied; escalated to manual support

### Mitigation
- Obtained F1 quota in eastus2 (approved immediately)
- Updated all runtime defaults to eastus2:
  - `infra/parameters.json`
  - `scripts/deploy.sh`
  - `scripts/deploy-fast.ps1`
  - `.github/workflows/deploy.yml`
  - `capture-evidence.sh`
- Updated default resource group to `azure-ops-lab-rg-eastus2` to avoid RG location collisions
- Updated region policy in `CLAUDE.md`

### Pending
- Manual support request #2602070010001016 for westus F1 quota (open as of Feb 7, 2026)
- Once westus is approved, it becomes the planned secondary region

---

## Lessons Learned

### What Went Well
- Discovered the constraint before any billable resources were deployed (zero cost impact)
- Quickly pivoted to eastus2 rather than waiting for support resolution
- Updated all runtime defaults consistently (no partial migration)
- Documented the constraint as an operational incident, not just a one-off fix

### What Could Be Improved
- **Add quota pre-check to evidence capture script:** Before deploying, verify F1 capacity exists in the target region
- **Document region capacity as an operational concern:** Free-tier availability is not guaranteed in all regions

---

## Corrective Actions

| Action | Status |
|--------|--------|
| Update runtime defaults to eastus2 | In progress (edits landed, pending validation) |
| Add RG region collision avoidance (region-suffixed RG names) | In progress (edits landed, pending validation) |
| Add quota pre-check to `capture-evidence.sh` | In progress (script rewrite pending) |
| Update CLAUDE.md Operational Region Policy | In progress (edits landed, pending validation) |
| File manual support request for westus F1 | Done (#2602070010001016) |
| Revise region policy once westus approved | Pending support response |

---

## STAR Summary

**Situation:** During PAYG subscription setup, F1 App Service Plan quota was unavailable in the planned deployment region (westus2), blocking the first live proof cycle.

**Task:** Obtain F1 capacity in an available region, update all runtime defaults consistently, and document the constraint for operational awareness.

**Action:** Checked quota across four regions, obtained approval in eastus2, updated all config/scripts/policy to use eastus2, filed support request for westus as planned secondary, and added quota pre-check to evidence automation.

**Result:** Deployment unblocked in eastus2 with zero cost impact. All runtime defaults updated consistently. Operational region policy documented with date-stamped status. Support request pending for expanded regional coverage.

---

*Report authored: 2026-02-07*
*Repository: [azure-ops-lab](https://github.com/bmetcalf21/azure-ops-lab)*
