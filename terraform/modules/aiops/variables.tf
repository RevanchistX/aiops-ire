variable "namespace" {
  description = "Kubernetes namespace to deploy aiops-brain into"
  type        = string
}

variable "claude_api_key" {
  description = "Anthropic API key for Claude claude-sonnet-4-20250514"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub PAT with repo scope — used to open incident issues"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. acme/aiops-ire)"
  type        = string
}

variable "database_url" {
  description = "Full PostgreSQL connection URL (postgresql://user:pass@host:5432/db)"
  type        = string
  sensitive   = true
}

variable "loki_url" {
  description = "In-cluster HTTP URL for the Loki query API"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for incident notifications (optional — leave empty to disable)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "image" {
  description = "Container image for aiops-brain (must be pre-loaded into k3s via build-and-load.sh)"
  type        = string
  default     = "aiops-brain:latest"
}
