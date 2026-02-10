#!/bin/bash
################################################################################
# Evidence Capture Script
#
# Automates the full deploy → verify → teardown proof cycle and captures
# timestamped artifacts for the docs/proof/runs/ folder.
#
# Usage:
#   ./capture-evidence.sh                                    # Defaults (westus)
#   ./capture-evidence.sh --location westus                  # Explicit region
#   ./capture-evidence.sh --location eastus2 --resource-group azure-ops-lab-rg-eastus2
#   ./capture-evidence.sh --keep-resources                   # Skip teardown
#
# Environment variables:
#   REQUIRED_SUB_NAME   Subscription name guard (default: current subscription)
#                       Set to enforce a specific subscription, e.g.:
#                       REQUIRED_SUB_NAME="Pay-As-You-Go" ./capture-evidence.sh
#
# Author: Brandon Metcalf
# Project: azure-ops-lab
################################################################################

set -euo pipefail

# --- Defaults ---
RG="azure-ops-lab-rg-westus"
LOCATION="westus"
KEEP_RESOURCES=false
QUOTA_CHECK_REGIONS="westus westus2 westus3 eastus2"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group|-g)
            RG="$2"
            shift 2
            ;;
        --location|-l)
            LOCATION="$2"
            shift 2
            ;;
        --keep-resources)
            KEEP_RESOURCES=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--resource-group NAME] [--location REGION] [--keep-resources]"
            echo ""
            echo "Options:"
            echo "  --resource-group, -g   Resource group name (default: azure-ops-lab-rg-westus)"
            echo "  --location, -l         Azure region (default: westus)"
            echo "  --keep-resources       Skip teardown (leave resources deployed)"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  REQUIRED_SUB_NAME      Subscription name guard (default: current sub)"
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1"
            exit 1
            ;;
    esac
done

# --- Timestamped output directory ---
TIMESTAMP=$(date +%Y-%m-%dT%H%M%S)
RUN_DIR="docs/proof/runs/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

echo "========================================"
echo "Evidence Capture — ${TIMESTAMP}"
echo "========================================"
echo "Resource Group: ${RG}"
echo "Location:       ${LOCATION}"
echo "Output:         ${RUN_DIR}"
echo "Keep Resources: ${KEEP_RESOURCES}"
echo ""

# --- Pre-flight: subscription safety check ---
echo "[Pre-flight] Validating subscription..."
CURRENT_SUB=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)

if [[ -n "${REQUIRED_SUB_NAME:-}" ]]; then
    if [[ "$CURRENT_SUB" != *"$REQUIRED_SUB_NAME"* ]]; then
        echo "Error: Current subscription is '$CURRENT_SUB'. Expected '$REQUIRED_SUB_NAME'."
        echo "Safety check failed. Aborting to prevent accidental spend or deletion in the wrong context."
        exit 1
    fi
fi
echo "Subscription: ${CURRENT_SUB} (${SUB_ID})"
echo ""

# --- Pre-flight: RG region collision check ---
echo "[Pre-flight] Checking for resource group region collision..."
EXISTING_RG_LOCATION=$(az group show --name "$RG" --query location -o tsv 2>/dev/null || echo "")
if [[ -n "$EXISTING_RG_LOCATION" && "$EXISTING_RG_LOCATION" != "$LOCATION" ]]; then
    echo "Error: Resource group '${RG}' already exists in '${EXISTING_RG_LOCATION}' but you requested '${LOCATION}'."
    echo "Azure resource groups cannot be moved between regions."
    echo ""
    echo "Suggested fix: use --resource-group azure-ops-lab-rg-${LOCATION}"
    exit 1
fi
echo "No RG collision detected."
echo ""

