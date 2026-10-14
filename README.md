# Terraform Infrastructure Setup Guide — smogcast

Infrastructure around the **smogcast** data platform (tomorrow's PM10/PM2.5 exceedance forecast) on Azure
Databricks: Unity Catalog objects, Key Vault + secret scope, the service principal that runs the Jobs and
deploys from CI, and the groups for row/column-level security.

Not managed here: the Databricks **workspaces** (DEV created by hand, PROD provided by the course — only
referenced by URL/id), the **tables** (created by the Jobs) and the **RLS/CLS secure views** (created in `gold_secure` by the smogcast step `gold governance`).

| Environment | Workspace | `-var-file` |
|---|---|---|
| dev | `dev` | `environment/dev/germanywestcentral/terraform.tfvars` (state: `backend.hcl` next to it, container `tfstate-dev`) |

**This repository manages DEV only.** PROD runs on the course's shared Databricks account, where we may not create
Azure resources, a service principal or account groups: there the Databricks part (schemas, volumes, Jobs, the
pipeline, the dashboard) is created by the Asset Bundle of the pipeline repository
[`smog-cast-dbr`](https://github.com/adamalama151212-code/smog-cast-dbr) (target `prod`), deployed by CI from a release
tag. The Azure Function, Key Vault and the app's hosting exist only in the author's subscription (DEV); the course
agreed to present the app from there. The code keeps the per-environment layout (`environment/<env>/<region>/`), so
a PROD of our own would need only its var files.

## 1. Install and Configure Azure CLI and Terraform

- Download Terraform: [https://developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install)
- Download Azure CLI: [https://learn.microsoft.com/cli/azure/install-azure-cli](https://learn.microsoft.com/cli/azure/install-azure-cli)

	```powershell
	winget install Hashicorp.Terraform
	winget install Microsoft.AzureCLI
	```

- Log in (all providers use this login — no keys in files):

	```powershell
	az login
	az account show --query "{name:name, id:id, tenant:tenantId}" -o table
	```

- **Check the subscription before every run** — it must match `subscription_id` in the var-file:

	```powershell
	az account set --subscription <subscription-id>
	```

## 2. Storage for the Terraform State (one-off)

"Backend" in Terraform means **where the state file is stored** (`backend.tf`) — the Azure equivalent of the S3
bucket for state. It has nothing to do with an application backend. **Each environment has its own container**
(`tfstate-dev`, `tfstate-prod`) in the author's storage account, so the DEV and PROD states never mix. The
container must exist before the first `terraform init`, so it is created once per environment with the Azure CLI:

	```powershell
	.\bootstrap\create-tfstate-storage.ps1 -StorageAccount stsmogcasttf<suffix> -Environment dev
	```

- Put the printed `storage_account_name` into `environment/dev/germanywestcentral/backend.hcl`, then:

	```powershell
	terraform init -backend-config="environment/dev/germanywestcentral/backend.hcl"
	```

- Switching to another environment re-points the backend (never only `workspace select`):

	```powershell
	terraform init -reconfigure -backend-config="environment/<env>/<region>/backend.hcl"
	```

	The role that lets you write the state needs 1-5 minutes after the script; if `init` gets
	`AuthorizationPermissionMismatch`, wait and run it again.

## 3. Terraform Workspace Management

- **List workspaces:**
	```powershell
	terraform workspace list
	```
- **Select a workspace:**
	```powershell
	terraform workspace select dev
	```
- **Create a new workspace:**
	```powershell
	terraform workspace new dev
	```
- **Show the current workspace (always before plan/apply):**
	```powershell
	terraform workspace show
	```

The workspace must match `environment` in the var-file — otherwise the plan stops with
`Workspace '...' does not match environment '...'` (guard in `main.tf`).

## 4. Terraform Operations (Dev Example)

- **Check changes:**
	```powershell
	terraform plan -var-file="./environment/dev/germanywestcentral/terraform.tfvars"
	```
- **Apply changes:**
	```powershell
	terraform apply -var-file="./environment/dev/germanywestcentral/terraform.tfvars"
	```
- **Destroy resources:**
	```powershell
	terraform destroy -var-file="./environment/dev/germanywestcentral/terraform.tfvars"
	```
- **Values for the smogcast repo** (`databricks.yml`, `conf/dev.yaml`, GitHub Actions):
	```powershell
	terraform output
	```
- **Before every commit:**
	```powershell
	terraform fmt -recursive
	terraform validate
	```

- **Apply on enviroment:**
	```powershell
	$vf = "./environment/dev/germanywestcentral/terraform.tfvars"
	terraform plan "-var-file=environment/dev/germanywestcentral/terraform.tfvars" "-out=dev.tfplan" -out="dev.tfplan" -no-color | Out-File plan-dev.txt -Encoding utf8
	```


## 5. Import Existing Objects (DEV, once)

The `smogcast_dev` catalog, its schemas and volumes were created by hand with `sql/bootstrap_uc.sql` (smogcast
repo) before this repository existed. Import them **before the first apply**, otherwise the apply fails with
"already exists":

```powershell
terraform workspace select dev
$vf = "./environment/dev/germanywestcentral/terraform.tfvars"

terraform import -var-file="$vf" module.unity_catalog.databricks_catalog.this smogcast_dev

foreach ($s in "bronze", "silver", "gold", "ops", "raw") {
    terraform import -var-file="$vf" "module.unity_catalog.databricks_schema.this[\`"$s\`"]" "smogcast_dev.$s"
}

foreach ($v in "landing", "checkpoints", "models") {
    terraform import -var-file="$vf" "module.unity_catalog.databricks_volume.this[\`"$v\`"]" "smogcast_dev.raw.$v"
}
```

Then `terraform plan` must show **no changes and no destroy** for the catalog, schemas and volumes — only new
resources (resource group, Key Vault, secret scope, service principal, groups, grants).

The `\`"` escaping is for Windows PowerShell 5.1 (it strips plain quotes from native-command arguments). In
PowerShell 7.3+ use `"module.unity_catalog.databricks_schema.this[`"$s`"]"` instead.

## 6. Modules

| Module | Creates | Why |
|---|---|---|
| `unity_catalog` | catalog `smogcast_<env>` (with a managed location when the metastore has none), schemas `bronze` `silver` `gold` `ops` `raw` `gold_secure`, volumes `landing` `checkpoints` `models` | medallion in Unity Catalog; paths must match `conf/<env>.yaml` of the smogcast repo |
| `secrets` | Key Vault (access policies: you — write, AzureDatabricks app — read), secret scope `smogcast` | secrets in Key Vault; Jobs read `dbutils.secrets.get("smogcast", "<key>")` |
| `identity` | Entra ID application + service principal, the same principal in the workspace, catalog grants, GitHub OIDC credentials | Jobs on PROD run as a principal, not a person (`run_as` in `databricks.yml`); CI deploys without a secret |
| `governance` | account groups `smogcast-admins`, `smogcast-analysts`, `smogcast-region-PL-xx` (the voivodeships in `region_codes`: PL-02 Wrocław, PL-12 Kraków), workspace assignment, members from `group_members` (users that exist in the account), SELECT on the **gold tables for admins only** and on the **secure views (`gold_secure`) for every group** | RLS by voivodeship, CLS on technical columns — the dynamic views are created by the smogcast step `gold governance`; besides the groups they honour the table `ops.access_policy` (works where account groups cannot be managed) |
| `live_ingest` | storage account (ADLS Gen2) with containers `live` and `function-deployment`; Azure Function `gios_poller` (Flex Consumption, Python 3.11, user-assigned identity, Application Insights); Databricks access connector → storage credential → external location → **external volume `<catalog>.raw.landing_live`** | the GIOŚ API is polled every hour outside Databricks (no cluster start for ~20 s of HTTP); the poll files land where the stream pipeline's Auto Loader reads them. Managed identities only — no keys in the data path |

| `app_hosting` | Databricks service principal `sp-smogcast-app-<env>` (SQL access only) in the group `smogcast-analysts`; user-assigned identity `id-smogcast-app-<env>` with `Get` on the Key Vault's secrets; Log Analytics workspace, Container Apps environment (Consumption) and the **Container App** `ca-smogcast-app-<env>` (public image from ghcr.io, 1 vCPU / 2 GiB, exactly one replica, port 3000, external HTTPS ingress); deploy identity `id-smogcast-app-<env>-deploy` with GitHub OIDC and Container Apps Contributor on that one app | the app (repo `smog-cast-app`) reads `gold_secure` through the SQL Warehouse as an analyst; its two secrets stay in Key Vault and never touch the state; the app repo deploys new images without any secret (§6d) |

## 6a. Deploy the Poller Code (after the first apply of `live_ingest`)

Terraform creates the function app; its CODE comes from the smogcast repo (`functions/gios_poller`):

```powershell
$fn = terraform output -raw live_function_app_name
cd "C:\Users\Leszek\DEMO RADPLUME\DEMO"
docker compose run --rm smogcast bash functions/gios_poller/build.sh      # -> functions/gios_poller/dist/gios_poller.zip
az functionapp deployment source config-zip -g rg-smogcast-dev -n $fn --src functions/gios_poller/dist/gios_poller.zip
```

The function runs every hour at :25 UTC (`poll_schedule`); its logs are in Application Insights `appi-<function app>`.

## 6b. CI deploy (`deploy.yml` in the smogcast repo)

GitHub Actions logs in as the Jobs' service principal through OIDC (no secret): `github_subjects` in the
environment's `terraform.tfvars` names the repo and the GitHub Environment
(`repo:<owner>@<owner id>/<repo>@<repo id>:environment:dev` – exactly what GitHub presents, see `AADSTS700213` in §8), and
`azurerm_role_assignment.ci_deploys_function` lets the principal upload the poller code (Website Contributor on that
one function app). After `apply`, put these ids (not secrets) into the GitHub Environment's variables:

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID` | `terraform output` of `module.identity.application_id` |
| `AZURE_TENANT_ID` | tenant id |
| `AZURE_SUBSCRIPTION_ID` | subscription id |
| `FUNCTION_RESOURCE_GROUP`, `FUNCTION_APP_NAME` | resource group and `function_app_name` of `live_ingest` |

PROD on the course account: no own principal (the course has one) — the `identity` module and this role stay off
for `prod`; how CI logs in there is agreed with the course technician.

## 6c. SQL Warehouse (root `main.tf`)

Every new workspace comes with a **"Serverless Starter Warehouse"** — Small, 10 min auto-stop: ~9.6 EUR per running
hour and at least 10 minutes billed per wake-up (on DEV 42.7 of the first 48.7 EUR, 2026-10-06..09). Terraform
**adopts** it (an `import` block — no second warehouse: the bundle finds it by name, the SQL Editor uses it by default)
and keeps it at **2X-Small** (4 DBU/h instead of 12) with **1 minute** auto-stop (the shortest a serverless warehouse
accepts; `0` would switch auto-stop off — the variable's validation forbids it). Before the first plan of a workspace,
put its id into the var-file:

```powershell
databricks warehouses list --profile <profile>     # id of "Serverless Starter Warehouse" -> sql_warehouse_id
```

The first plan shows **1 to import** (and 1 to change if the warehouse still has the default size); later plans:
no changes. `terraform output sql_warehouse_id` → `DATABRICKS_WAREHOUSE_ID` of the app. `prevent_destroy` guards it.

## 6d. The app on Azure Container Apps (module `app_hosting`)

The app needs two secrets, and Azure reads them from Key Vault **when it creates the app** – so they must be there
first, and one of them (the service principal's OAuth secret) can only be generated once the principal exists. Hence
two applies, switched by `app_image` in the environment's `terraform.tfvars`:

1. **First apply, `app_image` not set** – everything but the app: the service principal `sp-smogcast-app-<env>` and
   its membership in `smogcast-analysts`, the app's identity and its `Get` policy on the vault (the vault is updated
   in place), Log Analytics, the Container Apps environment, the deploy identity with its GitHub credential.
2. **The two secrets, by hand** (values never shown and never in the state):

    ```powershell
    $p  = "<databricks cli profile>"; $kv = terraform output -raw key_vault_name
    # the OAuth secret of the app's principal: generated and passed straight to Key Vault (90 days)
    $sp = (databricks service-principals list --profile $p -o json | ConvertFrom-Json |
           Where-Object displayName -eq (terraform output -raw app_service_principal_name)).id
    $s  = (databricks service-principal-secrets-proxy create $sp --lifetime 7776000s --profile $p -o json | ConvertFrom-Json).secret
    az keyvault secret set --vault-name $kv --name app-databricks-client-secret --value $s --output none; $s = $null
    # the language-model key, taken from the app repo's local .env
    $k  = (Get-Content <app repo>\.env | Where-Object { $_ -like "SMOGCAST_LLM_API_KEY=*" }) -replace "^SMOGCAST_LLM_API_KEY=", ""
    az keyvault secret set --vault-name $kv --name app-llm-api-key --value $k --output none; $k = $null
    ```

    (The same secret can be generated in the workspace: Settings → Identity and access → Service principals →
    the principal → Secrets → Generate secret. A secret lives at most 730 days; renew it before it expires –
    `az keyvault secret set` again, then restart the app's revision.)
3. **The image** – built in the app repo and pushed to `ghcr.io/<owner>/smog-cast-app:<tag>`; the package must be
   **public** (GitHub → the package → Package settings → Change visibility), the app pulls it without credentials.
4. **Second apply, `app_image = "ghcr.io/<owner>/smog-cast-app:<tag>"`** – creates the Container App and the deploy
   identity's role on it. `terraform output app_url` is the public address.

From then on the image is changed by `deploy.yml` of the app repo (`az containerapp update --image …`); Terraform
ignores the image (`lifecycle.ignore_changes`), so a later apply does not roll the app back. GitHub Environment
variables of the app repo (ids, not secrets): `AZURE_CLIENT_ID` = `terraform output app_deploy_client_id`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `CONTAINER_APP_NAME` = `terraform output app_container_app_name`,
`CONTAINER_APP_RESOURCE_GROUP` = `rg-smogcast-<env>`.

Why it is built this way:

- **One replica, always on** (`min_replicas = max_replicas = 1`): the conversations live in the memory of the
  process; about 0.7 USD a day on DEV.
- **No grant on the SQL Warehouse**: the workspace group `users` already has `CAN_USE` on it. `databricks_permissions`
  is authoritative – declaring it for the app would replace that list and lock out everyone else.
- **Access policy, not an Azure role, on the vault**: the vault uses access policies (the model Databricks documents
  for Key Vault-backed scopes), and its policies are declared inside the vault resource – `reader_object_ids` of the
  module `secrets`.
- **PROD (course account):** no principal can be created there by us, and there are no account groups. The app only
  needs a principal's id and an OAuth secret, so the course creates (or names) the principal and generates the
  secret; its `analyst` role then comes from the smogcast table `ops.access_policy`. The principal and the group
  membership of this module must be switched off for `prod` when PROD is set up (like the groups of `governance`).

## 7. Secrets

Terraform creates the vault and the scope, **not the secret values** (they would end up in the state). Set a value:

```powershell
az keyvault secret set --vault-name <key_vault_name> --name <key> --value "<value>"
```

Sometimes You get an error that You cannot create a Key Vault because a vault with this name is **soft-deleted**
(after a `destroy`, names stay reserved for 7 days). In this case purge it using command line:

```powershell
az keyvault list-deleted --query "[].name" -o tsv
az keyvault purge --name <key_vault_name>
```

might also add the subscription at the end to force a given Azure subscription
```powershell
az keyvault purge --name kv-smogcast-dev-adam --subscription <subscription-id>
```

(Not possible on PROD: purge protection is on there — choose a different name instead.)

## 8. Known Errors

- **`Workspace 'default' does not match environment 'dev'`** — you forgot `terraform workspace select dev`.
- **`No value for required variable "environment"`** — you forgot `-var-file=...`.
- **`AuthorizationPermissionMismatch` on `terraform init`** — the state role from step 2 is not active yet; wait a few minutes.
- **Creating the secret scope fails with a service principal** — a Key Vault-backed scope can only be created
  by a user (`az login` as a person); run that apply interactively, not from CI.
- **`databricks_group` / `databricks_mws_permission_assignment` fail with 403** — you are not a Databricks
  **account admin** (needed for groups); ask the account admin (on PROD: the course).
- **`az login` picks the Windows account and finds no subscriptions** — the CLI signs in through the Windows
  account broker by default: `az account clear; az config set core.enable_broker_on_windows=false; az login`
  (a browser opens and any account can be chosen).
- **`AADSTS70011 … scope '2ff814a6-…/.default' does not exist` (account provider, `tenant=common`)** —
  `tenant_id` is missing from the var-file; the account endpoint cannot infer the tenant.
- **Function host: `There was an error performing a read operation on the Blob Storage Secret Repository`, 403
  `AuthenticationFailed`; `az functionapp deployment source config-zip` ends with `Failed to fetch host key`** — an open
  azurerm bug ([#29149](https://github.com/hashicorp/terraform-provider-azurerm/issues/29149)): with identity-based
  storage the provider injects `AzureWebJobsStorage = "…;AccountKey=;…"` (empty key, hidden from the plan), which wins
  over the `AzureWebJobsStorage__*` identity settings. `terraform_data.drop_keyless_webjobs_storage` in `live_ingest`
  deletes it after every change of the function app; by hand:
  `az functionapp config appsettings delete -g rg-smogcast-dev -n <function app> --setting-names AzureWebJobsStorage`.
- **`ManagedEnvironmentCapacityHeavyUsageError` / `AKSCapacityHeavyUsage` when creating the Container Apps
  environment** — the region has no capacity for new environments right now (a Free Trial subscription is served
  last). Nothing is wrong with the configuration. The failed environment stays in Azure in the state `Failed` but
  not in the Terraform state, so delete it before trying again
  (`az resource delete --ids <id of cae-smogcast-app-<env>>`), then either retry later or set `app_location` in the
  environment's `terraform.tfvars` to another region (only the environment and the app move; identities, logs and
  the vault stay).
- **`AADSTS700213: No matching federated identity record found for presented assertion subject '…'` in a GitHub
  Actions login (`azure/login`)** — the subject of the federated credential differs from what GitHub presents. The
  error quotes the presented subject: copy it as it is into `app_github_subjects` (or `github_subjects`) of the
  environment's `terraform.tfvars`. For the app repo GitHub presents the numeric ids of the owner and the repository
  too: `repo:<owner>@<owner id>/<repo>@<repo id>:environment:<env>` (ids: `https://api.github.com/repos/<owner>/<repo>`,
  fields `owner.id` and `id`).
- **`Invalid for_each argument` / `Invalid index` during `terraform import`** — fixed in the modules (keys and
  names come from variables, not from resources); if it returns after a change, check `for_each` over resources.

## 9. History (DEV)

- 2026-10-07 — first apply on the author's trial subscription: state storage `stsmogcasttfadam` (container
  `tfstate-dev`), catalog `smogcast_dev` + 5 schemas + 3 volumes **imported**, then 25 new resources (resource group,
  Key Vault `kv-smogcast-dev-adam`, secret scope `smogcast`, service principal `sp-smogcast-dev`, 4 RLS/CLS groups:
  admins, analysts, region PL-02, region PL-12). Follow-up plan: no changes.
- 2026-10-07 — `live_ingest` applied (14 resources: storage `stsmogcastlivedevadam`, function app
  `func-smogcast-poller-dev-adam`, access connector, storage credential, external location, external volume
  `smogcast_dev.raw.landing_live`). The function host could not reach its storage (azurerm #29149, see §8) — the
  injected setting was deleted with `az`, and the workaround `terraform_data.drop_keyless_webjobs_storage` was added.
- 2026-10-08 — the workaround applied (1 to add); the Application Insights link tag that Azure adds to the function
  app is ignored (`lifecycle.ignore_changes`), so plans stay clean. Function host healthy, hourly polls continue.
- 2026-10-08 — RLS/CLS (smogcast E9 point 5) applied: 6 to add, 0 to change, 3 to destroy — schema
  `smogcast_dev.gold_secure`, `USE SCHEMA` + `SELECT` on it for the 4 groups, the author in `smogcast-admins`; the
  `SELECT` grants on `gold` of analysts, PL-02 and PL-12 removed (only admins read the gold tables). Checked with
  `SHOW GRANTS ON SCHEMA`. **PROD (author's decision):** roles come only from the smogcast table `ops.access_policy` —
  no account groups there (no account admin on the course account), so the group part of `governance` must be
  switched off for `prod` when PROD is set up.
- 2026-10-09 — costs: the Starter Warehouse (Small, 10 min auto-stop) took 42.7 of 48.7 EUR. Resized by hand
  (`databricks warehouses edit`, author's consent) to 2X-Small with 1 min auto-stop; the same settings added as code
  (§6c, import + `databricks_sql_endpoint.starter`) so the new account (~2026-10-11) starts with them.
- 2026-10-10 — applied: 1 imported (the warehouse, no changes), 2 added (CI: Website Contributor on the function app,
  GitHub OIDC credential `gh-dev`), 1 changed (`APPLY_TAG` on the catalog for the Jobs' principal); 0 destroyed.

- 2026-10-12 — **DEV from scratch on a new subscription** (`adamalama152001@gmail.com`, trial; the first trial is
  ending): state storage `stsmogcasttfadam2`, workspace `dbw-smogcast-dev` created by hand (**Hybrid**, not Serverless –
  the Jobs need classic clusters), `Microsoft.App` registered by hand. First apply: 1 imported (the warehouse, resized
  to 2X-Small / 1 min), 54 added – stopped on the last resource with `inconsistent values for sensitive attribute`
  (`terraform_data.drop_keyless_webjobs_storage` watched the whole function app object, unknown on a first create);
  the trigger is now a hash of the app, second apply: 1 added. Globally unique names carry the suffix `2`
  (`kv-smogcast-dev-adam2`, `stsmogcastlivedevadam2`, `func-smogcast-poller-dev-adam2`); GitHub OIDC subject =
  `repo:adamalama151212-code/smog-cast-dbr:environment:dev`.

- 2026-10-12 — **`app_hosting`, first apply (no image yet)**: 6 added and the Key Vault changed in place (a `Get`
  policy for the app's identity) – service principal `sp-smogcast-app-dev` in `smogcast-analysts`, identities
  `id-smogcast-app-dev` and `id-smogcast-app-dev-deploy`, GitHub credential `gh-dev`
  (`repo:adamalama151212-code/smog-cast-app:environment:dev`), `log-smogcast-app-dev`. The Container Apps
  environment failed with `ManagedEnvironmentCapacityHeavyUsageError` in Germany West Central (§8); the failed
  environment was deleted by hand, `app_location = "polandcentral"` added, second apply: 2 added (environment
  `cae-smogcast-app-dev` in **Poland Central**, the deploy identity's role on it).
- 2026-10-12 — **the app is live**: the two secrets set by hand (`app-databricks-client-secret`, valid until
  2027-01-10, and `app-llm-api-key`), the image pushed to `ghcr.io/adamalama151212-code/smog-cast-app:2026-10-12`
  (public package), `app_image` set, apply: 2 added (Container App `ca-smogcast-app-dev`, the deploy identity's
  role on it). Revision healthy, one replica; address: `terraform output app_url`. The principal's login and its
  analyst role were tried locally before the apply (10 of 10 secure views, technical columns masked).

## 10. Releases

Every merge to `main` updates one release pull request (release-please, `.github/workflows/release-please.yml`): the
next version worked out from the conventional commit messages (`feat:` → minor, `fix:` → patch; before 1.0 a `feat`
still bumps only the minor) and `CHANGELOG.md`. Merging it bumps `VERSION`, tags the commit (`vX.Y.Z`) and creates a
GitHub release. Nothing is applied by a workflow: `plan` and `apply` stay with a person (section 4).

Repo setting needed once: Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests".
