output "application_id" {
  description = "Client id: run_as.service_principal_name in databricks.yml, AZURE_CLIENT_ID in GitHub Actions"
  value       = azuread_service_principal.this.client_id
}

output "tenant_id" {
  description = "AZURE_TENANT_ID in GitHub Actions"
  value       = data.azuread_client_config.current.tenant_id
}

output "object_id" {
  description = "Entra ID object id of the service principal – principal of Azure role assignments (e.g. deploying the function)"
  value       = azuread_service_principal.this.object_id
}
