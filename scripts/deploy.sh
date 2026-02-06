#!/bin/bash
################################################################################
# Azure Operations Lab - Deploy Script
#
# Deploys infrastructure via Bicep with a mandatory what-if preview gate.
# Supports interactive confirmation (default) and non-interactive CI mode (--yes).
#
# Usage:
#   ./scripts/deploy.sh                          # Interactive (default)
#   ./scripts/deploy.sh --yes                    # Non-interactive / CI mode
#   ./scripts/deploy.sh --resource-group my-rg   # Custom resource group
#   ./scripts/deploy.sh --location eastus         # Custom region
#
# Author: Brandon Metcalf
# Project: azure-ops-lab
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Defaults
RESOURCE_GROUP="azure-ops-lab-rg"
LOCATION="westus2"
TEMPLATE_FILE="infra/main.bicep"
PARAMETERS_FILE="infra/parameters.json"
DEPLOYMENT_NAME="deploy-$(date +%Y%m%d-%H%M%S)"
AUTO_APPROVE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group|-g)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location|-l)
            LOCATION="$2"
            shift 2
            ;;
        --yes|-y)
            AUTO_APPROVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--resource-group NAME] [--location REGION] [--yes]"
            echo ""
            echo "Options:"
            echo "  --resource-group, -g   Resource group name (default: azure-ops-lab-rg)"
            echo "  --location, -l         Azure region (default: westus2)"
            echo "  --yes, -y              Skip confirmation prompt (CI mode)"
            echo "  --help, -h             Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown argument: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}Azure Ops Lab - Deploy Script${NC}"
echo -e "${CYAN}================================${NC}"
echo ""

# --- Pre-flight checks ---

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI (az) is not installed.${NC}"
    echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Azure CLI.${NC}"
    echo "Run: az login"
    exit 1
fi

# Ensure required resource providers are registered (idempotent, safe to run every time)
# Note: registration requires subscription-level permissions. If running with
# RG-scoped RBAC (e.g., OIDC Contributor at RG level), this may fail.
# In that case, ask a subscription admin to register these providers once.
REQUIRED_PROVIDERS=("Microsoft.Web" "Microsoft.Storage" "Microsoft.Insights" "Microsoft.OperationalInsights" "Microsoft.Authorization")
REG_FAILED=false
echo -e "${YELLOW}Checking resource provider registrations...${NC}"
for provider in "${REQUIRED_PROVIDERS[@]}"; do
    STATE=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$STATE" == "Registered" ]]; then
        continue
    fi
    echo -e "  Registering ${provider}..."
    if ! az provider register --namespace "$provider" --wait > /dev/null 2>&1; then
        echo -e "  ${YELLOW}WARNING: Could not register ${provider} (may lack subscription-level permissions).${NC}"
        REG_FAILED=true
    fi
done
if [[ "$REG_FAILED" == true ]]; then
    echo -e "${YELLOW}Some providers could not be registered automatically.${NC}"
    echo "Ask a subscription admin to run:"
    echo "  az provider register --namespace <provider>"
    echo "Continuing — deployment may fail if providers are not registered."
    echo ""
else
    echo -e "${GREEN}All resource providers registered.${NC}"
    echo ""
fi

# Check template files exist
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}Error: Template file not found: ${TEMPLATE_FILE}${NC}"
    exit 1
fi

if [[ ! -f "$PARAMETERS_FILE" ]]; then
    echo -e "${RED}Error: Parameters file not found: ${PARAMETERS_FILE}${NC}"
    exit 1
fi

# Show current context
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "Subscription:    ${GREEN}${SUBSCRIPTION_NAME}${NC}"
echo -e "Subscription ID: ${GREEN}${SUBSCRIPTION_ID}${NC}"
echo -e "Resource Group:  ${GREEN}${RESOURCE_GROUP}${NC}"
echo -e "Location:        ${GREEN}${LOCATION}${NC}"
echo -e "Deployment:      ${GREEN}${DEPLOYMENT_NAME}${NC}"
echo ""

