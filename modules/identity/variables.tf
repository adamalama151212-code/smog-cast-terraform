variable "display_name" {
  description = "Name of the Entra ID application / service principal, e.g. sp-smogcast-dev"
  type        = string
}

variable "catalog_name" {
  description = "Catalog the principal writes to"
  type        = string
}

variable "account_id" {
  description = "Databricks account id (the principal's roles are account-level objects)"
  type        = string
}

variable "deployer_groups" {
  description = "Account groups whose members may deploy Jobs and pipelines that run as the principal; empty = nobody but the principal itself"
  type        = list(string)
  default     = []
}

variable "github_subjects" {
  description = "Credential name => GitHub OIDC subject, e.g. { gh-dev = \"repo:<owner>@<owner id>/<repo>@<repo id>:environment:dev\" }; empty until the repo exists"
  type        = map(string)
  default     = {}
}
