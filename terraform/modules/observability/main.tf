# ─── kube-prometheus-stack ────────────────────────────────────────────────────
# Includes Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = var.namespace

  wait    = true
  timeout = 600  # large chart with many CRDs

  # Grafana admin password passed via set_sensitive to keep it out of plan output
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  values = [
    <<-EOT
    prometheus:
      prometheusSpec:
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: local-path
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: ${var.prometheus_storage_size}
        resources:
          requests:
            cpu: "200m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "2Gi"

    alertmanager:
      config:
        global:
          resolve_timeout: 5m
        route:
          group_by: ["alertname", "job"]
          group_wait: 30s
          group_interval: 5m
          repeat_interval: 12h
          receiver: aiops-brain
          routes:
            # Silence the always-firing Watchdog heartbeat alert
            - matchers:
                - alertname = "Watchdog"
              receiver: "null"
        receivers:
          - name: "null"
          - name: aiops-brain
            webhook_configs:
              - url: "${var.alertmanager_webhook_url}"
                send_resolved: true
      alertmanagerSpec:
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"

    grafana:
      # Prometheus datasource is wired automatically by kube-prometheus-stack.
      # Add Loki as an additional datasource.
      additionalDataSources:
        - name: Loki
          type: loki
          url: http://loki.${var.namespace}.svc.cluster.local:3100
          access: proxy
          isDefault: false
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
        limits:
          cpu: "300m"
          memory: "256Mi"

    kube-state-metrics:
      resources:
        requests:
          cpu: "50m"
          memory: "64Mi"
        limits:
          cpu: "100m"
          memory: "128Mi"

    prometheus-node-exporter:
      resources:
        requests:
          cpu: "50m"
          memory: "32Mi"
        limits:
          cpu: "100m"
          memory: "64Mi"
    EOT
  ]
}

# ─── Loki ─────────────────────────────────────────────────────────────────────
# Single-binary (monolithic) mode — suitable for single-node k3s
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_version
  namespace  = var.namespace

  wait    = true
  timeout = 300

  values = [
    <<-EOT
    deploymentMode: SingleBinary

    loki:
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      schemaConfig:
        configs:
          - from: "2024-01-01"
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h
      # Disable authentication for in-cluster use
      auth_enabled: false

    singleBinary:
      replicas: 1
      persistence:
        enabled: true
        storageClass: local-path
        size: ${var.loki_storage_size}
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"

    # Disable scalable-mode components (not used in SingleBinary)
    backend:
      replicas: 0
    read:
      replicas: 0
    write:
      replicas: 0
    EOT
  ]
}

# ─── Promtail ─────────────────────────────────────────────────────────────────
# DaemonSet that scrapes all pod logs and ships them to Loki
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_version
  namespace  = var.namespace

  wait    = true
  timeout = 180

  values = [
    <<-EOT
    config:
      clients:
        - url: http://loki.${var.namespace}.svc.cluster.local:3100/loki/api/v1/push

    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
    EOT
  ]

  depends_on = [helm_release.loki]
}
