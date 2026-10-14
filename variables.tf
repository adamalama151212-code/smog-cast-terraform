# ---------------------------------------------------------------- environment (environment/<env>/<region>/terraform.tfvars)

variable "environment" {
  description = "Environment name; must equal the selected Terraform workspace (dev | prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "subscription_id" {
  description = "Azure subscription of the environment (az account show --query id -o tsv)"
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant of the environment (az account show --query tenantId -o tsv); the Databricks account endpoint cannot infer it"
  type        = string
}

variable "location" {
  description = "Azure region (the same as the Databricks workspace)"
  type        = string
}

variable "databricks_host" {
  description = "Workspace URL without query parameters"
  type        = string
}

variable "databricks_workspace_id" {
  description = "Numeric workspace id (the adb-<id> part of the URL)"
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account id: \"account_id\" in <workspace host>/.well-known/databricks-config (or the account console user menu)"
  type        = string
}

variable "catalog_name" {
  description = "Unity Catalog catalog; must match storage.catalog in conf/<env>.yaml of the smogcast repo"
  type        = string
}

variable "catalog_storage_root" {
  description = "Managed location of the catalog; null when the metastore has a default storage root"
  type        = string
  default     = null
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name, 3-24 characters"
  type        = string
}

variable "key_vault_purge_protection" {
  description = "Key Vault purge protection (cannot be turned off once on): false on DEV, true on PROD"
  type        = bool
  default     = false
}

variable "live_storage_account_name" {
  description = "Globally unique storage account of the GIOŚ poll files (module live_ingest), 3-24 lowercase letters/digits"
  type        = string
}

variable "function_app_name" {
  description = "Globally unique name of the Azure Function that polls the GIOŚ API (module live_ingest)"
  type        = string
}

variable "sql_warehouse_id" {
  description = "Id of the workspace's \"Serverless Starter Warehouse\", adopted by Terraform (databricks warehouses list)"
  type        = string
}

variable "sql_warehouse_size" {
  description = "Size of the SQL Warehouse; 2X-Small = 4 DBU per running hour (Small = 12), plenty for the gold tables"
  type        = string
  default     = "2X-Small"
}

variable "sql_warehouse_auto_stop_mins" {
  description = "Idle minutes before the SQL Warehouse stops; 1 is the shortest a serverless warehouse accepts"
  type        = number
  default     = 1
  validation {
    # 0 would switch auto-stop off: the warehouse would run, and bill, until stopped by hand.
    condition     = var.sql_warehouse_auto_stop_mins >= 1
    error_message = "sql_warehouse_auto_stop_mins must be at least 1 (0 disables auto-stop)."
  }
}

variable "github_subjects" {
  description = "Credential name => GitHub OIDC subject allowed to sign in as the service principal"
  type        = map(string)
  default     = {}
}

variable "app_image" {
  description = "Image of the app's FIRST deployment (ghcr.io/<owner>/smog-cast-app:<tag>); null = no app yet, only what it needs. Later images come from deploy.yml of the app repo"
  type        = string
  default     = null
}

variable "app_cpu" {
  description = "vCPU of the app's container. On the Consumption plan memory goes with it: 2 Gi per vCPU, in steps of 0.25 vCPU (1 / 2Gi, 1.5 / 3Gi, 2 / 4Gi)"
  type        = number
  default     = 1
}

variable "app_memory" {
  description = "Memory of the app's container; must be 2 Gi per vCPU of app_cpu (e.g. \"3Gi\" with 1.5)"
  type        = string
  default     = "2Gi"
}

variable "app_location" {
  description = "Azure region of the app's Container Apps environment; null = var.location. Another region when this one is out of capacity (ManagedEnvironmentCapacityHeavyUsageError)"
  type        = string
  default     = null
}

variable "app_llm_base_url" {
  description = "OpenAI-compatible endpoint of the app's language model"
  type        = string
  default     = "https://api.cerebras.ai/v1"
}

variable "app_llm_model" {
  description = "Language model of the app's assistant"
  type        = string
  default     = "gpt-oss-120b"
}

variable "app_github_subjects" {
  description = "Credential name => GitHub OIDC subject allowed to deploy the app (the app repo and its GitHub Environment)"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------- shared (globals.auto.tfvars)

variable "secret_scope_name" {
  description = "Databricks secret scope read by the Jobs"
  type        = string
}

variable "group_prefix" {
  description = "Prefix of the RLS/CLS group names"
  type        = string
}

variable "region_codes" {
  description = "Voivodeships that get an RLS group (jurisdiction_code values of conf/cities.yaml in the smogcast repo)"
  type        = list(string)
}

variable "group_members" {
  description = "RLS/CLS group name => user e-mails in it (users must exist in the Databricks account)"
  type        = map(list(string))
  default     = {}
}
