variable "github_token" {
  description = "GitHub personal access token with repo scope for issue creation"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. acme/aiops-ire)"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name for the aiops incidents store"
  type        = string
  default     = "aiops"
}

variable "db_user" {
  description = "PostgreSQL application user name"
  type        = string
  default     = "aiops"
}

variable "db_password" {
  description = "PostgreSQL application user password"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin user password for the observability stack"
  type        = string
  sensitive   = true
}

variable "claude_api_key" {
  description = "Anthropic API key for aiops-brain Claude claude-sonnet-4-20250514 calls"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for incident notifications (optional — omit to disable)"
  type        = string
  sensitive   = true
  default     = ""
}

# ─── CryptoFlux ───────────────────────────────────────────────────────────────

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
  description = "dr-sync replication interval in seconds (RPO target: < 5 min)"
  type        = number
  default     = 300
}