# --- Artifact 00: Region support + deployment precheck signals ---
echo "[00] Capturing region support and precheck signals..."
{
    echo "Region Support + Deployment Precheck Signals"
    echo "Captured: ${TIMESTAMP}"
    echo "Subscription: ${CURRENT_SUB} (${SUB_ID})"
    echo "Note: This is a supportability signal, not authoritative quota."
    echo "Actual quota enforcement occurs at what-if/deploy time."
    echo "========================================"
    # az appservice list-locations returns display names (e.g., "East US 2")
    # Resolve API name -> display name via az account list-locations for matching
    F1_LOCATIONS=$(az appservice list-locations --sku F1 --query "[].name" -o tsv 2>/dev/null || echo "")
    for region in $QUOTA_CHECK_REGIONS; do
        echo ""
        echo "--- ${region} ---"
        DISPLAY_NAME=$(az account list-locations --query "[?name=='${region}'].displayName" -o tsv 2>/dev/null || echo "")
        if [[ -n "$DISPLAY_NAME" ]] && echo "$F1_LOCATIONS" | grep -Fxi "$DISPLAY_NAME" > /dev/null; then
            echo "F1 SKU: region supported (${DISPLAY_NAME})"
        else
            echo "F1 SKU: region not listed (may lack capacity or support)"
        fi
    done
} > "${RUN_DIR}/00-quota-status.txt" 2>&1
echo "Saved: ${RUN_DIR}/00-quota-status.txt"

# --- Pre-flight: F1 region support fail-fast ---
echo "[Pre-flight] Verifying F1 region support in ${LOCATION}..."
F1_LOCATIONS_CHECK=$(az appservice list-locations --sku F1 --query "[].name" -o tsv 2>/dev/null || echo "")
LOCATION_DISPLAY=$(az account list-locations --query "[?name=='${LOCATION}'].displayName" -o tsv 2>/dev/null || echo "")
if [[ -z "$LOCATION_DISPLAY" ]] || ! echo "$F1_LOCATIONS_CHECK" | grep -Fxi "$LOCATION_DISPLAY" > /dev/null; then
    echo "Error: F1 App Service Plan does not appear to be supported in '${LOCATION}'."
    echo "Check precheck signals in: ${RUN_DIR}/00-quota-status.txt"
    echo "Try a different region: --location eastus2"
    exit 1
fi
echo "F1 region support confirmed in ${LOCATION} (${LOCATION_DISPLAY})."
echo ""

# --- Artifact 01: Region decision ---
echo "[01] Recording region decision..."
cat > "${RUN_DIR}/01-region-decision.md" <<REGIONEOF
# Region Decision

**Run timestamp:** ${TIMESTAMP}
**Selected region:** ${LOCATION}
**Resource group:** ${RG}

## Rationale

As of Feb 10, 2026, operational default is westus (F1 quota approved).
eastus2 is documented fallback (F1 quota also approved).
westus2 and westus3 remain unavailable for this subscription.

## Precheck signals

