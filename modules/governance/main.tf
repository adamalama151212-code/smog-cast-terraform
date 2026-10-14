# Groups for Row- and Column-Level Security (decision D12 of the smogcast plan: RLS by voivodeship).
#
#   <prefix>-admins          sees every row and column
#   <prefix>-analysts        sees every row, but not technical columns (CLS: class = technical in the data dictionary)
#   <prefix>-region-PL-12 …  sees only the rows of its voivodeship (jurisdiction_code)
#
# Terraform creates the groups and the read grants. The rules themselves are dynamic VIEWS in the schema gold_secure,
# created by the smogcast step `gold governance` after the tables exist (not row filters on the tables: a filtered
# table rejects Delta API writes from the Jobs' single-user clusters). The views test membership with
# is_account_group_member('<group name>') and, first, the smogcast table ops.access_policy.
#
# Unity Catalog grants and is_account_group_member() need ACCOUNT-level groups, so groups are created with
# the account provider (requires an account admin) and then assigned to the workspace.

terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      configuration_aliases = [databricks.account]
    }
  }
}

locals {
  groups = toset(concat(
    ["${var.group_prefix}-admins", "${var.group_prefix}-analysts"],
    [for code in var.region_codes : "${var.group_prefix}-region-${code}"],
  ))
}

resource "databricks_group" "this" {
  provider     = databricks.account
  for_each     = local.groups
  display_name = each.key
}

# for_each over the static name set (not over databricks_group.this): the keys must be known before the
# groups exist, otherwise `terraform import` and the first plan fail with "Invalid for_each argument".
resource "databricks_mws_permission_assignment" "this" {
  provider     = databricks.account
  for_each     = local.groups
  workspace_id = var.workspace_id
  principal_id = databricks_group.this[each.key].id
  permissions  = ["USER"]
}

# Every group may enter the catalog; only admins read the layers themselves. What rows and columns the others see
# is decided by the secure views in gold_secure (grants below).
# One databricks_grant per (securable, principal): two resources for the same pair would overwrite each other.
resource "databricks_grant" "catalog" {
  for_each  = local.groups
  catalog   = var.catalog_name
  principal = databricks_group.this[each.key].display_name
  # Admins read every layer (bronze, silver, ops), e.g. to trace a forecast back to raw data; others enter only.
  privileges = each.key == "${var.group_prefix}-admins" ? ["USE_CATALOG", "USE_SCHEMA", "SELECT", "READ_VOLUME"] : ["USE_CATALOG"]
}

# The gold TABLES: admins only (the Jobs run as the deployer / service principal, which owns them). Everyone else
# reads gold through the secure views below, which filter rows by voivodeship and mask technical columns.
resource "databricks_grant" "gold" {
  for_each   = toset(["${var.group_prefix}-admins"])
  schema     = var.gold_schema
  principal  = databricks_group.this[each.key].display_name
  privileges = ["USE_SCHEMA", "SELECT"]
}

# The secure views (schema gold_secure; created by the smogcast step `gold governance`). A view reads its tables with
# the rights of its owner, so SELECT on the views is all a reader needs.
resource "databricks_grant" "gold_secure" {
  for_each   = local.groups
  schema     = var.secure_schema
  principal  = databricks_group.this[each.key].display_name
  privileges = ["USE_SCHEMA", "SELECT"]
}

# Membership as code (the groups were empty). Users must already exist in the Databricks account.
locals {
  members = { for pair in flatten([for g, users in var.group_members : [for u in users : { group = g, user = u }]]) :
  "${pair.group}/${pair.user}" => pair }
}

data "databricks_user" "member" {
  provider  = databricks.account
  for_each  = toset(flatten(values(var.group_members)))
  user_name = each.key
}

resource "databricks_group_member" "this" {
  provider  = databricks.account
  for_each  = local.members
  group_id  = databricks_group.this[each.value.group].id
  member_id = data.databricks_user.member[each.value.user].id
}
