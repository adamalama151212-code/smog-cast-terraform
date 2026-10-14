# DEV state — the author's subscription. Used on init:
#   terraform init -backend-config="environment/dev/germanywestcentral/backend.hcl"
# Values printed by: .\bootstrap\create-tfstate-storage.ps1 -StorageAccount <name> -Environment dev

resource_group_name  = "rg-smogcast-tfstate"
storage_account_name = "stsmogcasttfadam2" # globally unique, 3-24 lowercase letters/digits (created 2026-10-12)
container_name       = "tfstate-dev"
key                  = "smogcast.tfstate"