# --- Step 1: Ensure resource group exists ---

echo -e "${YELLOW}[1/4] Ensuring resource group exists...${NC}"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags environment=lab owner=brandon-metcalf project=azure-ops-lab \
    --output none
echo -e "${GREEN}Resource group ready.${NC}"
echo ""

# --- Step 2: What-if preview (MANDATORY per CLAUDE.md) ---

echo -e "${YELLOW}[2/4] Running what-if preview (required)...${NC}"
echo ""
az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMETERS_FILE" \
    --parameters location="$LOCATION"
echo ""

# --- Step 3: Confirm deployment ---

if [[ "$AUTO_APPROVE" == true ]]; then
    echo -e "${YELLOW}[3/4] Auto-approved (--yes flag).${NC}"
else
    echo -e "${YELLOW}[3/4] Review the what-if output above.${NC}"
    echo ""
    read -p "Deploy these changes? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
fi

# --- Step 4: Deploy ---

echo -e "${YELLOW}[4/4] Deploying infrastructure...${NC}"
az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMETERS_FILE" \
    --parameters location="$LOCATION" \
    --output none
echo -e "${GREEN}Deployment succeeded.${NC}"
echo ""

# --- Post-deploy safety check: verify F1 SKU ---

echo -e "${YELLOW}Verifying App Service Plan SKU...${NC}"

# Get the deployed web app name from deployment outputs
DEPLOYED_WEB_APP=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --query "properties.outputs.webAppName.value" \
    -o tsv 2>/dev/null || echo "")

# Resolve: deployment output -> web app -> App Service Plan ID -> SKU tier
if [[ -z "$DEPLOYED_WEB_APP" ]]; then
    echo -e "${RED}ERROR: Could not read webAppName from deployment outputs.${NC}"
    echo "Deployment succeeded but SKU verification failed. Verify manually:"
    echo "  az resource list -g $RESOURCE_GROUP --query \"[].{type:type,name:name}\" -o table"
    echo "  az appservice plan list -g $RESOURCE_GROUP --query \"[].{name:name,tier:sku.tier}\" -o table"
    exit 1
fi

PLAN_ID=$(az webapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYED_WEB_APP" \
    --query "appServicePlanId" \
    -o tsv 2>/dev/null || echo "")

if [[ -z "$PLAN_ID" ]]; then
    echo -e "${RED}ERROR: Could not resolve App Service Plan for web app '${DEPLOYED_WEB_APP}'.${NC}"
    echo "Verify manually:"
    echo "  az webapp show -g $RESOURCE_GROUP -n $DEPLOYED_WEB_APP --query appServicePlanId -o tsv"
    exit 1
fi

PLAN_SKU=$(az appservice plan show --ids "$PLAN_ID" --query "sku.tier" -o tsv 2>/dev/null || echo "")

if [[ "$PLAN_SKU" == "Free" ]]; then
    echo -e "${GREEN}App Service Plan tier: Free (F1) -- OK${NC}"
elif [[ -z "$PLAN_SKU" ]]; then
    echo -e "${RED}ERROR: Could not read SKU tier from App Service Plan.${NC}"
    echo "Verify manually: az appservice plan show --ids $PLAN_ID --query sku -o json"
    exit 1
else
    echo -e "${RED}CRITICAL: App Service Plan tier is '${PLAN_SKU}', NOT Free!${NC}"
    echo -e "${RED}This violates the zero-budget constraint.${NC}"
    echo -e "${RED}Run teardown immediately: ./scripts/teardown.sh ${RESOURCE_GROUP}${NC}"
    exit 1
fi

# --- Summary ---

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Deployment Complete${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "Resource Group: ${RESOURCE_GROUP}"
echo -e "Deployment:     ${DEPLOYMENT_NAME}"
echo ""
echo "Deployed resources:"
az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Name:name, Type:type}" \
    -o table
echo ""
echo "When finished, teardown with:"
echo "  ./scripts/teardown.sh ${RESOURCE_GROUP}"
