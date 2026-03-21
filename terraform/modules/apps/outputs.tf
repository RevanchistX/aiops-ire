output "service_name" {
  description = "Kubernetes Service name for the flask-app"
  value       = kubernetes_service.flask_app.metadata[0].name
}

output "service_cluster_ip" {
  description = "ClusterIP assigned to the flask-app Service"
  value       = kubernetes_service.flask_app.spec[0].cluster_ip
}

output "service_dns" {
  description = "In-cluster DNS name for the flask-app Service"
  value       = "${kubernetes_service.flask_app.metadata[0].name}.${var.namespace}.svc.cluster.local"
}
