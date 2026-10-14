output "function_app_name" {
  description = "Target of `az functionapp deployment source config-zip` (smogcast repo, functions/gios_poller)"
  value       = azurerm_function_app_flex_consumption.poller.name
}

output "function_app_id" {
  description = "Scope of the CI principal's role for deploying the function code"
  value       = azurerm_function_app_flex_consumption.poller.id
}

output "volume_path" {
  description = "storage.live_landing_root in conf/<env>.yaml of the smogcast repo"
  value       = "/Volumes/${databricks_volume.landing_live.catalog_name}/${databricks_volume.landing_live.schema_name}/${databricks_volume.landing_live.name}"
}

output "storage_account_name" {
  value = azurerm_storage_account.live.name
}
