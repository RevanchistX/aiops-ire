variable "namespace" {
  description = "Kubernetes namespace to deploy the observability stack into"
  type        = string
}

variable "grafana_admin_password" {
  description = "Grafana admin user password"
  type        = string
  sensitive   = true
}

variable "alertmanager_webhook_url" {
  description = "Alertmanager webhook receiver URL — aiops-brain /webhook endpoint"
  type        = string
  default     = "http://aiops-brain.aiops.svc.cluster.local:8000/webhook"
}

variable "prometheus_storage_size" {
  description = "PersistentVolumeClaim size for Prometheus TSDB"
  type        = string
  default     = "10Gi"
}

variable "loki_storage_size" {
  description = "PersistentVolumeClaim size for Loki log chunks"
  type        = string
  default     = "5Gi"
}

variable "kube_prometheus_stack_version" {
  description = "prometheus-community/kube-prometheus-stack Helm chart version to pin"
  type        = string
  default     = "82.12.0"
}

variable "loki_version" {
  description = "grafana/loki Helm chart version to pin"
  type        = string
  default     = "6.55.0"
}

variable "promtail_version" {
  description = "grafana/promtail Helm chart version to pin"
  type        = string
  default     = "6.17.1"
}
