# Azure Key Vault + a Databricks secret scope backed by it (course requirement: secrets in Key Vault).
# Terraform creates the containers only; secret VALUES are set by hand (`az keyvault secret set`) so they
# never land in the Terraform state. Jobs read them with dbutils.secrets.get(scope, key).

terraform {
  required_providers {
    azurerm    = { source = "hashicorp/azurerm" }
    azuread    = { source = "hashicorp/azuread" }
    databricks = { source = "databricks/databricks" }
  }
}

data "azurerm_client_config" "current" {}

# Databricks reads a Key Vault-backed scope as its first-party application "AzureDatabricks" (same client id
# in every tenant), so that application needs read access to the vault.
data "azuread_service_principal" "azure_databricks" {
  client_id = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
}

resource "azurerm_key_vault" "this" {
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  # Off for DEV so a vault name can be reused after a destroy; turn on for PROD.
  purge_protection_enabled = var.purge_protection
  tags                     = var.tags

  # Access policies (not Azure RBAC): the permission model Databricks documents for Key Vault-backed scopes.
  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Purge"]
  }

  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azuread_service_principal.azure_databricks.object_id
    secret_permissions = ["Get", "List"]
  }

  # Identities that only read a secret they know by name (the app's managed identity). Declared here, inside the
  # vault: its policies are managed in this one place, and a separate azurerm_key_vault_access_policy resource
  # would fight with the blocks above.
  dynamic "access_policy" {
    for_each = var.reader_object_ids
    content {
      tenant_id          = data.azurerm_client_config.current.tenant_id
      object_id          = access_policy.value
      secret_permissions = ["Get"]
    }
  }
}

# Creating a Key Vault-backed scope requires an Entra ID USER token (az login as a person), not a service
# principal — run this module's first apply interactively.
resource "databricks_secret_scope" "this" {
  name         = var.scope_name
  backend_type = "AZURE_KEYVAULT"

  keyvault_metadata {
    resource_id = azurerm_key_vault.this.id
    dns_name    = azurerm_key_vault.this.vault_uri
  }
}
