output "service_endpoint" {
  description = "In-cluster DNS endpoint for PostgreSQL (host:port)"
  value       = "${kubernetes_service.postgresql.metadata[0].name}.${kubernetes_service.postgresql.metadata[0].namespace}.svc.cluster.local:5432"
}

output "service_name" {
  description = "Kubernetes service name for PostgreSQL"
  value       = kubernetes_service.postgresql.metadata[0].name
}
