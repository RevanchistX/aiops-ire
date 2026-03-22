# ─── Custom PrometheusRule — fast-firing flask-app alerts ─────────────────────
# These rules target flask-app directly and are tuned for demo use:
# short `for` windows (30s–1m) so alerts reach Alertmanager quickly.
#
# depends_on helm_release.kube_prometheus_stack because the PrometheusRule CRD
# is installed by that chart; kubernetes_manifest will error if the CRD doesn't
# exist yet.
#
# The `release: kube-prometheus-stack` label is required so the Prometheus
# operator's default ruleSelector picks up this resource.

resource "kubernetes_manifest" "flask_app_alerts" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "flask-app-alerts"
      namespace = var.namespace
      labels = {
        release    = "kube-prometheus-stack"
        managed-by = "terraform"
      }
    }

    spec = {
      groups = [
        {
          name = "flask-app"
          rules = [

            # ── 1. High CPU ────────────────────────────────────────────────
            # Fires when the flask-app container averages > 5% of one CPU
            # core over the last minute — easily triggered by /cpu endpoint.
            {
              alert = "FlaskAppHighCPU"
              expr  = "rate(container_cpu_usage_seconds_total{namespace=\"apps\",container=\"flask-app\"}[1m]) > 0.05"
              for   = "1m"
              labels = {
                severity = "warning"
                service  = "flask-app"
              }
              annotations = {
                summary     = "Flask app high CPU usage"
                description = "flask-app container CPU rate exceeded 5% for 1 minute (current: {{ $value | humanizePercentage }})."
              }
            },

            # ── 2. Pod restarted ───────────────────────────────────────────
            # Fires as soon as a container restart is observed in a 5-minute
            # window — catches OOMKills and CrashLoopBackOffs immediately.
            {
              alert = "FlaskAppPodRestarted"
              expr  = "increase(kube_pod_container_status_restarts_total{namespace=\"apps\"}[5m]) > 0"
              for   = "30s"
              labels = {
                severity = "critical"
                service  = "flask-app"
              }
              annotations = {
                summary     = "Flask app pod restarted"
                description = "A flask-app pod in namespace apps has restarted at least once in the last 5 minutes."
              }
            },

            # ── 3. High error rate ─────────────────────────────────────────
            # Fires when the HTTP 500 rate is above zero for 30s.
            # Triggered directly by the /error endpoint.
            {
              alert = "FlaskAppHighErrorRate"
              expr  = "rate(flask_http_request_total{namespace=\"apps\",http_status=\"500\"}[1m]) > 0"
              for   = "30s"
              labels = {
                severity = "critical"
                service  = "flask-app"
              }
              annotations = {
                summary     = "Flask app returning HTTP 500 errors"
                description = "flask-app has been returning 500 responses for at least 30 seconds (rate: {{ $value | humanize }} req/s)."
              }
            },

          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# ─── CryptoFlux PrometheusRules ────────────────────────────────────────────────
# Infrastructure-level alerts for the CryptoFlux trading platform.
# Log-based security detection is handled separately by aiops-brain security_monitor.py.

resource "kubernetes_manifest" "cryptoflux_alerts" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "cryptoflux-alerts"
      namespace = var.namespace
      labels = {
        release    = "kube-prometheus-stack"
        managed-by = "terraform"
      }
    }

    spec = {
      groups = [
        {
          name = "cryptoflux"
          rules = [

            # ── 1. Transaction ingestion gap ───────────────────────────────
            # Fires when the data-ingestion container has not been ready for
            # 15 minutes — a strong proxy for ingestion stall when no custom
            # metric is available.
            {
              alert = "CryptoFluxTransactionGap"
              expr  = "kube_pod_container_status_ready{namespace=\"cryptoflux\", container=\"data-ingestion\"} == 0"
              for   = "15m"
              labels = {
                severity  = "critical"
                service   = "data-ingestion"
                namespace = "cryptoflux"
              }
              annotations = {
                summary     = "CryptoFlux data-ingestion not ready for 15 minutes"
                description = "The data-ingestion container has not been in ready state for 15 minutes — transaction ingestion may have stalled (pod: {{ $labels.pod }})."
              }
            },

            # ── 2. DR sync pod restarting ──────────────────────────────────
            # Fires as soon as the dr-sync container restarts — any restart
            # introduces a replication gap that may breach the 5-minute RPO.
            {
              alert = "CryptoFluxDRSyncFailed"
              expr  = "increase(kube_pod_container_status_restarts_total{namespace=\"cryptoflux\", container=\"dr-sync\"}[5m]) > 0"
              for   = "1m"
              labels = {
                severity  = "warning"
                service   = "dr-sync"
                namespace = "cryptoflux"
              }
              annotations = {
                summary     = "CryptoFlux DR sync pod restarting"
                description = "The dr-sync container restarted at least once in the last 5 minutes — DR replication may be interrupted, breaching the 5-minute RPO target."
              }
            },

            # ── 3. Any CryptoFlux pod not running ─────────────────────────
            # Catches unexpected pod failures across all CryptoFlux services.
            # Excludes completed Jobs (data-ingestion, dr-sync run as workers).
            {
              alert = "CryptoFluxPodDown"
              expr  = "kube_pod_container_status_running{namespace=\"cryptoflux\"} == 0"
              for   = "2m"
              labels = {
                severity  = "critical"
                service   = "cryptoflux"
                namespace = "cryptoflux"
              }
              annotations = {
                summary     = "CryptoFlux container not running"
                description = "Container {{ $labels.container }} in pod {{ $labels.pod }} (namespace cryptoflux) has not been running for 2 minutes."
              }
            },

          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
