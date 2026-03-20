output "postgres_service_endpoint" {
  description = "In-cluster DNS endpoint for PostgreSQL (host:port)"
  value       = module.database.service_endpoint
}
