# Live ingestion outside Databricks: an Azure Function polls the GIOŚ API every hour and writes the poll files
# to a blob container that Unity Catalog exposes as an EXTERNAL volume — the stream pipeline reads them there.
#
#   Function (Flex Consumption, Python) ──managed identity──► storage <account>/live/landing/{gios_registry,gios_live}
#   Access connector ──managed identity──► the same container ──► storage credential → external location
#                                                                  → volume <catalog>.raw.landing_live
#
# No keys anywhere in the data path: both writers/readers use managed identities. The function CODE is deployed
# from the smogcast repo (functions/gios_poller), not by Terraform.

terraform {
  required_providers {
    azurerm    = { source = "hashicorp/azurerm" }
    databricks = { source = "databricks/databricks" }
  }
}

# ----------------------------------------------------------------------------- storage
resource "azurerm_storage_account" "live" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true # ADLS Gen2: abfss:// paths for Unity Catalog
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

# Poll files: <container>/landing/gios_registry/..., <container>/landing/gios_live/...
resource "azurerm_storage_container" "live" {
  name                  = "live"
  storage_account_id    = azurerm_storage_account.live.id
  container_access_type = "private"
}

# Deployment packages of the function app (Flex Consumption keeps them in a blob container).
resource "azurerm_storage_container" "deployment" {
  name                  = "function-deployment"
  storage_account_id    = azurerm_storage_account.live.id
  container_access_type = "private"
}

# ----------------------------------------------------------------------------- function app
resource "azurerm_user_assigned_identity" "function" {
  name                = "id-${var.function_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Owner (not only Contributor): the Functions host also needs it for its own blobs (timer locks, deployment).
resource "azurerm_role_assignment" "function_storage" {
  scope                = azurerm_storage_account.live.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.function_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.function_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "other"
  tags                = var.tags
}

resource "azurerm_service_plan" "function" {
  name                = "asp-${var.function_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "FC1" # Flex Consumption: pay per execution, managed-identity deployment storage
  tags                = var.tags
}

resource "azurerm_function_app_flex_consumption" "poller" {
  name                = var.function_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.function.id

  runtime_name           = "python"
  runtime_version        = "3.11" # the same Python as the smogcast Docker image that builds the package
  maximum_instance_count = 40     # the minimum Flex allows; one poll per hour needs a single instance
  instance_memory_in_mb  = 2048

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${azurerm_storage_account.live.primary_blob_endpoint}${azurerm_storage_container.deployment.name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.function.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.function.id]
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.this.connection_string
  }

  app_settings = {
    SMOGCAST_ENV             = var.environment # conf/<env>.yaml of the smogcast package: cities, API address
    LIVE_STORAGE_ACCOUNT_URL = azurerm_storage_account.live.primary_blob_endpoint
    LIVE_CONTAINER           = azurerm_storage_container.live.name
    LIVE_PREFIX              = "${var.landing_folder}/"
    AZURE_CLIENT_ID          = azurerm_user_assigned_identity.function.client_id
    POLL_SCHEDULE            = var.poll_schedule
    # The Functions host's own storage (timer locks) through the same identity — no connection string.
    AzureWebJobsStorage__accountName = azurerm_storage_account.live.name
    AzureWebJobsStorage__credential  = "managedidentity"
    AzureWebJobsStorage__clientId    = azurerm_user_assigned_identity.function.client_id
  }

  tags       = var.tags
  depends_on = [azurerm_role_assignment.function_storage]

  lifecycle {
    # Azure adds this tag itself (the portal's link to Application Insights); removing it on every apply would only
    # make Azure add it back — a change in every plan.
    ignore_changes = [tags["hidden-link: /app-insights-resource-id"]]
  }
}

# WORKAROUND for an open azurerm bug (hashicorp/terraform-provider-azurerm#29149): with an identity-based storage
# connection the provider still injects `AzureWebJobsStorage = "...;AccountKey=;..."` (an EMPTY key) on every
# create/update of a Flex Consumption app, hidden from the plan. A plain AzureWebJobsStorage wins over the
# AzureWebJobsStorage__* identity settings, so the host gets 403 from storage and the timer never runs.
# After every change of the app, the setting is deleted again (az CLI — the same login Terraform uses).
# Remove this block once the provider stops injecting the setting.
resource "terraform_data" "drop_keyless_webjobs_storage" {
  # A fingerprint of the app, not the app object itself: the object carries sensitive attributes that are unknown
  # until the app exists, and a first apply then fails with "inconsistent values for sensitive attribute".
  triggers_replace = nonsensitive(sha256(jsonencode(azurerm_function_app_flex_consumption.poller)))

  provisioner "local-exec" {
    command = "az functionapp config appsettings delete --ids ${azurerm_function_app_flex_consumption.poller.id} --setting-names AzureWebJobsStorage --output none"
  }
}

# ----------------------------------------------------------------------------- Unity Catalog
resource "azurerm_databricks_access_connector" "live" {
  name                = "ac-${var.function_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "connector_storage" {
  scope                = azurerm_storage_account.live.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.live.identity[0].principal_id
}

resource "databricks_storage_credential" "live" {
  name    = "smogcast-live-${var.environment}"
  comment = "smogcast: access connector of the live poll container"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.live.id
  }
  depends_on = [azurerm_role_assignment.connector_storage]
}

resource "databricks_external_location" "live" {
  name            = "smogcast-live-${var.environment}"
  url             = "abfss://${azurerm_storage_container.live.name}@${azurerm_storage_account.live.name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.live.name
  comment         = "smogcast: GIOŚ API polls written by the Azure Function"
}

resource "databricks_volume" "landing_live" {
  name             = var.volume_name
  catalog_name     = var.catalog_name
  schema_name      = var.volume_schema
  volume_type      = "EXTERNAL"
  storage_location = "${databricks_external_location.live.url}${var.landing_folder}"
  comment          = "GIOŚ API polls (gios_registry/, gios_live/) written by the Azure Function"
}
