output "trading_ui_node_port" {
  description = "NodePort exposed for trading-ui (access via http://<node-ip>:30500)"
  value       = 30500
}

output "postgresql_primary_endpoint" {
  description = "ClusterIP DNS name for the primary PostgreSQL service"
  value       = "postgresql-primary.${var.namespace}.svc.cluster.local:5432"
}

output "postgresql_dr_endpoint" {
  description = "ClusterIP DNS name for the DR PostgreSQL service"
  value       = "postgresql-dr.${var.namespace}.svc.cluster.local:5432"
}
