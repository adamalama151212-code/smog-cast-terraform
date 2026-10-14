# =============================================================================
# One-off per environment: storage for the Terraform state. One storage account, one CONTAINER per
# environment (tfstate-dev, tfstate-prod) — the DEV and PROD states never share a container.
#
# Terraform cannot keep its state in a storage account it creates itself, so this account is made
# with the Azure CLI before the first `terraform init`. Re-running is safe (create = no-op if present).
#
#   az login
#   .\bootstrap\create-tfstate-storage.ps1 -StorageAccount stsmogcasttf<suffix> -Environment dev
#
# Then put the printed values into environment/<env>/<region>/backend.hcl.
# =============================================================================
param(
    # Globally unique, 3-24 lowercase letters and digits (e.g. stsmogcasttfadam).
    [Parameter(Mandatory = $true)] [string] $StorageAccount,
    [string] $ResourceGroup = "rg-smogcast-tfstate",
    [Parameter(Mandatory = $true)] [ValidateSet("dev", "prod")] [string] $Environment,
    [string] $Location = "germanywestcentral"
)

$Container = "tfstate-$Environment"

$ErrorActionPreference = "Stop"

# Windows PowerShell does not stop on a failing native command; check every az call explicitly.
function Invoke-Az {
    $out = & az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed (exit $LASTEXITCODE)" }
    return $out
}

Write-Host "Subscription:" (Invoke-Az account show --query "{name:name, id:id}" -o tsv)

Invoke-Az group create --name $ResourceGroup --location $Location `
    --tags project=smogcast purpose=terraform-state | Out-Null

Invoke-Az storage account create --name $StorageAccount --resource-group $ResourceGroup --location $Location `
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false `
    --tags project=smogcast purpose=terraform-state | Out-Null

# Versioning keeps every previous state file: a broken apply can be rolled back by restoring a version.
Invoke-Az storage account blob-service-properties update --account-name $StorageAccount `
    --resource-group $ResourceGroup --enable-versioning true | Out-Null

# Created with the account key (works immediately); Terraform itself then uses Entra ID (use_azuread_auth).
Invoke-Az storage container create --name $Container --account-name $StorageAccount --auth-mode key | Out-Null

# Terraform reads and writes the state as the signed-in user, not with the account key.
$me = Invoke-Az ad signed-in-user show --query id -o tsv
$scope = Invoke-Az storage account show --name $StorageAccount --resource-group $ResourceGroup --query id -o tsv
# No parentheses in --query: az is a .cmd file on Windows and cmd.exe breaks on "length(@)".
$existing = Invoke-Az role assignment list --assignee $me --scope $scope --role "Storage Blob Data Contributor" --query "[].id" -o tsv
if (-not $existing) {
    Invoke-Az role assignment create --assignee-object-id $me --assignee-principal-type User `
        --role "Storage Blob Data Contributor" --scope $scope | Out-Null
    Write-Host "Role assigned; Azure needs 1-5 minutes before terraform init can use it."
}

Write-Host ""
Write-Host "Put this into environment/$Environment/<region>/backend.hcl:"
Write-Host "  resource_group_name  = `"$ResourceGroup`""
Write-Host "  storage_account_name = `"$StorageAccount`""
Write-Host "  container_name       = `"$Container`""
