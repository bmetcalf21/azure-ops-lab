# Region Decision

**Run timestamp:** 2026-02-10T100120
**Selected region:** westus
**Resource group:** azure-ops-lab-rg-westus

## Rationale

As of Feb 10, 2026, operational default is westus (F1 quota approved).
eastus2 is documented fallback (F1 quota also approved).
westus2 and westus3 remain unavailable for this subscription.

## Precheck signals

See `00-quota-status.txt` in this run folder for region support snapshot.
Actual quota enforcement occurs at what-if and deployment time.
