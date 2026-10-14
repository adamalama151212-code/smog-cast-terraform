# DEV — the author's own Azure subscription. Workspace: terraform workspace select dev

environment = "dev"
location    = "germanywestcentral"

subscription_id = "26197092-29d8-4fd7-918a-6b75bae1626e" # "Azure subscription 1", adamalama152001@gmail.com (trial, since 2026-10-11)
tenant_id       = "83e96ba9-013c-47f0-94c4-67a270df8828" # "Default Directory" of that account

# Workspace dbw-smogcast-dev (resource group smog-cast-dev, Premium, compute mode Hybrid), created by hand.
databricks_host         = "https://adb-7405617572397835.15.azuredatabricks.net"
databricks_workspace_id = "7405617572397835"
databricks_account_id   = "882356f4-9228-4d5d-9792-4aae3e991284" # <workspace host>/.well-known/databricks-config

catalog_name = "smogcast_dev"
# The DEV metastore has no default storage root; a folder under the workspace's own external location
# (databricks external-locations list: dbw_smogcast_dev).
catalog_storage_root = "abfss://unity-catalog-storage@dbstoragejw665pft2g7ow.dfs.core.windows.net/7405617572397835/smogcast_dev"

# The workspace's own "Serverless Starter Warehouse", adopted by Terraform (2X-Small, 1 min auto-stop):
# databricks warehouses list --profile <profile>. A new workspace has a new id.
sql_warehouse_id = "2d73c5dbf6ca1dc0"

key_vault_name             = "kv-smogcast-dev-adam2" # globally unique, 3-24 characters (available on 2026-10-12)
key_vault_purge_protection = false

# GIOŚ API poller (module live_ingest); both names globally unique (available on 2026-10-12)
live_storage_account_name = "stsmogcastlivedevadam2"
function_app_name         = "func-smogcast-poller-dev-adam2"

# Who is in which RLS/CLS group (E9 point 5). The demo switches roles through the smogcast table ops.access_policy,
# so the author stays an admin here.
group_members = {
  "smogcast-admins" = ["adamalama152001@gmail.com"]
}

# GitHub Actions (deploy.yml, environment "dev") logs in as the Jobs' service principal – no secret. The subject
# names the repo the workflow runs in (the clean pipeline repo) and must equal, character for character, what GitHub
# presents: the owner and the repository each followed by "@" and their numeric id (owner.id and id in
# https://api.github.com/repos/<owner>/<repo>). AADSTS700213 quotes the presented subject when they differ.
github_subjects = { gh-dev = "repo:adamalama151212-code@237463681/smog-cast-dbr@1414877305:environment:dev" }

# The app (module app_hosting; README §6d). First apply WITHOUT app_image: identities, the app's service principal,
# the Container Apps environment. Then by hand: the two secrets into Key Vault and the image into ghcr. Then set
# app_image and apply again – that creates the app. Later images come from deploy.yml of the app repo.
app_image = "ghcr.io/adamalama151212-code/smog-cast-app:2026-10-12" # the first deployment (public package)

# Region of the app's Container Apps environment only (everything else stays in `location`). Germany West Central had
# no capacity for a new environment on 2026-10-12 (ManagedEnvironmentCapacityHeavyUsageError, README §8).
app_location = "polandcentral"

# Size of the app's container (memory is tied to CPU: 2 Gi per vCPU). Measured on 2026-10-12 with 1 vCPU / 2 Gi:
# 1.39-1.47 Gi in use right after the start, so one step up for headroom.
app_cpu    = 1.5
app_memory = "3Gi"

# GitHub Actions of the app repo (deploy.yml, environment "dev") signs in as the app's deploy identity.
# The subject must equal, character for character, what GitHub presents. For this repo GitHub adds the numeric ids
# of the owner and of the repository after "@" (AADSTS700213 quotes the presented subject when they differ).
app_github_subjects = { gh-dev = "repo:adamalama151212-code@237463681/smog-cast-app@1411998699:environment:dev" }
