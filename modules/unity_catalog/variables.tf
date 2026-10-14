variable "catalog_name" {
  description = "Unity Catalog catalog of the environment, e.g. smogcast_dev"
  type        = string
}

variable "comment" {
  description = "Catalog comment"
  type        = string
}

variable "storage_root" {
  description = "Managed location (abfss://...) of the catalog; null when the metastore has a default storage root"
  type        = string
  default     = null
}

# Comments are the same as in sql/bootstrap_uc.sql of the smogcast repo, so after importing the objects
# that script created on DEV (README, "Import existing objects") the plan shows no changes for them.
variable "schemas" {
  description = "Schema name => comment"
  type        = map(string)
  default = {
    bronze = "raw data as delivered, long format"
    silver = "cleaned data, daily aggregates, model features"
    gold   = "forecast, backtest metrics, data-quality summary"
    ops    = "quarantine, late readings, data-quality metric log"
    raw    = "volumes with files: landing, checkpoints, models"
    # Row/column-secured views of gold (smogcast repo: step `gold governance`); analysts and regional groups read only these.
    gold_secure = "gold for analysts and regions: rows by voivodeship, technical columns masked"
  }
}

variable "volume_schema" {
  description = "Schema that holds the file volumes"
  type        = string
  default     = "raw"
}

variable "volumes" {
  description = "Volume name => comment (all managed, in volume_schema)"
  type        = map(string)
  default = {
    landing     = "raw downloads; originals kept in _zrodlo/"
    checkpoints = "Structured Streaming checkpoints (pm-stream)"
    models      = "Spark ML pipeline models (train -> forecast)"
  }
}
