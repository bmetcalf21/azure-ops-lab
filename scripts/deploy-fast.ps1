<#
.SYNOPSIS
    Azure Operations Lab - Fast Deploy Script (PowerShell)

.DESCRIPTION
    Deploys infrastructure via Bicep for live interview demos.
    Skips interactive confirmation for smooth demo flow.
    Includes post-deploy F1 SKU safety check.

    This script uses Azure CLI (az) within PowerShell to maintain
    consistent authentication and command patterns with the rest of the repo.

.PARAMETER ResourceGroup
    Resource group name. Default: azure-ops-lab-rg-westus

.PARAMETER Location
    Azure region. Default: westus

.EXAMPLE
    ./scripts/deploy-fast.ps1
    ./scripts/deploy-fast.ps1 -ResourceGroup "my-rg" -Location "eastus"

.NOTES
    Author: Brandon Metcalf
    Project: azure-ops-lab
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = "azure-ops-lab-rg-westus",
    [string]$Location = "westus"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TemplateFile = "infra/main.bicep"
$ParametersFile = "infra/parameters.json"
$DeploymentName = "deploy-fast-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# --- Guard: Only allow known lab resource groups ---
$AllowedResourceGroups = @("azure-ops-lab-rg", "azure-ops-lab-rg-eastus2", "azure-ops-lab-rg-westus")

