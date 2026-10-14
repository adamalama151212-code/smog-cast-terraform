output "group_names" {
  description = "Group names to use in sql/governance.sql (row filters, column masks)"
  value       = sort(keys(databricks_group.this))
}

output "group_ids" {
  description = "Group name => account-level id, for members added outside this module (the app's service principal)"
  value       = { for name, group in databricks_group.this : name => group.id }
}
