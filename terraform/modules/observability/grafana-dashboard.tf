# ─── Grafana Dashboard: AIOps Incident Response ───────────────────────────────
# Injected via ConfigMap. The Grafana sidecar container watches for ConfigMaps
# labelled grafana_dashboard=1 (in all namespaces) and loads them automatically.
#
# Datasource UIDs used:
#   "postgresql" → Grafana PostgreSQL datasource (incidents table)
#   "prometheus"  → Prometheus datasource (kube-prometheus-stack built-in)
#
# Panel layout (24-column Grafana grid):
#   Row y=0  h=4  : [Total Incidents 8w] [Remediation Rate 8w] [Pod Restarts 8w]
#   Row y=4  h=8  : [Incidents by Severity pie 8w] [Incidents over Time ts 16w]
#   Row y=12 h=8  : [Flask CPU ts 12w] [Flask Memory ts 12w]
#   Row y=20 h=10 : [Latest 10 Incidents table 24w]

resource "kubernetes_config_map" "grafana_dashboard_aiops" {
  metadata {
    name      = "grafana-dashboard-aiops"
    namespace = var.namespace
    labels = {
      grafana_dashboard = "1"    # sidecar discovery label
      managed-by        = "terraform"
    }
  }

  data = {
    "aiops-incident-response.json" = <<-JSON
      {
        "title": "AIOps Incident Response",
        "uid": "aiops-incident-response",
        "description": "Real-time incident history from PostgreSQL and infrastructure health from Prometheus — powered by Claude AI.",
        "schemaVersion": 38,
        "version": 1,
        "refresh": "30s",
        "timezone": "browser",
        "time": { "from": "now-24h", "to": "now" },
        "timepicker": {},
        "tags": ["aiops", "incidents", "self-healing"],
        "editable": true,
        "graphTooltip": 1,
        "links": [],
        "annotations": {
          "list": [
            {
              "builtIn": 1,
              "datasource": { "type": "grafana", "uid": "-- Grafana --" },
              "enable": true,
              "hide": true,
              "iconColor": "rgba(0, 211, 255, 1)",
              "name": "Annotations & Alerts",
              "type": "dashboard"
            }
          ]
        },
        "panels": [

          {
            "id": 1,
            "type": "stat",
            "title": "Total Incidents",
            "gridPos": { "x": 0, "y": 0, "w": 8, "h": 4 },
            "datasource": { "type": "postgres", "uid": "postgresql" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "postgres", "uid": "postgresql" },
                "editorMode": "code",
                "format": "table",
                "rawQuery": true,
                "rawSql": "SELECT COUNT(*) AS \"value\" FROM incidents",
                "sql": { "columns": [], "groupBy": [], "limit": 50 }
              }
            ],
            "options": {
              "colorMode": "background",
              "graphMode": "none",
              "justifyMode": "center",
              "orientation": "auto",
              "textMode": "auto",
              "wideLayout": true,
              "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "thresholds" },
                "mappings": [],
                "thresholds": {
                  "mode": "absolute",
                  "steps": [
                    { "color": "blue",   "value": null },
                    { "color": "yellow", "value": 5   },
                    { "color": "red",    "value": 20  }
                  ]
                },
                "unit": "short"
              },
              "overrides": []
            }
          },

          {
            "id": 2,
            "type": "stat",
            "title": "Auto-Remediation Success Rate",
            "gridPos": { "x": 8, "y": 0, "w": 8, "h": 4 },
            "datasource": { "type": "postgres", "uid": "postgresql" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "postgres", "uid": "postgresql" },
                "editorMode": "code",
                "format": "table",
                "rawQuery": true,
                "rawSql": "SELECT COALESCE(ROUND(100.0 * SUM(CASE WHEN remediation_action NOT IN ('skipped', 'none') THEN 1 ELSE 0 END)::numeric / NULLIF(COUNT(*), 0), 1), 0) AS \"value\" FROM incidents",
                "sql": { "columns": [], "groupBy": [], "limit": 50 }
              }
            ],
            "options": {
              "colorMode": "background",
              "graphMode": "none",
              "justifyMode": "center",
              "orientation": "auto",
              "textMode": "auto",
              "wideLayout": true,
              "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "thresholds" },
                "mappings": [],
                "thresholds": {
                  "mode": "absolute",
                  "steps": [
                    { "color": "red",    "value": null },
                    { "color": "yellow", "value": 50  },
                    { "color": "green",  "value": 80  }
                  ]
                },
                "unit": "percent",
                "min": 0,
                "max": 100
              },
              "overrides": []
            }
          },

          {
            "id": 3,
            "type": "stat",
            "title": "Pod Restarts (last 1h)",
            "gridPos": { "x": 16, "y": 0, "w": 8, "h": 4 },
            "datasource": { "type": "prometheus", "uid": "prometheus" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "prometheus", "uid": "prometheus" },
                "editorMode": "code",
                "expr": "sum(increase(kube_pod_container_status_restarts_total{namespace=\"apps\"}[1h])) or vector(0)",
                "legendFormat": "Restarts",
                "range": false,
                "instant": true
              }
            ],
            "options": {
              "colorMode": "background",
              "graphMode": "none",
              "justifyMode": "center",
              "orientation": "auto",
              "textMode": "auto",
              "wideLayout": true,
              "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false }
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "thresholds" },
                "mappings": [],
                "thresholds": {
                  "mode": "absolute",
                  "steps": [
                    { "color": "green",  "value": null },
                    { "color": "yellow", "value": 1   },
                    { "color": "red",    "value": 3   }
                  ]
                },
                "unit": "short"
              },
              "overrides": []
            }
          },

          {
            "id": 4,
            "type": "piechart",
            "title": "Incidents by Severity",
            "gridPos": { "x": 0, "y": 4, "w": 8, "h": 8 },
            "datasource": { "type": "postgres", "uid": "postgresql" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "postgres", "uid": "postgresql" },
                "editorMode": "code",
                "format": "table",
                "rawQuery": true,
                "rawSql": "SELECT severity AS \"Severity\", COUNT(*) AS \"Count\" FROM incidents GROUP BY severity ORDER BY severity",
                "sql": { "columns": [], "groupBy": [], "limit": 50 }
              }
            ],
            "options": {
              "pieType": "pie",
              "displayLabels": ["name", "percent"],
              "legend": { "displayMode": "list", "placement": "right", "showLegend": true },
              "tooltip": { "mode": "single", "sort": "none" }
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "palette-classic" },
                "mappings": []
              },
              "overrides": [
                {
                  "matcher": { "id": "byName", "options": "critical" },
                  "properties": [{ "id": "color", "value": { "mode": "fixed", "fixedColor": "red" } }]
                },
                {
                  "matcher": { "id": "byName", "options": "warning" },
                  "properties": [{ "id": "color", "value": { "mode": "fixed", "fixedColor": "orange" } }]
                },
                {
                  "matcher": { "id": "byName", "options": "info" },
                  "properties": [{ "id": "color", "value": { "mode": "fixed", "fixedColor": "blue" } }]
                }
              ]
            }
          },

          {
            "id": 5,
            "type": "timeseries",
            "title": "Incidents over Time",
            "gridPos": { "x": 8, "y": 4, "w": 16, "h": 8 },
            "datasource": { "type": "postgres", "uid": "postgresql" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "postgres", "uid": "postgresql" },
                "editorMode": "code",
                "format": "time_series",
                "rawQuery": true,
                "rawSql": "SELECT $__timeGroupAlias(fired_at,'1h'), COUNT(*) AS \"Incidents\" FROM incidents WHERE $__timeFilter(fired_at) GROUP BY 1 ORDER BY 1",
                "sql": { "columns": [], "groupBy": [], "limit": 50 }
              }
            ],
            "options": {
              "tooltip": { "mode": "multi", "sort": "none" },
              "legend": { "displayMode": "list", "placement": "bottom", "showLegend": true }
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "palette-classic" },
                "custom": {
                  "axisBorderShow": false,
                  "axisCenteredZero": false,
                  "axisColorMode": "text",
                  "axisPlacement": "auto",
                  "barAlignment": 0,
                  "drawStyle": "bars",
                  "fillOpacity": 60,
                  "gradientMode": "none",
                  "hideFrom": { "legend": false, "tooltip": false, "viz": false },
                  "insertNulls": false,
                  "lineInterpolation": "linear",
                  "lineWidth": 1,
                  "pointSize": 5,
                  "scaleDistribution": { "type": "linear" },
                  "showPoints": "never",
                  "spanNulls": false,
                  "stacking": { "group": "A", "mode": "none" },
                  "thresholdsStyle": { "mode": "off" }
                },
                "mappings": [],
                "thresholds": {
                  "mode": "absolute",
                  "steps": [
                    { "color": "green", "value": null },
                    { "color": "red",   "value": 10  }
                  ]
                },
                "unit": "short"
              },
              "overrides": []
            }
          },

          {
            "id": 6,
            "type": "timeseries",
            "title": "Flask App CPU Usage",
            "gridPos": { "x": 0, "y": 12, "w": 12, "h": 8 },
            "datasource": { "type": "prometheus", "uid": "prometheus" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "prometheus", "uid": "prometheus" },
                "editorMode": "code",
                "expr": "rate(container_cpu_usage_seconds_total{namespace=\"apps\",container=\"flask-app\"}[5m])",
                "legendFormat": "{{pod}}",
                "range": true
              }
            ],
            "options": {
              "tooltip": { "mode": "multi", "sort": "none" },
              "legend": { "displayMode": "list", "placement": "bottom", "showLegend": true }
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "palette-classic" },
                "custom": {
                  "axisBorderShow": false,
                  "axisCenteredZero": false,
                  "axisColorMode": "text",
                  "axisLabel": "CPU cores",
                  "axisPlacement": "auto",
                  "barAlignment": 0,
                  "drawStyle": "line",
                  "fillOpacity": 10,
                  "gradientMode": "none",
                  "hideFrom": { "legend": false, "tooltip": false, "viz": false },
                  "insertNulls": false,
                  "lineInterpolation": "linear",
                  "lineWidth": 2,
                  "pointSize": 5,
                  "scaleDistribution": { "type": "linear" },
                  "showPoints": "never",
                  "spanNulls": false,
                  "stacking": { "group": "A", "mode": "none" },
                  "thresholdsStyle": { "mode": "line" }
                },
                "mappings": [],
                "thresholds": {
                  "mode": "absolute",
                  "steps": [
                    { "color": "green", "value": null },
                    { "color": "red",   "value": 0.05 }
                  ]
                },
                "unit": "short",
                "min": 0
              },
              "overrides": []
            }
          },

          {
            "id": 7,
            "type": "timeseries",
            "title": "Flask App Memory Usage",
            "gridPos": { "x": 12, "y": 12, "w": 12, "h": 8 },
            "datasource": { "type": "prometheus", "uid": "prometheus" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "prometheus", "uid": "prometheus" },
                "editorMode": "code",
                "expr": "container_memory_working_set_bytes{namespace=\"apps\",container=\"flask-app\"}",
                "legendFormat": "{{pod}}",
                "range": true
              }
            ],
            "options": {
              "tooltip": { "mode": "multi", "sort": "none" },
              "legend": { "displayMode": "list", "placement": "bottom", "showLegend": true }
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "palette-classic" },
                "custom": {
                  "axisBorderShow": false,
                  "axisCenteredZero": false,
                  "axisColorMode": "text",
                  "axisPlacement": "auto",
                  "barAlignment": 0,
                  "drawStyle": "line",
                  "fillOpacity": 10,
                  "gradientMode": "none",
                  "hideFrom": { "legend": false, "tooltip": false, "viz": false },
                  "insertNulls": false,
                  "lineInterpolation": "linear",
                  "lineWidth": 2,
                  "pointSize": 5,
                  "scaleDistribution": { "type": "linear" },
                  "showPoints": "never",
                  "spanNulls": false,
                  "stacking": { "group": "A", "mode": "none" },
                  "thresholdsStyle": { "mode": "line" }
                },
                "mappings": [],
                "thresholds": {
                  "mode": "absolute",
                  "steps": [
                    { "color": "green",  "value": null      },
                    { "color": "yellow", "value": 134217728 },
                    { "color": "red",    "value": 241172480 }
                  ]
                },
                "unit": "bytes",
                "min": 0
              },
              "overrides": []
            }
          },

          {
            "id": 8,
            "type": "table",
            "title": "Latest 10 Incidents",
            "gridPos": { "x": 0, "y": 20, "w": 24, "h": 10 },
            "datasource": { "type": "postgres", "uid": "postgresql" },
            "targets": [
              {
                "refId": "A",
                "datasource": { "type": "postgres", "uid": "postgresql" },
                "editorMode": "code",
                "format": "table",
                "rawQuery": true,
                "rawSql": "SELECT alert_name AS \"Alert\", severity AS \"Severity\", service AS \"Service\", fired_at AS \"Fired At\", LEFT(root_cause, 120) AS \"Root Cause\", github_issue_url AS \"GitHub Issue\" FROM incidents ORDER BY fired_at DESC LIMIT 10",
                "sql": { "columns": [], "groupBy": [], "limit": 50 }
              }
            ],
            "options": {
              "showHeader": true,
              "cellOptions": { "type": "auto" },
              "footer": { "countRows": false, "fields": "", "reducer": ["sum"], "show": false },
              "frameIndex": 0,
              "sortBy": [{ "desc": true, "displayName": "Fired At" }]
            },
            "fieldConfig": {
              "defaults": {
                "color": { "mode": "thresholds" },
                "custom": {
                  "align": "auto",
                  "cellOptions": { "type": "auto" },
                  "filterable": true,
                  "inspect": false
                },
                "mappings": [],
                "thresholds": {
                  "mode": "absolute",
                  "steps": [{ "color": "green", "value": null }]
                }
              },
              "overrides": [
                {
                  "matcher": { "id": "byName", "options": "Severity" },
                  "properties": [
                    { "id": "custom.cellOptions", "value": { "type": "color-background", "mode": "basic" } },
                    {
                      "id": "mappings",
                      "value": [
                        { "type": "value", "options": { "critical": { "color": "red",    "index": 0, "text": "critical" } } },
                        { "type": "value", "options": { "warning":  { "color": "orange", "index": 1, "text": "warning"  } } },
                        { "type": "value", "options": { "info":     { "color": "blue",   "index": 2, "text": "info"     } } }
                      ]
                    }
                  ]
                },
                {
                  "matcher": { "id": "byName", "options": "GitHub Issue" },
                  "properties": [
                    { "id": "custom.cellOptions", "value": { "type": "auto" } },
                    { "id": "links", "value": [{ "targetBlank": true, "title": "Open Issue", "url": "$${__value.text}" }] }
                  ]
                },
                {
                  "matcher": { "id": "byName", "options": "Root Cause" },
                  "properties": [{ "id": "custom.width", "value": 420 }]
                },
                {
                  "matcher": { "id": "byName", "options": "Fired At" },
                  "properties": [{ "id": "unit", "value": "dateTimeAsIso" }]
                }
              ]
            }
          }

        ]
      }
    JSON
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
