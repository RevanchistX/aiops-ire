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

variable "chart_version" {
  description = "Bitnami postgresql Helm chart version to pin (overrides module default)"
  type        = string
  default     = null  # uses module default when omitted
}

variable "claude_api_key" {
  description = "Anthropic API key for aiops-brain Claude claude-sonnet-4-20250514 calls"
  type        = string
  sensitive   = true
}