if ($ResourceGroup -notin $AllowedResourceGroups) {
    Write-Error ("Resource group '{0}' is not in the allowed list: {1}. " +
        "This guard prevents accidental operations on non-lab resource groups. " +
        "Edit the `$AllowedResourceGroups array in this script to add new entries.") `
        -f $ResourceGroup, ($AllowedResourceGroups -join ", ")
    exit 1
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Azure Ops Lab - Fast Deploy" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# --- Pre-flight checks ---

# Check Azure CLI is available
try {
    $null = & az version 2>&1
} catch {
    Write-Error "Azure CLI (az) is not installed. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
}

# Check Azure login
try {
    $AccountJson = & az account show 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Not logged in" }
    $Account = $AccountJson | ConvertFrom-Json
} catch {
    Write-Error "Not logged in to Azure CLI. Run: az login"
    exit 1
}

# Ensure required resource providers are registered (idempotent, safe to run every time)
# Note: registration requires subscription-level permissions. If running with
# RG-scoped RBAC (e.g., OIDC Contributor at RG level), this may fail.
# In that case, ask a subscription admin to register these providers once.
$RequiredProviders = @("Microsoft.Web", "Microsoft.Storage", "Microsoft.Insights", "Microsoft.OperationalInsights", "Microsoft.Authorization")
$RegFailed = $false
Write-Host "Checking resource provider registrations..." -ForegroundColor Yellow
foreach ($provider in $RequiredProviders) {
    $state = & az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
    if ($state -eq "Registered") { continue }
    Write-Host "  Registering $provider..."
    & az provider register --namespace $provider --wait 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Could not register $provider (may lack subscription-level permissions)." -ForegroundColor Yellow
        $RegFailed = $true
    }
}
if ($RegFailed) {
    Write-Host "Some providers could not be registered automatically." -ForegroundColor Yellow
    Write-Host "Ask a subscription admin to run:"
    Write-Host "  az provider register --namespace <provider>"
    Write-Host "Continuing -- deployment may fail if providers are not registered."
    Write-Host ""
} else {
    Write-Host "All resource providers registered." -ForegroundColor Green
    Write-Host ""
}

# Check template files exist
if (-not (Test-Path $TemplateFile)) {
    Write-Error "Template file not found: $TemplateFile"
    exit 1
}
if (-not (Test-Path $ParametersFile)) {
    Write-Error "Parameters file not found: $ParametersFile"
    exit 1
}

Write-Host "Subscription:    $($Account.name)" -ForegroundColor Green
Write-Host "Subscription ID: $($Account.id)" -ForegroundColor Green
Write-Host "Resource Group:  $ResourceGroup" -ForegroundColor Green
Write-Host "Location:        $Location" -ForegroundColor Green
Write-Host "Deployment:      $DeploymentName" -ForegroundColor Green
Write-Host ""

# --- Step 1: Ensure resource group exists ---

Write-Host "[1/3] Ensuring resource group exists..." -ForegroundColor Yellow
& az group create `
    --name $ResourceGroup `
    --location $Location `
    --tags environment=lab owner=brandon-metcalf project=azure-ops-lab `
    --output none
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create resource group."
    exit 1
}
Write-Host "Resource group ready." -ForegroundColor Green
Write-Host ""

# --- Step 2: What-if preview (display only, no gate for fast path) ---

Write-Host "[2/3] Running what-if preview..." -ForegroundColor Yellow
Write-Host ""
& az deployment group what-if `
    --resource-group $ResourceGroup `
    --template-file $TemplateFile `
    --parameters $ParametersFile `
    --parameters location=$Location
if ($LASTEXITCODE -ne 0) {
    Write-Error "What-if preview failed. Aborting deployment."
    exit 1
}
Write-Host ""

# --- Step 3: Deploy (no confirmation -- fast path for demos) ---

Write-Host "[3/3] Deploying infrastructure..." -ForegroundColor Yellow
& az deployment group create `
    --name $DeploymentName `
    --resource-group $ResourceGroup `
    --template-file $TemplateFile `
    --parameters $ParametersFile `
    --parameters location=$Location `
    --output none
if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed."
    exit 1
}
Write-Host "Deployment succeeded." -ForegroundColor Green
Write-Host ""

# --- Post-deploy safety check: verify F1 SKU ---

Write-Host "Verifying App Service Plan SKU..." -ForegroundColor Yellow

# Get the deployed web app name from deployment outputs
$WebAppName = & az deployment group show `
    --resource-group $ResourceGroup `
    --name $DeploymentName `
    --query "properties.outputs.webAppName.value" `
    -o tsv 2>$null

if (-not $WebAppName) {
    Write-Host "ERROR: Could not read webAppName from deployment outputs." -ForegroundColor Red
    Write-Host "Deployment succeeded but SKU verification failed. Verify manually:"
    Write-Host "  az resource list -g $ResourceGroup --query `"[].{type:type,name:name}`" -o table"
    Write-Host "  az appservice plan list -g $ResourceGroup --query `"[].{name:name,tier:sku.tier}`" -o table"
    exit 1
}

# Resolve the App Service Plan from the deployed web app
$PlanId = & az webapp show `
    --resource-group $ResourceGroup `
    --name $WebAppName `
    --query "appServicePlanId" `
    -o tsv 2>$null

if (-not $PlanId) {
    Write-Host "ERROR: Could not resolve App Service Plan for web app '$WebAppName'." -ForegroundColor Red
    Write-Host "Verify manually:"
    Write-Host "  az webapp show -g $ResourceGroup -n $WebAppName --query appServicePlanId -o tsv"
    exit 1
}

$PlanTier = & az appservice plan show `
    --ids $PlanId `
    --query "sku.tier" `
    -o tsv 2>$null

if ($PlanTier -eq "Free") {
    Write-Host "App Service Plan tier: Free (F1) -- OK" -ForegroundColor Green
} elseif (-not $PlanTier) {
    Write-Host "ERROR: Could not read SKU tier from App Service Plan." -ForegroundColor Red
    Write-Host "Verify manually: az appservice plan show --ids $PlanId --query sku -o json"
    exit 1
} else {
    Write-Host "" -ForegroundColor Red
    Write-Host "CRITICAL: App Service Plan tier is '$PlanTier', NOT Free!" -ForegroundColor Red
    Write-Host "This violates the zero-budget constraint." -ForegroundColor Red
    Write-Host "Run teardown IMMEDIATELY:" -ForegroundColor Red
    Write-Host "  ./scripts/teardown.sh $ResourceGroup" -ForegroundColor Red
    Write-Host "  # or: az group delete --name $ResourceGroup --yes" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# --- Summary ---

Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "Deployment Complete" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Deployment:     $DeploymentName"
Write-Host ""
Write-Host "Deployed resources:"
& az resource list `
    --resource-group $ResourceGroup `
    --query "[].{Name:name, Type:type}" `
    -o table
Write-Host ""
Write-Host "When finished, teardown with:"
Write-Host "  ./scripts/teardown.sh $ResourceGroup"
