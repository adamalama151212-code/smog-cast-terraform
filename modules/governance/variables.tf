variable "group_prefix" {
  description = "Prefix of the group names, e.g. smogcast"
  type        = string
  default     = "smogcast"
}

variable "region_codes" {
  description = "ISO 3166-2:PL voivodeship codes of the cities (jurisdiction_code in conf/cities.yaml)"
  type        = list(string)
}

variable "workspace_id" {
  description = "Numeric workspace id (the adb-<id> part of the workspace URL)"
  type        = string
}

variable "catalog_name" {
  type = string
}

variable "gold_schema" {
  description = "Full name of the gold schema (catalog.gold)"
  type        = string
}

variable "secure_schema" {
  description = "Full name of the schema with the secure views (catalog.gold_secure)"
  type        = string
}

variable "group_members" {
  description = "Group name => user e-mails to add (account users that already exist), e.g. the author in smogcast-admins"
  type        = map(list(string))
  default     = {}
}
