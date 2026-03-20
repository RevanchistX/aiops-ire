output "service_endpoint" {
  description = "In-cluster DNS endpoint for PostgreSQL (host:port)"
  value       = "${helm_release.postgresql.name}.${helm_release.postgresql.namespace}.svc.cluster.local:5432"
}

output "release_name" {
  description = "Helm release name, used to construct DATABASE_URL in later modules"
  value       = helm_release.postgresql.name
}
