# High-Availability & Multi-Region Design

> **Status: Design-only.** This document describes how the azure-ops-lab would scale to a highly available, multi-region architecture if budget constraints were lifted. No multi-region resources are deployed by this repo.

---

## Current Architecture (Single-Region, Zero-Cost)

```
                        westus2
           ┌──────────────────────────────┐
           │      azure-ops-lab-rg        │
           │                              │
           │  ┌─────────────────────┐     │
Internet ──┼─►│  App Service (F1)   │     │
           │  │  Managed Identity   │     │
           │  │  TLS 1.2 enforced   │     │
           │  └────────┬────────────┘     │
           │           │                  │
           │  ┌────────▼────────────┐     │
           │  │  Application        │     │
           │  │  Insights           │     │
           │  └────────┬────────────┘     │
           │           │                  │
           │  ┌────────▼────────────┐     │
           │  │  Log Analytics      │     │
           │  │  Workspace          │     │
           │  └─────────────────────┘     │
           │                              │
           │  ┌─────────────────────┐     │
           │  │  Storage Account    │     │
           │  │  Standard_LRS       │     │
           │  └─────────────────────┘     │
           └──────────────────────────────┘

Cost: $0/month (F1 free tier, free ingestion caps)
RTO:  Dependent on Azure region recovery (hours)
RPO:  Last deployment commit (IaC is source of truth)
```

**Design rationale**: This lab exists to demonstrate operational competence, not to run production workloads. Single-region F1 keeps cost at zero while still proving provisioning, governance, monitoring, and teardown discipline.

---

## Target Architecture (Multi-Region HA)

If this were a production workload requiring high availability, the architecture would extend to a paired-region active-passive deployment.

### Azure Paired Region: West US 2 + West Central US

Azure maintains [paired regions](https://learn.microsoft.com/en-us/azure/reliability/cross-region-replication-azure) for coordinated recovery. **West US 2** is paired with **West Central US**, which provides:

- Sequential region recovery (one region prioritized during broad outages)
- Data residency within the same geography (United States)
- Physical isolation (separate datacenter clusters)

```
                    Azure Front Door
                   (Global load balancer)
                    ┌──────┴──────┐
                    │  Health     │
                    │  Probes     │
                    ├─────┬───────┤
                    ▼     │       ▼
              westus2     │    westcentralus
         ┌────────────┐  │  ┌────────────┐
         │  PRIMARY    │  │  │  SECONDARY │
         │             │  │  │  (standby) │
         │  App Svc    │  │  │  App Svc   │
         │  (S1/P1v3)  │  │  │  (S1/P1v3) │
         │  + MI       │  │  │  + MI      │
         │             │  │  │            │
         │  App        │  │  │  App       │
         │  Insights   │  │  │  Insights  │
         │  ▼          │  │  │  ▼         │
         │  Log        │  │  │  Log       │
         │  Analytics  │  │  │  Analytics │
         │             │  │  │            │
         │  Storage    │  │  │  Storage   │
         │  (RA-GRS)───┼──┼──┤  (read     │
         │             │  │  │  replica)  │
         └────────────┘  │  └────────────┘
                         │
                    DNS failover
                    via Front Door
                    health probes
```

### Component Decisions

| Component | Current (Lab) | HA Target | Rationale |
|---|---|---|---|
| **Load Balancer** | None | Azure Front Door (Standard) | Global anycast, SSL offload, health-probe failover. Preferred over Traffic Manager for HTTP workloads. |
| **App Service Plan** | F1 (Free) | S1 or P1v3 per region | F1 does not support custom domains, scaling, or deployment slots. S1 is the minimum for HA features. |
| **Storage** | Standard_LRS | RA-GRS | Read-access geo-redundant storage enables read from secondary during primary outage. |
| **App Insights** | Single workspace | Per-region workspace | Each region sends telemetry to its own workspace. Cross-workspace KQL queries provide unified view. |
| **Log Analytics** | Single workspace | Per-region + cross-query | Avoids cross-region ingestion latency. Central dashboards use `workspace()` function in KQL. |

---

## Failover & Disaster Recovery

### Active-Passive Model

The recommended pattern for this workload class is **active-passive**:

- **Primary (West US 2)**: Handles all traffic. Full read-write.
- **Secondary (West Central US)**: Warm standby. App deployed but receives no traffic until failover. Storage readable via RA-GRS.

Active-active is not recommended here because:
- The application is a simple web app, not a globally distributed service
- Active-active adds complexity (data synchronization, conflict resolution) without proportional benefit
- Cost doubles immediately with active-active

### Failover Trigger

Azure Front Door monitors the primary backend via health probes (default: 30-second intervals). When the primary fails health checks:

1. Front Door routes traffic to the secondary backend (automatic, no DNS TTL delay)
2. Storage reads fail over to the RA-GRS secondary endpoint
3. Alert fires to on-call engineer for assessment

### Recovery Targets

| Metric | Target | Achievable With |
|---|---|---|
| **RTO** (Recovery Time Objective) | < 5 minutes | Front Door automatic failover + warm standby app |
| **RPO** (Recovery Point Objective) | < 15 minutes | RA-GRS replication lag (typically seconds, SLA ≤ 15 min) |

### Manual Failback

After the primary region recovers:
1. Verify primary health via Front Door health dashboard
2. Confirm storage replication is caught up (`az storage account show --query geoReplicationStats`)
3. Front Door automatically resumes routing to primary once health probes pass

No manual DNS changes required.

---

## Why This Lab Stays Single-Region

| Factor | Single-Region (Current) | Multi-Region (Target) |
|---|---|---|
| **Monthly cost** | $0 | ~$70-150+ |
| **Complexity** | 1 resource group, 5 resources | 2 resource groups, 10+ resources, Front Door |
| **Deployment time** | ~2 minutes | ~5-10 minutes |
| **Interview value** | Proves IaC, governance, monitoring, FinOps | Proves HA architecture understanding |

The single-region lab proves **operational execution** (deploy, monitor, govern, teardown). This document proves **architectural thinking** (HA design, paired regions, RTO/RPO, failover mechanics).

Both are valuable interview signals. Only one costs $0.

### Cost Breakdown Estimate (Multi-Region)

| Resource | Per-Region Cost | x2 Regions | Notes |
|---|---|---|---|
| App Service Plan S1 | ~$55/mo | ~$110/mo | Minimum for custom domains + slots |
| Storage RA-GRS | ~$5/mo | ~$5/mo | Single account with geo-replication |
| Front Door Standard | ~$35/mo | ~$35/mo | Global resource, not per-region |
| Log Analytics | ~$2.76/GB | varies | Free tier covers 5 GB/mo per workspace |
| App Insights | included | included | Uses Log Analytics ingestion |
| **Total estimate** | | **~$150/mo** | Rough estimate; actual depends on traffic |

---

## Extension Path

If this lab were promoted to a production-like demo:

1. **Phase 1**: Upgrade App Service Plan to S1 in westus2 (enables deployment slots, custom domains)
2. **Phase 2**: Add RA-GRS to storage account (single config change in Bicep)
3. **Phase 3**: Deploy second region (westcentralus) using same Bicep template with regional parameters
4. **Phase 4**: Add Azure Front Door with backend pools pointing to both regions
5. **Phase 5**: Configure health probes, failover priority, and alerting

Each phase is an incremental Bicep change. The IaC-first approach means the entire multi-region stack is reproducible and teardown-safe.
