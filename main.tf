terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azuread    = { source = "hashicorp/azuread", version = "~> 3.0" }
    databricks = { source = "databricks/databricks", version = "~> 1.50" }
  }
}

# The Databricks WORKSPACES are not managed here: DEV was created by hand, PROD is provided by the course.
# They are only referenced by URL and id — adopting one would risk a replace (= deleting the workspace) on
# any attribute mismatch.

locals {
  environment = var.environment
  tags        = { project = "smogcast", environment = local.environment, managed_by = "terraform" }
}

# Guard: the selected workspace and the -var-file must name the same environment. A mismatch would apply
# one environment's values onto another environment's state.
resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = terraform.workspace == var.environment
      error_message = "Workspace '${terraform.workspace}' does not match environment '${var.environment}' of the var-file. Run: terraform workspace select ${var.environment}"
    }
  }
}

# Azure resources of smogcast other than the workspace (the Key Vault for now).
resource "azurerm_resource_group" "smogcast" {
  name     = "rg-smogcast-${local.environment}"
  location = var.location
  tags     = local.tags
}

module "unity_catalog" {
  source       = "./modules/unity_catalog"
  catalog_name = var.catalog_name
  comment      = "smogcast: tomorrow's PM10/PM2.5 exceedance forecast (${upper(local.environment)})"
  storage_root = var.catalog_storage_root
}

module "secrets" {
  source              = "./modules/secrets"
  key_vault_name      = var.key_vault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.smogcast.name
  scope_name          = var.secret_scope_name
  purge_protection    = var.key_vault_purge_protection
  # The hosted app's managed identity reads its two secrets (module app_hosting).
  reader_object_ids = [module.app_hosting.identity_principal_id]
  tags              = local.tags
}

module "identity" {
  source          = "./modules/identity"
  display_name    = "sp-smogcast-${local.environment}"
  catalog_name    = module.unity_catalog.catalog_name
  github_subjects = var.github_subjects
  account_id      = var.databricks_account_id
  # The admins group (module governance; the author is its member) deploys the bundle from a laptop.
  deployer_groups = [for g in module.governance.group_names : g if g == "${var.group_prefix}-admins"]
}

module "governance" {
  source = "./modules/governance"
  providers = {
    databricks         = databricks
    databricks.account = databricks.account
  }
  group_prefix  = var.group_prefix
  region_codes  = var.region_codes
  workspace_id  = var.databricks_workspace_id
  catalog_name  = module.unity_catalog.catalog_name
  gold_schema   = module.unity_catalog.schema_names["gold"]
  secure_schema = module.unity_catalog.schema_names["gold_secure"]
  group_members = var.group_members

  # schema_names is built from variables, so the grants on gold must wait for the schema explicitly.
  depends_on = [module.unity_catalog]
}

# The Jobs' service principal may read the secrets of its environment.
resource "databricks_secret_acl" "jobs_read" {
  scope      = module.secrets.scope_name
  principal  = module.identity.application_id
  permission = "READ"
}

# The SQL Warehouse of the dashboard and the app. Terraform adopts that warehouse (import, no new one: the
# bundle finds it by name and the SQL Editor uses it too) and keeps it at the smallest size with the shortest
# auto-stop. A serverless warehouse starts in seconds, so waking it more often costs little.
import {
  to = databricks_sql_endpoint.starter
  id = var.sql_warehouse_id
}

resource "databricks_sql_endpoint" "starter" {
  name                      = "Serverless Starter Warehouse" # the name the bundle looks up (databricks.yml)
  cluster_size              = var.sql_warehouse_size
  auto_stop_mins            = var.sql_warehouse_auto_stop_mins
  min_num_clusters          = 1
  max_num_clusters          = 1
  enable_serverless_compute = true
  warehouse_type            = "PRO"
  enable_photon             = true
  spot_instance_policy      = "COST_OPTIMIZED"

  # The dashboard, the Jobs' dashboard refresh and the app all depend on this warehouse.
  lifecycle {
    prevent_destroy = true
  }
}

# GIOŚ API polling outside Databricks (Azure Function) and the external volume its files land in.
module "live_ingest" {
  source               = "./modules/live_ingest"
  environment          = local.environment
  location             = var.location
  resource_group_name  = azurerm_resource_group.smogcast.name
  storage_account_name = var.live_storage_account_name
  function_app_name    = var.function_app_name
  catalog_name         = module.unity_catalog.catalog_name
  tags                 = local.tags

  # The volume goes into the schema `raw` created by the unity_catalog module.
  depends_on = [module.unity_catalog]
}

# The app (Reflex, repo smog-cast-app) on Azure Container Apps: its own Databricks service principal with the analyst
# role, its secrets in the Key Vault above, a deploy identity for GitHub Actions of the app repo.
# var.app_image = null creates everything but the app itself (first apply); see README §6d for the order.
module "app_hosting" {
  source = "./modules/app_hosting"
  providers = {
    databricks         = databricks
    databricks.account = databricks.account
  }
  environment         = local.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.smogcast.name
  # Only the Container Apps environment (and the app in it) may live in another region than the rest.
  environment_location = var.app_location
  image                = var.app_image
  cpu                  = var.app_cpu
  memory               = var.app_memory
  key_vault_uri        = module.secrets.key_vault_uri
  databricks_host      = var.databricks_host
  sql_warehouse_id     = databricks_sql_endpoint.starter.id
  catalog_name         = module.unity_catalog.catalog_name
  analysts_group_id    = module.governance.group_ids["${var.group_prefix}-analysts"]
  llm_base_url         = var.app_llm_base_url
  llm_model            = var.app_llm_model
  github_subjects      = var.app_github_subjects
  tags                 = local.tags
}

# CI (deploy.yml in the smogcast repo) logs in as the Jobs' service principal and uploads the function code
# (`az functionapp deployment source config-zip`). Website Contributor on this one app is enough for that – no
# rights on the subscription or on other resources.
resource "azurerm_role_assignment" "ci_deploys_function" {
  scope                = module.live_ingest.function_app_id
  role_definition_name = "Website Contributor"
  principal_id         = module.identity.object_id
}
