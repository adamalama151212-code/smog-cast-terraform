# The identity that runs the smogcast Jobs and deploys the bundle from CI — never a person.
#   Entra ID application + service principal  →  added to the Databricks workspace  →  Unity Catalog grants
#   GitHub Actions logs in as it through OIDC federation (no client secret anywhere).
# Its application (client) id goes into `run_as.service_principal_name` of the bundle (databricks.yml).

terraform {
  required_providers {
    azuread    = { source = "hashicorp/azuread" }
    databricks = { source = "databricks/databricks" }
  }
}

data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name = var.display_name
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# One credential per GitHub subject, e.g. "repo:<owner>@<owner id>/<repo>@<repo id>:environment:dev". GitHub's OIDC
# token for a workflow job in that environment is exchanged for an Entra ID token of this principal.
resource "azuread_application_federated_identity_credential" "github" {
  for_each       = var.github_subjects
  application_id = azuread_application.this.id
  display_name   = each.key
  description    = "GitHub Actions: ${each.value}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value
}

resource "databricks_service_principal" "this" {
  application_id = azuread_service_principal.this.client_id
  display_name   = var.display_name
  # Job clusters are created on behalf of the principal the Job runs as.
  allow_cluster_create  = true
  workspace_access      = true
  databricks_sql_access = true
}

# Who may deploy Jobs and pipelines that run as this principal (`run_as` in the bundle) from a laptop. Databricks asks
# the deployer for the Service Principal User role on the principal – being a workspace admin, or its creator (who
# only gets the Manager role), is not enough: "Cannot bind the service principal provided in 'run_as' field".
# CI needs nothing here: it deploys as the principal itself.
# A rule set is authoritative for its principal, so the Manager role is listed too instead of being dropped.
resource "databricks_access_control_rule_set" "deployers" {
  count = length(var.deployer_groups) > 0 ? 1 : 0
  name  = "accounts/${var.account_id}/servicePrincipals/${databricks_service_principal.this.application_id}/ruleSets/default"

  grant_rules {
    principals = [for g in var.deployer_groups : "groups/${g}"]
    role       = "roles/servicePrincipal.user"
  }

  grant_rules {
    principals = [for g in var.deployer_groups : "groups/${g}"]
    role       = "roles/servicePrincipal.manager"
  }
}

# Everything the pipeline does in its catalog: create schemas (safety net in storage.py), write tables,
# read and write the volumes. Granted on the catalog, so it is inherited by every schema and volume in it.
# databricks_grant (not _grants) adds this principal's grants without touching anyone else's.
resource "databricks_grant" "catalog" {
  catalog   = var.catalog_name
  principal = databricks_service_principal.this.application_id
  privileges = [
    "USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE", "CREATE_FUNCTION",
    "SELECT", "MODIFY", "EXECUTE", "READ_VOLUME", "WRITE_VOLUME",
    # the declarative stream pipeline runs as this principal; its cleaned tables are materialized views
    # (silver.pm_stream, ops.pm_stream_quarantine, ops.pm_late_rejected) – CREATE_TABLE does not cover them
    "CREATE_MATERIALIZED_VIEW",
    # the `gold governance` step tags gold columns (class = business / technical) in Unity Catalog
    "APPLY_TAG",
  ]
}
