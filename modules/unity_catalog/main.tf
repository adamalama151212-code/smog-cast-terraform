# Unity Catalog objects the smogcast pipeline writes to:
#   tables  <catalog>.{bronze,silver,gold,ops}.<table>     (created by the Jobs, not here)
#   files   /Volumes/<catalog>/raw/{landing,checkpoints,models}
# The layout must match conf/<env>.yaml of the smogcast repo (storage.catalog, *_root paths).

terraform {
  required_providers {
    databricks = { source = "databricks/databricks" }
  }
}

resource "databricks_catalog" "this" {
  name    = var.catalog_name
  comment = var.comment
  # Needed when the metastore has no default storage root (the case on the DEV workspace).
  storage_root = var.storage_root
  # Never drop a catalog that still holds tables and volumes on a plain `terraform destroy`.
  force_destroy = false

  # Databricks sets system properties itself (e.g. collation = UTF8_BINARY); without this every plan would try
  # to remove them.
  lifecycle {
    ignore_changes = [properties]
  }
}

resource "databricks_schema" "this" {
  for_each     = var.schemas
  catalog_name = databricks_catalog.this.name
  name         = each.key
  comment      = each.value

  # System properties set by Databricks (collation, owner = root) — see the catalog above.
  lifecycle {
    ignore_changes = [properties]
  }
}

resource "databricks_volume" "this" {
  for_each     = var.volumes
  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.this[var.volume_schema].name
  name         = each.key
  volume_type  = "MANAGED"
  comment      = each.value
}
