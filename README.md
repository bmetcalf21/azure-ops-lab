# Azure Operations & Governance Lab

![Build Status](https://github.com/bmetcalf21/azure-ops-lab/actions/workflows/build.yml/badge.svg)

## Overview

A practical Azure cloud operations lab demonstrating infrastructure-as-code, RBAC governance, resource tagging, and observability. This project provisions a sample workload (App Service + Storage) with proper identity management, monitoring, and cost controls suitable for a spin-up/spin-down lab environment.

**Key capabilities:**
- Infrastructure as Code using Azure Bicep
- Entra ID RBAC configuration with role assignments
- Resource tagging for governance and cost tracking
- Azure Monitor and Application Insights integration
- Automated CI/CD with GitHub Actions
- Python-based compliance auditing tools

## Architecture

**Resource Group:** azure-ops-lab-rg

**Compute & Web:**
- App Service Plan (F1 Free Tier)
  - Web App (Python 3.11, Linux)
  - System-assigned managed identity

**Storage:**
- Storage Account (Standard_LRS, StorageV2)

**Observability:**
- Application Insights (connected to all resources)
- Log Analytics Workspace (centralized logging)

**Governance:**
- RBAC: Contributor role assignment (Web App identity -> Resource Group)
- Tags: environment=lab, owner=brandon-metcalf, project=azure-ops-lab

## What's Implemented

- **IaC Templates:** Complete Bicep definitions for all Azure resources
- **CI Validation:** GitHub Actions workflow validates syntax without requiring Azure credentials
- **Python Tooling:** Tag compliance auditor using Azure SDK
- **Governance Strategy:** Consistent tagging and RBAC patterns
- **Teardown Automation:** Scripts for cost-effective resource cleanup

## What's Next

- Deploy to live Azure subscription (requires OIDC federation setup)
- Configure Application Insights alerts for performance/availability monitoring
- Implement automated cost tracking and reporting
- Add integration tests for deployed resources

## Prerequisites

- Azure subscription (free tier compatible)
- Azure CLI (`az`) installed
- Bicep CLI installed
- Python 3.9+ with pip
- GitHub account (for Actions workflows)

## Deployment Instructions

### 1. Setup Azure Resources

Create a resource group:
```bash
az group create --name azure-ops-lab-rg --location westus2
```

### 2. Deploy Infrastructure

Deploy using Bicep:
```bash
az deployment group create \
  --resource-group azure-ops-lab-rg \
  --template-file infra/main.bicep \
  --parameters infra/parameters.json
```

### 3. Verify Deployment

List deployed resources:
```bash
az resource list --resource-group azure-ops-lab-rg --output table
```

### 4. Run Tag Compliance Audit

Install Python dependencies:
```bash
pip install azure-identity azure-mgmt-resource
```

Run the audit script:
```bash
python src/tag_audit.py \
  --subscription-id YOUR_SUBSCRIPTION_ID \
  --resource-group azure-ops-lab-rg \
  --output-format json
```

## Teardown Instructions

To delete all resources and avoid ongoing charges:

```bash
./scripts/teardown.sh azure-ops-lab-rg
```

Or manually:
```bash
az group delete --name azure-ops-lab-rg --yes --no-wait
```

## Governance

### RBAC Strategy

- **Principle of Least Privilege:** Role assignments scoped to resource group level
- **Entra ID Integration:** Uses Azure RBAC for identity-based access control
- **Role Used:** Contributor role for deployment automation (read/write, no permission management)

### Tagging Strategy

All resources include mandatory tags for governance:

| Tag | Purpose | Example Value |
|-----|---------|---------------|
| `environment` | Deployment stage | `lab`, `dev`, `prod` |
| `owner` | Responsible party | `brandon-metcalf` |
| `project` | Cost allocation | `azure-ops-lab` |

Tags enable:
- Cost tracking and allocation
- Automated compliance auditing
- Resource lifecycle management
- Environment isolation

## Observability

### Monitoring Components

- **Application Insights:** Application performance monitoring (APM)
  - Request rates and response times
  - Dependency tracking (Storage Account calls)
  - Exception logging
  - Custom metrics and events

- **Log Analytics Workspace:** Centralized log aggregation
  - Platform logs from all resources
  - Query using KQL (Kusto Query Language)
  - Retention configured for cost optimization

### Planned Alerts

- App Service response time > 2s
- Storage Account throttling events
- Failed authentication attempts
- Budget threshold warnings

## Cost Control

**Designed for minimal cost:**
- **App Service:** F1 Free tier (60 CPU minutes/day)
- **Storage Account:** Pay-as-you-go with minimal usage
- **Application Insights:** First 5GB/month free
- **Log Analytics:** First 5GB/month free

**Spin-up/Spin-down approach:**
- Use `az group delete` to remove all resources when not in use
- Redeploy from IaC templates when needed
- No persistent data in lab environment

**Estimated monthly cost:** ~$0 with free tiers (if kept within limits)

## CI/CD Workflows

### Build & Validate (Always Runs)
- Validates Bicep syntax
- Checks Python code for errors
- Runs on every push to main
- **No Azure credentials required**

### Deploy to Azure (Manual Trigger)
- Uses OIDC federation (no secrets in repo)
- Requires Azure federated credentials setup
- Manual workflow_dispatch trigger
- Environment-based approvals

## Project Structure

```
azure-ops-lab/
+-- README.md                    # This file
+-- docs/
|   +-- incidents/               # Incident reports and RCAs
+-- infra/
|   +-- main.bicep               # Infrastructure as Code definitions
|   +-- parameters.json          # Deployment parameters
+-- src/
|   +-- tag_audit.py             # Compliance auditing tool
+-- scripts/
|   +-- teardown.sh              # Resource cleanup script
+-- .github/
    +-- workflows/
        +-- build.yml            # Syntax validation (no Azure creds)
        +-- deploy.yml           # Deployment workflow (manual)
```

## Incident History

This project is maintained as a production-like environment. Real operational incidents are documented here to practice incident response and root cause analysis.

| Date | Incident | Impact | Status |
|------|----------|--------|--------|
| 2026-02-02 | [GitHub Actions Platform Outage](docs/incidents/2026-02-02-github-actions-platform-outage.md) | CI delayed ~6hrs (upstream Azure issue) | Resolved |

See [docs/incidents/](docs/incidents/) for detailed incident reports and post-mortems.

## Contributing

This is a personal lab project for learning Azure operations. Feel free to fork and adapt for your own learning purposes.

## License

MIT License - Free to use and modify.

---

**Author:** Brandon Metcalf
**GitHub:** [@bmetcalf21](https://github.com/bmetcalf21)
**Project:** azure-ops-lab
