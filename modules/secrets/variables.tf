variable "key_vault_name" {
  description = "Globally unique Key Vault name, 3-24 characters (letters, digits, hyphens)"
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "scope_name" {
  description = "Databricks secret scope name used by the Jobs (dbutils.secrets.get(scope, key))"
  type        = string
  default     = "smogcast"
}

variable "purge_protection" {
  description = "Key Vault purge protection (cannot be turned off once on)"
  type        = bool
  default     = false
}

variable "reader_object_ids" {
  description = "Object ids of identities that may read (Get) secrets, e.g. the managed identity of the hosted app"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
