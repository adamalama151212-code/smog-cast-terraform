# Every provider signs in as whoever is logged in with `az login` — no keys or tokens in files.
# Which subscription / tenant / workspace / account is targeted comes from the environment's var-file.
# The tenant is explicit everywhere: DEV and PROD live in different tenants, and the account endpoint
# (accounts.azuredatabricks.net) cannot infer it — without it the CLI token is requested from "common" and fails.

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# Workspace level: catalog, schemas, volumes, grants, secret scope, workspace service principal.
provider "databricks" {
  host            = var.databricks_host
  auth_type       = "azure-cli"
  azure_tenant_id = var.tenant_id
}

# Account level: groups (Unity Catalog grants need account groups) and their workspace assignment.
provider "databricks" {
  alias           = "account"
  host            = "https://accounts.azuredatabricks.net"
  account_id      = var.databricks_account_id
  auth_type       = "azure-cli"
  azure_tenant_id = var.tenant_id
}
