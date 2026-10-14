output "catalog_name" {
  value = databricks_catalog.this.name
}

# The names below are built from the input variables, not from the resources: while objects are being imported
# (terraform import) the resource maps hold only what is already in the state, and an output built from them
# would be missing keys ("Invalid index"). Callers that need an object to EXIST depend on the module instead.
output "schema_names" {
  description = "Schema name => full name (catalog.schema)"
  value       = { for k in keys(var.schemas) : k => "${var.catalog_name}.${k}" }
}

output "volume_paths" {
  description = "Volume name => /Volumes path (goes into conf/<env>.yaml of the smogcast repo)"
  value       = { for k in keys(var.volumes) : k => "/Volumes/${var.catalog_name}/${var.volume_schema}/${k}" }
}
