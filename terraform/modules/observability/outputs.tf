output "grafana_endpoint" {
  description = "In-cluster DNS endpoint for Grafana"
  value       = "http://kube-prometheus-stack-grafana.${helm_release.kube_prometheus_stack.namespace}.svc.cluster.local:80"
}

output "prometheus_endpoint" {
  description = "In-cluster DNS endpoint for Prometheus"
  value       = "http://kube-prometheus-stack-prometheus.${helm_release.kube_prometheus_stack.namespace}.svc.cluster.local:9090"
}

output "loki_endpoint" {
  description = "In-cluster DNS endpoint for Loki"
  value       = "http://loki.${helm_release.loki.namespace}.svc.cluster.local:3100"
}

output "alertmanager_endpoint" {
  description = "In-cluster DNS endpoint for Alertmanager"
  value       = "http://kube-prometheus-stack-alertmanager.${helm_release.kube_prometheus_stack.namespace}.svc.cluster.local:9093"
}
