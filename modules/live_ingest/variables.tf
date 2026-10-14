variable "environment" {
  description = "dev | prod — also SMOGCAST_ENV of the function (conf/<env>.yaml of the smogcast package)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the smogcast Azure resources"
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique storage account of the poll files, 3-24 lowercase letters and digits"
  type        = string
}

variable "function_app_name" {
  description = "Globally unique function app name (also the stem of its identity, plan, insights, connector)"
  type        = string
}

variable "poll_schedule" {
  description = "NCRONTAB (6 fields, UTC) of the poll; GIOŚ publishes the past hour ~20 min after it"
  type        = string
  default     = "0 25 * * * *"
}

variable "landing_folder" {
  description = "Folder in the container that the volume points at (the function writes below it)"
  type        = string
  default     = "landing"
}

variable "catalog_name" {
  description = "Unity Catalog catalog of the environment"
  type        = string
}

variable "volume_schema" {
  description = "Schema of the file volumes (conf/<env>.yaml: /Volumes/<catalog>/<schema>/...)"
  type        = string
  default     = "raw"
}

variable "volume_name" {
  description = "External volume of the poll files; storage.live_landing_root in conf/<env>.yaml points at it"
  type        = string
  default     = "landing_live"
}

variable "tags" {
  type    = map(string)
  default = {}
}
