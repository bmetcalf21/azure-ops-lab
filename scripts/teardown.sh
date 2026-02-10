#!/bin/bash
################################################################################
# Azure Operations Lab - Teardown Script
#
# Safely deletes all Azure resources by removing the resource group.
# This is the recommended approach for lab environments to ensure complete
# cleanup and avoid unexpected charges.
#
# Author: Brandon Metcalf
# Project: azure-ops-lab
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default resource group name
DEFAULT_RG="azure-ops-lab-rg-westus"
RESOURCE_GROUP="${1:-$DEFAULT_RG}"

echo -e "${YELLOW}================================${NC}"
echo -e "${YELLOW}Azure Ops Lab - Teardown Script${NC}"
echo -e "${YELLOW}================================${NC}"
echo ""

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

# Show current subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "Current subscription: ${GREEN}${SUBSCRIPTION_NAME}${NC}"
echo -e "Subscription ID: ${GREEN}${SUBSCRIPTION_ID}${NC}"
echo ""

# Check if resource group exists
echo "Checking if resource group exists..."
if ! az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
    echo -e "${YELLOW}Resource group '${RESOURCE_GROUP}' does not exist.${NC}"
    echo "Nothing to delete."
    exit 0
fi

# List resources in the group
echo -e "\n${YELLOW}Resources to be deleted:${NC}"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o table

# Confirm deletion
echo ""
echo -e "${RED}WARNING: This will permanently delete all resources in '${RESOURCE_GROUP}'.${NC}"
echo -e "${RED}This action cannot be undone.${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Teardown cancelled."
    exit 0
fi

# Delete the resource group
echo -e "${YELLOW}Deleting resource group: ${RESOURCE_GROUP}${NC}"
echo "This may take several minutes..."

if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
    echo -e "${GREEN}Deletion initiated successfully.${NC}"
    echo ""
    echo "The resource group and all its resources are being deleted in the background."
    echo "This process typically takes 5-10 minutes."
    echo ""
    echo "To check deletion status, run:"
    echo "  az group show --name $RESOURCE_GROUP"
    echo ""
    echo -e "${GREEN}Teardown complete!${NC}"
else
    echo -e "${RED}Failed to delete resource group.${NC}"
    exit 1
fi
