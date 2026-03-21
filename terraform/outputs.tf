output "postgres_service_endpoint" {
  description = "In-cluster DNS endpoint for PostgreSQL (host:port)"
  value       = module.database.service_endpoint
}

output "grafana_endpoint" {
  description = "In-cluster DNS endpoint for Grafana (port-forward to access from host)"
  value       = module.observability.grafana_endpoint
}

output "prometheus_endpoint" {
  description = "In-cluster DNS endpoint for Prometheus"
  value       = module.observability.prometheus_endpoint
}

output "loki_endpoint" {
  description = "In-cluster DNS endpoint for Loki — set as LOKI_URL in aiops-brain"
  value       = module.observability.loki_endpoint
}

output "flask_app_dns" {
  description = "In-cluster DNS name for the flask-app chaos target Service"
  value       = module.apps.service_dns
}
