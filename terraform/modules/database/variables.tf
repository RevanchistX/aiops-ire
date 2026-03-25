variable "namespace" {
  description = "Kubernetes namespace to deploy PostgreSQL into"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name to create on startup"
  type        = string
}

variable "db_user" {
  description = "PostgreSQL application user name"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL application user password"
  type        = string
  sensitive   = true
}

variable "storage_size" {
  description = "PersistentVolumeClaim size for PostgreSQL data volume"
  type        = string
  default     = "5Gi"
}