See \`00-quota-status.txt\` in this run folder for region support snapshot.
Actual quota enforcement occurs at what-if and deployment time.
REGIONEOF
echo "Saved: ${RUN_DIR}/01-region-decision.md"

# --- Artifact 02: Pre-deploy check ---
echo "[02] Capturing pre-deploy state..."
az resource list --resource-group "$RG" --output table > "${RUN_DIR}/02-pre-deploy-check.txt" 2>&1 \
    || echo "RG '${RG}' does not exist yet (expected for fresh deploy)" > "${RUN_DIR}/02-pre-deploy-check.txt"
echo "Saved: ${RUN_DIR}/02-pre-deploy-check.txt"

# --- Artifact 03: What-if output ---
echo "[03] Running what-if preview..."
# Ensure RG exists for what-if
az group create --name "$RG" --location "$LOCATION" \
    --tags environment=lab owner=brandon-metcalf project=azure-ops-lab \
    --output none 2>/dev/null || true
az deployment group what-if \
    --resource-group "$RG" \
    --template-file infra/main.bicep \
    --parameters infra/parameters.json \
    --parameters location="$LOCATION" \
    > "${RUN_DIR}/03-deploy-whatif-output.txt" 2>&1
echo "Saved: ${RUN_DIR}/03-deploy-whatif-output.txt"

# --- Artifact 04: Deploy ---
echo "[04] Running deployment..."
./scripts/deploy.sh --yes --resource-group "$RG" --location "$LOCATION" \
    | tee "${RUN_DIR}/04-deploy-log.txt"
echo "Saved: ${RUN_DIR}/04-deploy-log.txt"

# --- Artifact 05: SKU verification ---
echo "[05] Verifying SKU..."
az appservice plan list -g "$RG" \
    --query "[].{Name:name, Tier:sku.tier, SKU:sku.name}" -o table \
    > "${RUN_DIR}/05-sku-verification.txt"
echo "Saved: ${RUN_DIR}/05-sku-verification.txt"

# --- Artifact 06: Resource inventory ---
echo "[06] Capturing resource inventory..."
az resource list -g "$RG" \
    --query "[].{Name:name, Type:type, Location:location, Tags:tags}" -o table \
    > "${RUN_DIR}/06-resource-inventory.txt"
echo "Saved: ${RUN_DIR}/06-resource-inventory.txt"

# --- Artifact 07: Tag audit ---
echo "[07] Running tag audit..."
python3 src/tag_audit.py \
    --subscription-id "$SUB_ID" \
    --resource-group "$RG" \
    --output-format json \
    > "${RUN_DIR}/07-tag-audit.json"
echo "Saved: ${RUN_DIR}/07-tag-audit.json"

# --- Teardown (unless --keep-resources) ---
if [[ "$KEEP_RESOURCES" == true ]]; then
    echo ""
    echo "[Skipping teardown] --keep-resources flag set."
    echo "Resources remain deployed in ${RG}."
    echo "Teardown manually when done: ./scripts/teardown.sh ${RG}"
    TEARDOWN_STATUS="Skipped (--keep-resources)"
    TEARDOWN_ARTIFACTS=""
else
    # --- Artifact 08: Teardown ---
    echo "[08] Running teardown..."
    echo "yes" | ./scripts/teardown.sh "$RG" | tee "${RUN_DIR}/08-teardown-log.txt"
    echo "Saved: ${RUN_DIR}/08-teardown-log.txt"

    # --- Artifact 09: Post-teardown check ---
    echo "[09] Verifying cleanup..."
    RG_EXISTS=$(az group exists --name "$RG")
    echo "Resource group '${RG}' exists: ${RG_EXISTS}" > "${RUN_DIR}/09-post-teardown-check.txt"
    echo "Saved: ${RUN_DIR}/09-post-teardown-check.txt"
    if [[ "$RG_EXISTS" == "false" ]]; then
        TEARDOWN_STATUS="Complete (RG deleted)"
    else
        TEARDOWN_STATUS="In progress (async delete initiated, RG still exists)"
    fi
    TEARDOWN_ARTIFACTS="| \`08-teardown-log.txt\` | Teardown execution log |
| \`09-post-teardown-check.txt\` | RG deletion confirmation |"
fi

# --- RUN_SUMMARY.md ---
RESOURCE_COUNT=$(wc -l < "${RUN_DIR}/06-resource-inventory.txt" | tr -d ' ')
# Subtract header lines from table output (2 lines: header + separator)
RESOURCE_COUNT=$((RESOURCE_COUNT > 2 ? RESOURCE_COUNT - 2 : 0))

cat > "${RUN_DIR}/RUN_SUMMARY.md" <<SUMMARYEOF
# Evidence Run Summary

**Timestamp:** ${TIMESTAMP}
**Region:** ${LOCATION}
**Resource Group:** ${RG}
**Subscription:** ${CURRENT_SUB}
**Resources Deployed:** ${RESOURCE_COUNT}
**Teardown:** ${TEARDOWN_STATUS}
**Estimated Cost:** \$0.00 (F1 Free tier, ephemeral deployment)

## Artifacts

| File | Description |
|------|-------------|
| \`00-quota-status.txt\` | Region support and precheck signals |
| \`01-region-decision.md\` | Region selection rationale |
| \`02-pre-deploy-check.txt\` | Pre-deploy resource state |
| \`03-deploy-whatif-output.txt\` | Bicep what-if preview |
| \`04-deploy-log.txt\` | Full deployment log |
| \`05-sku-verification.txt\` | App Service Plan F1/Free confirmation |
| \`06-resource-inventory.txt\` | Deployed resources with tags |
| \`07-tag-audit.json\` | Tag compliance audit results |
${TEARDOWN_ARTIFACTS}

## Manual Artifacts (capture separately)

- \`budget-config.png\` — Subscription budget alert configuration
- \`daily-caps.png\` — Log Analytics and App Insights daily cap settings
SUMMARYEOF
echo "Saved: ${RUN_DIR}/RUN_SUMMARY.md"

echo ""
echo "========================================"
echo "Evidence capture complete."
echo "All artifacts in: ${RUN_DIR}"
echo "========================================"
echo "Note: You still need to manually capture:"
echo "  - budget-config.png"
echo "  - daily-caps.png"
echo "========================================"
