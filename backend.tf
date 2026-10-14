# Where the state is stored. Each environment has its OWN container (tfstate-dev, tfstate-prod), so DEV and
# PROD states can never mix. The values live in environment/<env>/<region>/backend.hcl and are passed on init:
#
#   terraform init -backend-config="environment/dev/germanywestcentral/backend.hcl"
#   terraform init -reconfigure -backend-config="environment/<env>/<region>/backend.hcl"   # switching env
#
# Inside a container the Terraform workspace (= environment) still names the blob: "smogcast.tfstateenv:dev".
# The storage account and the containers are created once by bootstrap/create-tfstate-storage.ps1.
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
