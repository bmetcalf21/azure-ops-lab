# Region Decision

**Run timestamp:** 2026-02-07T140703
**Selected region:** eastus2
**Resource group:** azure-ops-lab-rg-eastus2

## Rationale

As of Feb 7, 2026, operational default is eastus2 due to F1 quota availability.
westus is planned secondary pending support approval (#2602070010001016).
westus2 and westus3 are currently unavailable for this subscription.

## Precheck signals

See `00-quota-status.txt` in this run folder for region support snapshot.
Actual quota enforcement occurs at what-if and deployment time.
