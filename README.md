# aiops-ire — Self-Healing Infrastructure Platform

[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s%20v1.31-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://k3s.io)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.5-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://terraform.io)
[![Ansible](https://img.shields.io/badge/Ansible-2.x-EE0000?style=flat-square&logo=ansible&logoColor=white)](https://ansible.com)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Claude AI](https://img.shields.io/badge/Claude-claude--sonnet--4--20250514-D97706?style=flat-square&logo=anthropic&logoColor=white)](https://anthropic.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=flat-square&logo=postgresql&logoColor=white)](https://postgresql.org)
[![License](https://img.shields.io/badge/License-MIT-22C55E?style=flat-square)](LICENSE)

---

## Overview

**aiops-ire** is a production-grade, zero-touch incident response platform built on bare Ubuntu Server. When a failure occurs — whether a CPU spike, memory leak, pod crash, or elevated error rate — the system automatically detects the degradation via Prometheus, pulls the relevant logs from Loki, submits the full context to Claude AI for root-cause analysis, persists the incident to PostgreSQL, opens a structured GitHub issue containing a step-by-step remediation runbook, and attempts Kubernetes-native auto-remediation, all without human involvement. The entire pipeline from alert firing to GitHub issue creation completes in under two minutes.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         aiops-ire  —  Full Pipeline                         │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐   HTTP /cpu          ┌─────────────────────────────────┐
  │ chaos/       │   /memory /error     │  Namespace: apps                │
  │ inject.sh    │ ──────────────────▶  │  flask-app  (2 replicas)        │
  │              │   kubectl exec       │  Flask 3.1  +  prometheus-client│
  └──────────────┘   pod-kill           └────────────┬────────────────────┘
                                                     │ metrics scrape :5000
                                                     ▼
  ┌──────────────────────────────────────────────────────────────────────────┐
  │  Namespace: observability                                                │
  │                                                                          │
  │  ┌─────────────────┐   PrometheusRule    ┌──────────────────────────┐   │
  │  │   Prometheus    │ ◀───────────────── │  flask-app-alerts        │   │
  │  │   (kube-prom    │                    │  FlaskAppHighCPU    1m   │   │
  │  │    stack)       │  alert fires       │  FlaskAppPodRestarted 30s│   │
  │  └────────┬────────┘ ──────────────────▶│  FlaskAppHighErrorRate30s│   │
  │           │                             └──────────────────────────┘   │
  │           ▼ webhook POST /webhook                                        │
  │  ┌─────────────────┐   Loki LogQL      ┌─────────────────────────────┐ │
  │  │  Alertmanager   │                   │  Loki  (single-binary)      │ │
  │  └────────┬────────┘                   │  Promtail DaemonSet         │ │
  │           │                            └─────────────────────────────┘ │
  │           │ POST /webhook                           ▲                   │
  └───────────┼─────────────────────────────────────────┼───────────────────┘
              │                                         │ logs query
              ▼                                         │
  ┌───────────────────────────────────────────────────────────────────────┐
  │  Namespace: aiops                                                     │
  │                                                                       │
  │  ┌─────────────────────────────────────────────────────────────────┐ │
  │  │  aiops-brain  (FastAPI)                                         │ │
  │  │                                                                 │ │
  │  │  1. Extract alert metadata (name, severity, service)           │ │
  │  │  2. Query Loki → last 10 min of logs                           │ │
  │  │  3. Send alert + logs ──────────────────────────────────────┐  │ │
  │  │  4. Persist incident to PostgreSQL                          │  │ │
  │  │  5. Open GitHub issue with runbook                          │  │ │
  │  │  6. Attempt auto-remediation (pod restart / rollout)        │  │ │
  │  │  7. Update remediation result in PostgreSQL                 │  │ │
  │  └──────────────────────────────────────┬──────────────────────┘ │ │
  │                                         │                         │ │
  └─────────────────────────────────────────┼─────────────────────────┘
                                            │
              ┌─────────────────────────────┼──────────────────────────┐
              │                             │                          │
              ▼                             ▼                          ▼
  ┌─────────────────────┐   ┌──────────────────────────┐   ┌──────────────────┐
  │  Claude API         │   │  PostgreSQL 16            │   │  GitHub Issues   │
  │  claude-sonnet-4-   │   │  Namespace: database      │   │  auto-created    │
  │  20250514           │   │  incidents table (JSONB)  │   │  with runbook    │
  │                     │   │  Bitnami Helm chart       │   │  + severity tag  │
  │  • Root cause       │   │  Alembic migrations       │   │                  │
  │  • Severity rating  │   │                           │   │                  │
  │  • Runbook steps    │   └──────────────────────────┘   └──────────────────┘
  │  • Remediation safe │
  └─────────────────────┘
```

---

## Full Stack

| Component | Version | Purpose |
|---|---|---|
| **Ubuntu Server** | 22.04 LTS | Bare-metal host OS |
| **Ansible** | 2.x | Server provisioning: OS hardening, k3s install, Helm install |
| **k3s** | v1.31 | Lightweight single-node Kubernetes distribution |
| **Helm** | v3 | Kubernetes package manager (managed by Ansible) |
| **Terraform** | ≥ 1.5 | Declares all Kubernetes resources; single source of truth |
| **Prometheus** (kube-prometheus-stack) | chart 82.12.0 | Metrics collection, alerting rules, alert evaluation |
| **Alertmanager** | bundled | Alert routing and webhook delivery to aiops-brain |
| **Loki** | chart 6.55.0 | Log aggregation — queried by aiops-brain for context |
| **Promtail** | chart 6.17.1 | DaemonSet log shipper → Loki |
| **Grafana** | bundled | Dashboards for metrics and Loki log exploration |
| **PostgreSQL** | 16 (Bitnami chart 17.1.0) | Incident persistence with JSONB columns |
| **SQLAlchemy + Alembic** | 2.0.36 / 1.14.0 | Async ORM and schema migrations |
| **Flask** | 3.1.0 | Chaos-target microservice with intentionally broken endpoints |
| **FastAPI** | 0.115.5 | aiops-brain: async webhook receiver and incident orchestrator |
| **Anthropic Python SDK** | 0.40.0 | Claude API client for log analysis and runbook generation |
| **Claude claude-sonnet-4-20250514** | — | LLM: root-cause analysis, severity rating, remediation runbook |
| **PyGithub** | 2.5.0 | GitHub issue creation via REST API |
| **kubernetes** (Python) | 31.0.0 | In-cluster RBAC-backed auto-remediation |

---

## Project Structure

```
aiops-ire/
├── ansible/                   # Phase 1 — server provisioning
│   ├── playbooks/
│   │   ├── setup-server.yml   # k3s + Helm install
│   │   └── hardening.yml      # OS security baseline
│   └── roles/
│       ├── common/            # Base packages and sysctl
│       ├── k3s/               # k3s single-node install
│       └── helm/              # Helm CLI install
│
├── terraform/                 # Phases 2–5 — all Kubernetes resources
│   ├── main.tf                # Module wiring (no logic here)
│   ├── variables.tf           # All input variables with descriptions
│   ├── outputs.tf             # Service DNS endpoints and URLs
│   ├── providers.tf           # kubernetes, helm, github providers
│   └── modules/
│       ├── namespaces/        # Phase 2 — five namespaces
│       ├── database/          # Phase 2 — PostgreSQL via Bitnami Helm
│       ├── observability/     # Phase 3 — Prometheus, Alertmanager, Loki, Grafana
│       ├── apps/              # Phase 4 — Flask chaos-target Deployment + Service
│       └── aiops/             # Phase 5 — aiops-brain: RBAC, Secret, Deployment
│
├── src/
│   ├── aiops-brain/           # Phase 5 — FastAPI incident response service
│   │   ├── main.py            # /webhook, /health, /incidents endpoints
│   │   ├── analyzer.py        # Claude API integration
│   │   ├── loki_client.py     # Loki HTTP query client
│   │   ├── github_client.py   # GitHub issue creation
│   │   ├── remediation.py     # kubectl pod restart / rollout restart
│   │   ├── models.py          # SQLAlchemy Incident model
│   │   ├── database.py        # Async engine and session factory
│   │   ├── migrations/        # Alembic revisions
│   │   ├── Dockerfile
│   │   └── build-and-load.sh  # Build + import into k3s containerd
│   │
│   └── flask-apps/            # Phase 4 — chaos target microservice
│       ├── app.py             # /health /cpu /memory /error /slow /metrics
│       ├── Dockerfile
│       └── build-and-load.sh
│
├── chaos/                     # Phase 6 — chaos injection scripts
│   ├── inject.sh              # Interactive menu
│   ├── cpu_spike.sh           # Hit /cpu endpoint for 60s
│   ├── memory_leak.sh         # Hit /memory endpoint in a loop
│   ├── disk_fill.sh           # Write 200 MB into pod /tmp
│   ├── network_drop.sh        # tc netem 500ms delay on eth0
│   └── pod_kill.sh            # Force-delete a pod
│
└── kubernetes/                # Raw manifests (referenced by Terraform)
    ├── namespaces/
    ├── database/
    ├── observability/
    ├── apps/
    ├── aiops/
    └── chaos/
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Ubuntu Server 22.04 | Bare-metal or VM with ≥ 4 vCPU, ≥ 8 GB RAM, ≥ 40 GB disk |
| Ansible ≥ 2.12 | Installed on your local machine |
| Terraform ≥ 1.5 | Installed on your local machine |
| Docker Engine | Required on the server to build images |
| Anthropic API key | `claude-sonnet-4-20250514` access required |
| GitHub PAT | `repo` scope — for opening issues |
| SSH access to server | Passwordless key recommended |

---

## Quick Start

### Phase 1 — Provision the server with Ansible

```bash
# Verify SSH connectivity
ansible -i ansible/inventory.ini all -m ping

# Install k3s, Helm, and apply OS hardening
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-server.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/hardening.yml
```

### Phase 2–3 — Bootstrap infrastructure with Terraform

```bash
cd terraform

# Copy and populate the variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set db_password, grafana_admin_password, etc.

terraform init

# Namespaces and PostgreSQL
terraform apply -target=module.namespaces -target=module.database -var-file=terraform.tfvars

# Observability stack (Prometheus, Alertmanager, Loki, Grafana)
terraform apply -target=module.observability -var-file=terraform.tfvars
```

### Phase 4 — Deploy the Flask chaos-target apps

```bash
# Build the image on the server and load it into k3s containerd
cd src/flask-apps
bash build-and-load.sh

# Deploy via Terraform
cd ../../terraform
terraform apply -target=module.apps -var-file=terraform.tfvars
```

### Phase 5 — Deploy aiops-brain

```bash
# Build and load the aiops-brain image
cd src/aiops-brain
bash build-and-load.sh

# Deploy the full aiops module (RBAC, Secret, Deployment, Service)
cd ../../terraform
terraform apply -target=module.aiops -var-file=terraform.tfvars

# Verify the pod is running and healthy
kubectl get pods -n aiops
kubectl logs -n aiops -l app=aiops-brain -f
```

### Phase 6 — Inject chaos and observe the pipeline

```bash
# Interactive menu — pick a scenario and watch the pipeline fire
bash chaos/inject.sh

# Or run a specific scenario directly
bash chaos/pod_kill.sh
bash chaos/cpu_spike.sh
```

**Watch for auto-generated incidents at:**
```
https://github.com/DeniStojanovski/aiops-ire/issues
```

---

## How It Works

The pipeline executes the following steps for every alert Alertmanager receives:

**1. Chaos injection** — A script (`chaos/inject.sh`) exercises one of the Flask app's intentionally broken endpoints or kills a pod outright. The app's `prometheus-client` counters and Kubernetes container metrics immediately reflect the degradation.

**2. Prometheus detection** — Custom `PrometheusRule` resources define fast-firing alert expressions (30s–1m windows) scoped to the `apps` namespace. When an expression is satisfied for its `for` duration, Prometheus transitions the alert to `FIRING`.

**3. Alertmanager routing** — Alertmanager receives the firing alert and routes it to the `aiops-brain` webhook receiver (`POST http://aiops-brain.aiops.svc.cluster.local:8000/webhook`). Routing is configured in the kube-prometheus-stack Helm values.

**4. Webhook received** — FastAPI's `/webhook` endpoint deserialises the Alertmanager payload, extracts `alertname`, `severity`, `service`, and `namespace` from the alert labels, then hands off to a background task so the HTTP response returns immediately.

**5. Log collection** — `loki_client.py` queries Loki's `query_range` API for the last 10 minutes of logs from the affected service. It falls back to a namespace-wide query if the service-specific stream returns no results.

**6. Claude API analysis** — `analyzer.py` constructs a structured prompt containing the alert metadata, label set, and full log snapshot, then calls `claude-sonnet-4-20250514`. Claude returns a response in four sections: **Root Cause**, **Severity Assessment**, **Remediation Runbook**, and **Auto-Remediation Safe** (yes/no).

**7. Incident persistence** — The full incident record — raw alert payload (JSONB), log snapshot, Claude's complete response, parsed root cause, and runbook — is written to the `incidents` table in PostgreSQL via an async SQLAlchemy session.

**8. GitHub issue creation** — `github_client.py` opens an issue in the configured repository with a formatted Markdown body: incident summary table, root cause, severity assessment, numbered runbook, and a collapsible log excerpt. Severity labels are applied automatically.

**9. Auto-remediation** — `remediation.py` maps the alert name to a remediation strategy using the aiops-brain's Kubernetes ServiceAccount (ClusterRole: `get/list/delete` pods, `get/list/patch` deployments). CrashLoop/OOMKill alerts trigger a pod deletion; high-memory/high-CPU alerts trigger a rolling restart via annotation patch. Claude's `auto_remediation_safe` flag gates execution.

**10. Result update** — The `remediation_action` and `remediation_result` columns in PostgreSQL are updated with the outcome. The incident record is now complete and queryable via `GET /incidents`.

---

## Kubernetes Namespaces

| Namespace | Contents | Purpose |
|---|---|---|
| `observability` | Prometheus, Alertmanager, Grafana, Loki, Promtail | Full observability stack |
| `database` | PostgreSQL 16 (Bitnami) | Persistent incident storage |
| `apps` | flask-app Deployment (2 replicas) | Chaos injection target |
| `aiops` | aiops-brain Deployment, RBAC, Secrets | Incident response orchestrator |
| `chaos` | (reserved) | Chaos tooling and test workloads |

---

## Environment Variables

All variables are injected into the `aiops-brain` pod via a Kubernetes Secret managed by Terraform. They are never hardcoded or stored in ConfigMaps.

| Variable | Used By | Description |
|---|---|---|
| `CLAUDE_API_KEY` | aiops-brain | Anthropic API key for Claude API access |
| `GITHUB_TOKEN` | aiops-brain | GitHub PAT with `repo` scope for issue creation |
| `GITHUB_REPO` | aiops-brain | Repository in `owner/repo` format |
| `DATABASE_URL` | aiops-brain | `postgresql://user:pass@host:5432/aiops` |
| `LOKI_URL` | aiops-brain | `http://loki.observability.svc.cluster.local:3100` |

For local development, export variables from a `.env` file (never committed):

```bash
export $(grep -v '^#' .env | xargs)
cd src/aiops-brain && uvicorn main:app --reload --port 8080
```

---

## Demo

When a pod-kill chaos event fires, the full pipeline produces a GitHub issue like the following within approximately 90 seconds:

```
[CRITICAL] FlaskAppPodRestarted — flask-app
```

**Issue body:**

```markdown
## Incident Summary

| Field      | Value                             |
|------------|-----------------------------------|
| Alert      | `FlaskAppPodRestarted`            |
| Service    | `flask-app`                       |
| Severity   | critical                          |
| Fired At   | 2026-03-21 14:32:07 UTC           |

## Root Cause

The flask-app container in the apps namespace was force-terminated, triggering
an immediate restart by the Deployment controller. The restart count increment
was detected within the 5-minute observation window by the
kube_pod_container_status_restarts_total metric.

## Severity Assessment

**Critical** — A pod restart causes a brief period of unavailability. With only
2 replicas, each restart temporarily reduces capacity by 50%.

## Remediation Runbook

1. Confirm the replacement pod has reached Running/Ready state:
   `kubectl get pods -n apps -l app=flask-app`
2. Review container logs for the root cause of the original termination:
   `kubectl logs -n apps <pod-name> --previous`
3. If OOMKilled, increase the memory limit in the Terraform module and re-apply.
4. If CrashLoopBackOff persists, inspect the application error logs and redeploy.
5. Verify readiness probe is passing before routing traffic.
```

**Auto-remediation result:** `Deleted pod flask-app-7d9f8b-xk2pq; Deployment controller will reschedule`

The `GET /incidents` endpoint returns the full structured record:

```json
{
  "id": "a3f2c1d4-8e7b-4a9f-b2c3-1d4e5f6a7b8c",
  "alert_name": "FlaskAppPodRestarted",
  "severity": "critical",
  "service": "flask-app",
  "fired_at": "2026-03-21T14:32:07",
  "root_cause": "The flask-app container was force-terminated...",
  "runbook": "1. Confirm the replacement pod...",
  "github_issue_url": "https://github.com/DeniStojanovski/aiops-ire/issues/1",
  "remediation_action": "pod_restart(app=flask-app, namespace=apps)",
  "remediation_result": "Deleted pod flask-app-7d9f8b-xk2pq; Deployment controller will reschedule",
  "created_at": "2026-03-21T14:32:51"
}
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.
