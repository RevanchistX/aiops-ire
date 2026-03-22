variable "namespace" {
  description = "Kubernetes namespace to deploy CryptoFlux into"
  type        = string
}

# ─── Primary PostgreSQL ────────────────────────────────────────────────────────

variable "cf_db_name" {
  description = "PostgreSQL database name for CryptoFlux primary"
  type        = string
  default     = "cryptoflux"
}

variable "cf_db_user" {
  description = "PostgreSQL user for CryptoFlux primary"
  type        = string
  default     = "cryptouser"
}

variable "cf_db_pass" {
  description = "PostgreSQL password for CryptoFlux primary"
  type        = string
  sensitive   = true
}

# ─── DR PostgreSQL ─────────────────────────────────────────────────────────────

variable "cf_dr_db_name" {
  description = "PostgreSQL database name for CryptoFlux DR replica"
  type        = string
  default     = "cryptoflux_dr"
}

variable "cf_dr_db_user" {
  description = "PostgreSQL user for CryptoFlux DR replica"
  type        = string
  default     = "dr_user"
}

variable "cf_dr_db_pass" {
  description = "PostgreSQL password for CryptoFlux DR replica"
  type        = string
  sensitive   = true
}

# ─── Application secrets ───────────────────────────────────────────────────────

variable "cf_secret_key" {
  description = "Flask SECRET_KEY for trading-ui session signing"
  type        = string
  sensitive   = true
}

variable "cf_trading_data_api_key" {
  description = "API key shared between trading-data, trading-ui, and liquidity-calc"
  type        = string
  sensitive   = true
}

variable "cf_ext_api_key" {
  description = "API key for the external transactions API (ext-api)"
  type        = string
  sensitive   = true
}

# ─── Worker tuning ────────────────────────────────────────────────────────────

variable "cf_interval_seconds" {
  description = "data-ingestion polling interval in seconds"
  type        = number
  default     = 300
}

variable "cf_batch_size" {
  description = "data-ingestion batch size per poll cycle"
  type        = number
  default     = 100
}

variable "cf_retention_days" {
  description = "data-ingestion transaction retention in days"
  type        = number
  default     = 1
}

variable "cf_sync_interval_seconds" {
  description = "dr-sync replication interval in seconds (RPO target)"
  type        = number
  default     = 300
}
