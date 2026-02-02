# Incident Report: GitHub Actions Platform Outage

**Incident ID:** INC-2026-02-02-001  
**Date:** 2026-02-02  
**Duration:** ~6 hours (approximately 18:00 – 00:30 UTC)  
**Severity:** SEV-3 (CI/CD pipeline availability; no production impact)  
**Status:** ✅ Resolved  

---

## Executive Summary

On February 2, 2026, GitHub Actions experienced a global outage affecting hosted runner provisioning. Workflows in this repository failed to start due to runner acquisition errors. GitHub Status reported failures due to an upstream provider issue, with Azure Status showing correlated VM management disruptions during the same window. 

**No code defects were involved.** The repository's IaC templates and Python automation were validated locally during the incident window, confirming code correctness independent of CI availability.

---

## Impact Assessment

| Scope | Impact |
|-------|--------|
| **CI/CD Pipeline** | Workflows could not execute; builds queued indefinitely then failed |
| **Code Quality** | No impact; validated locally |
| **Deployment** | Delayed (no deployment was attempted during outage) |
| **Production Systems** | N/A (lab/portfolio environment) |
| **Data Loss** | None |

---

## Timeline (UTC)

| Time | Event |
|------|-------|
| ~18:00 | Workflow triggered; job entered "Queued" state and did not start |
| ~19:00 | Job failed with error: "The job was not acquired by Runner... Internal server error" |
| ~19:15 | Checked GitHub Status; incident acknowledged |
| ~19:30 | Ran local validation (`az bicep build`, `python -m py_compile`) — all passed |
| 21:13 | GitHub Status update: "Identified the root cause and are working with our upstream provider to mitigate" |
| 22:10 | GitHub Status update: "We continue to investigate failures... waiting on our upstream provider to apply the identified mitigations" |
| ~23:30 | GitHub Actions began recovering; some workflows started succeeding |
| ~00:30 | Full recovery confirmed; repository workflow completed successfully |

---

## Root Cause Analysis

### Failure Chain

```
Upstream Azure infrastructure issues (reported by status pages)
    ↓
Azure VM management operations affected
    ↓
GitHub Actions could not provision hosted runners (ubuntu-latest)
    ↓
Workflow jobs failed at runner acquisition (before any code executed)
```

### Technical Details

- **Platform:** GitHub Actions (hosted runners)
- **Upstream Dependency:** Microsoft Azure (provides VM infrastructure for GitHub-hosted runners)
- **Failure Point:** Runner provisioning/assignment stage
- **Error Observed:** `The job was not acquired by Runner... Internal server error`

### Shared Responsibility Model

| Layer | Owner | Status |
|-------|-------|--------|
| Application Code (Bicep, Python) | Repository owner | Validated correct |
| CI Workflow Definition (.yml) | Repository owner | Correct syntax |
| GitHub Actions Service | GitHub | Failed (runner provisioning) |
| VM Infrastructure | Microsoft Azure | Reported issues via Azure Status |

**Conclusion:** This was an infrastructure-level failure outside repository control. No code changes were required for resolution.

---

## Actions Taken During Incident

### Detection
- Observed workflow stuck in "Queued" state beyond normal start time
- Checked GitHub Actions UI; saw runner acquisition error
- Verified against GitHub Status page (incident confirmed)

### Investigation
- Confirmed error occurred *before* any workflow steps executed
- Ruled out code/syntax issues (failure was at infrastructure layer)
- Monitored GitHub Status and Azure Status for updates

### Mitigation
- Ran equivalent validation locally to confirm code correctness:

```bash
# Bicep template validation
az bicep build --file infra/main.bicep
# Result: Success (no errors)

# Python syntax validation  
python -m py_compile src/tag_audit.py
# Result: Success (no syntax errors)
```

- Did NOT repeatedly re-trigger workflows (understood issue was upstream; retries would not help)
- Documented incident for post-mortem

### Resolution
- No action required from repository side
- GitHub/Azure applied upstream fixes
- Workflow re-run succeeded after platform recovery

---

## Lessons Learned

### What Went Well
- Quickly identified this as a platform issue, not a code issue
- Local validation confirmed code correctness without waiting for CI recovery
- Avoided wasting time on unnecessary debugging or repeated workflow runs
- Monitored official status pages for authoritative updates

### What Could Be Improved
- **Add local validation script to repo:** Create `scripts/validate-local.sh` to standardize local checks when CI is unavailable
- **Multi-runner fallback:** Consider adding self-hosted runner option for critical workflows (out of scope for this lab)

---

## Preventative Measures Implemented

| Action | Status |
|--------|--------|
| Document incident for future reference | ✅ Complete (this report) |
| Add local validation script | 🔄 Planned |
| Monitor status pages during CI operations | ✅ Ongoing practice |

---

## References

- [GitHub Status](https://www.githubstatus.com/) — "Incident with Actions" (2026-02-02)
- [Azure Status](https://status.azure.com/) — Storage/VM Scale Set incident (2026-02-02)

---

## Appendix: Key Takeaways for Cloud Operations

This incident reinforced several core principles:

1. **Check status pages first.** Before debugging code, verify the platform is healthy.

2. **Local validation is essential.** CI unavailability should not block code verification. Always have a local fallback.

3. **Understand the shared responsibility model.** Know which layers you control and which you don't. Don't waste time "fixing" what isn't yours to fix.

4. **Document during the incident.** Capture timestamps, errors, and actions while they're fresh. This enables accurate post-mortems.

5. **Stay calm and wait for upstream resolution.** Repeated retries during a platform outage create noise, not signal.

---

*Report authored: 2026-02-03*  
*Repository: [azure-ops-lab](https://github.com/bmetcalf21/azure-ops-lab)*
