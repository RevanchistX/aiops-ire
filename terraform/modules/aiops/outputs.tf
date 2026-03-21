output "service_dns" {
  description = "In-cluster DNS name for the aiops-brain Service (webhook target for Alertmanager)"
  value       = "${kubernetes_service.aiops_brain.metadata[0].name}.${var.namespace}.svc.cluster.local"
}

output "webhook_url" {
  description = "Full webhook URL to configure in Alertmanager"
  value       = "http://${kubernetes_service.aiops_brain.metadata[0].name}.${var.namespace}.svc.cluster.local:8000/webhook"
}

output "service_account_name" {
  description = "ServiceAccount name used by the aiops-brain pod"
  value       = kubernetes_service_account.aiops_brain.metadata[0].name
}
