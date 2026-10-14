# Values the smogcast repo needs (databricks.yml, conf/<env>.yaml, GitHub Actions): terraform output

output "environment" {
  value = local.environment
}

output "databricks_host" {
  value = var.databricks_host
}

output "catalog_name" {
  value = module.unity_catalog.catalog_name
}

output "volume_paths" {
  value = module.unity_catalog.volume_paths
}

output "key_vault_name" {
  value = module.secrets.key_vault_name
}

output "secret_scope" {
  value = module.secrets.scope_name
}

output "jobs_service_principal_application_id" {
  description = "databricks.yml run_as.service_principal_name; AZURE_CLIENT_ID in GitHub Actions"
  value       = module.identity.application_id
}

output "tenant_id" {
  value = module.identity.tenant_id
}

output "governance_groups" {
  value = module.governance.group_names
}

output "sql_warehouse_id" {
  description = "DATABRICKS_WAREHOUSE_ID of the app (tools/dev-env.sh in the smog-cast-app repo)"
  value       = databricks_sql_endpoint.starter.id
}

output "app_url" {
  description = "Public address of the app (null until app_image is set)"
  value       = module.app_hosting.url
}

output "app_container_app_name" {
  description = "CONTAINER_APP_NAME in the GitHub Environment of the app repo (null until app_image is set)"
  value       = module.app_hosting.container_app_name
}

output "app_service_principal_name" {
  description = "The app's Databricks service principal: generate its OAuth secret in the workspace settings"
  value       = module.app_hosting.service_principal_name
}

output "app_service_principal_application_id" {
  description = "Client id of the app's service principal (the app gets it as DATABRICKS_CLIENT_ID)"
  value       = module.app_hosting.service_principal_application_id
}

output "app_deploy_client_id" {
  description = "AZURE_CLIENT_ID in the GitHub Environment of the app repo (deploy identity, OIDC)"
  value       = module.app_hosting.deploy_client_id
}

output "live_function_app_name" {
  description = "Deploy the poller code here: az functionapp deployment source config-zip (smogcast repo, functions/gios_poller)"
  value       = module.live_ingest.function_app_name
}

output "live_volume_path" {
  description = "storage.live_landing_root in conf/<env>.yaml of the smogcast repo"
  value       = module.live_ingest.volume_path
}
