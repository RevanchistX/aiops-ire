# aiops-ire — Self-Healing Infrastructure Platform

[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s%20v1.31-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://k3s.io)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.5-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://terraform.io)
[![Ansible](https://img.shields.io/badge/Ansible-2.x-EE0000?style=flat-square&logo=ansible&logoColor=white)](https://ansible.com)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Claude AI](https://img.shields.io/badge/Claude-claude--sonnet--4--20250514-D97706?style=flat-square&logo=anthropic&logoColor=white)](https://anthropic.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=flat-square&logo=postgresql&logoColor=white)](https://postgresql.org)
[![Slack](https://img.shields.io/badge/Slack-Block%20Kit-4A154B?style=flat-square&logo=slack&logoColor=white)](https://api.slack.com/block-kit)
[![License](https://img.shields.io/badge/License-MIT-22C55E?style=flat-square)](LICENSE)

---

## Overview

**aiops-ire** is a production-grade, zero-touch incident response platform built on bare Ubuntu Server. When a failure occurs — whether a CPU spike, memory leak, pod crash, or elevated error rate — the system automatically detects the degradation via Prometheus, pulls the relevant logs from Loki, submits the full context to Claude AI for root-cause analysis, persists the incident to PostgreSQL, opens a structured GitHub issue containing a step-by-step remediation runbook, delivers a formatted Slack notification, and attempts Kubernetes-native auto-remediation, all without human involvement. The entire pipeline from alert firing to GitHub issue and Slack message completes in under two minutes.

Phase 8 extends the platform with **CryptoFlux** — an intentionally vulnerable eight-service trading platform — and a **security monitoring pipeline** that scans Loki logs every five minutes and auto-detects SQL injection, XSS, info-leak endpoint access, hardcoded secrets, transaction ingestion gaps, and DR sync failures, routing each finding through the same GitHub + Slack pipeline.

---

> **Current Phase:** Phase 8C Complete — Attack Console + Security Monitoring

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         aiops-ire  —  Full Pipeline                         │
└─────────────────────────────────────────────────────────────────────────────┘

 CHAOS PIPELINE                          SECURITY PIPELINE
 ─────────────────────────────────────   ────────────────────────────────────
  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐
  │ chaos/       │  │ Namespace: apps  │  │ Namespace: cryptoflux        │
  │ inject.sh    │─▶│ flask-app        │  │ trading-ui    :30500 (ext)   │
  │ cpu/mem/disk │  │ (2 replicas)     │  │ trading-data  :7100          │
  │ net/pod-kill │  │ Flask 3.1        │  │ ext-api       :8000          │
  └──────────────┘  │ prom-client      │  │ liquidity-calc :8001         │
                    └────────┬─────────┘  │ data-ingestion (worker)      │
                             │ metrics    │ dr-sync        (worker)      │
                             ▼            │ postgresql-primary  :5432    │
  ┌──────────────────────────────────────┐│ postgresql-dr       :5432    │
  │  Namespace: observability            ││ (DR replica — RPO < 5 min)  │
  │                                      ││ attack-console :30600 (ext)  │
  │  Prometheus ──  PrometheusRules      ││ CronJob: security-scan ────┐ │
  │   flask-app-alerts   (3 rules)       ││ POST /security-scan        │ │
  │   cryptoflux-alerts  (3 rules)       ││ every 5 minutes            │ │
  │                                      │└────────────────────────────┼─┘
  │  Alertmanager                        │                             │
  │  Loki + Promtail DaemonSet           │                             │
  └──────┬───────────────────┬───────────┘                             │
         │ POST /webhook     │ logs query  ◀───────────────────────────┘
         ▼                   ▼              POST /security-scan
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Namespace: aiops                                                    │
  │  ┌────────────────────────────────────────────────────────────────┐ │
  │  │  aiops-brain  (FastAPI)                                        │ │
  │  │                                                                │ │
  │  │  POST /webhook pipeline:          POST /security-scan:         │ │
  │  │  1. extract alert metadata        security_monitor.py          │ │
  │  │  2. Loki → last 10 min logs       Loki → last 15 min logs      │ │
  │  │  3. Claude → root cause+runbook   SQLi · XSS · InfoLeak        │ │
  │  │  4. persist → PostgreSQL          HardcodedSecret · TxGap · DR │ │
  │  │  5. open GitHub issue             persist + GitHub + Slack      │ │
  │  │  6. Slack Block Kit notify        (no Claude, human review)    │ │
  │  │  7. auto-remediation                                           │ │
  │  │  8. update PostgreSQL result                                   │ │
  │  └───────────────────────────────┬────────────────────────────────┘ │
  └──────────────────────────────────┼───────────────────────────────────┘
                    ┌────────────────┼──────────────────┐
                    │                │                  │
                    ▼                ▼                  ▼
           ┌─────────────┐  ┌──────────────────┐  ┌──────────────┐
           │  Claude API │  │  PostgreSQL 16   │  │    GitHub    │
           │  sonnet-4   │  │  incidents table │  │    Issues    │
           │  • root cause│  │  Alembic migrate│  │  + runbooks  │
           │  • runbook  │  │  Bitnami chart  │  │  + labels    │
           │  • safe?    │  └──────────────────┘  └──────────────┘
           └─────────────┘
           ┌──────────┐  ┌──────────────────────────────────────────────┐
           │  Slack   │  │  Grafana — "AIOps Incident Response"         │
           │  Block   │  │  Incident history (PostgreSQL)               │
           │  Kit     │  │  Flask CPU / Memory (Prometheus)             │
           └──────────┘  └──────────────────────────────────────────────┘
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
| **Grafana** | bundled | "AIOps Incident Response" dashboard: PostgreSQL + Prometheus panels |
| **PostgreSQL** | 16 (Bitnami chart 17.1.0) | Incident persistence with JSONB columns |
| **SQLAlchemy** | 2.0.36 | Async ORM for incident reads and writes |
| **Alembic** | 1.14.0 | Schema migrations — run automatically via Kubernetes Job on every deploy |
| **Flask** | 3.1.0 | Chaos-target microservice with intentionally broken endpoints |
| **FastAPI** | 0.115.5 | aiops-brain: async webhook receiver and incident orchestrator |
| **Anthropic Python SDK** | 0.40.0 | Claude API client for log analysis and runbook generation |
| **Claude claude-sonnet-4-20250514** | — | LLM: root-cause analysis, severity rating, remediation runbook |
| **PyGithub** | 2.5.0 | GitHub issue creation via REST API |
| **slack-sdk** | 3.34.0 | Slack Block Kit incident notifications via incoming webhook |
| **kubernetes** (Python) | 31.0.0 | In-cluster RBAC-backed auto-remediation |
| **CryptoFlux** (Flask, Python) | — | Intentionally vulnerable 8-service trading platform (Phase 8) |
| **Attack Console** (Flask, Python) | — | DVWA-style vulnerability lab at port 30600 — SQLi, XSS, broken auth, info leak, command injection |
| **security_monitor.py** | — | Log-based attack detection: SQLi, XSS, InfoLeak, secrets, gaps, command injection, broken auth |
| **Kubernetes CronJob** | — | Triggers `POST /security-scan` every 5 minutes |

---

## Build Phases

| Phase | What is built |
|---|---|
| **Phase 1** | Ansible — k3s + Helm install, OS hardening |
| **Phase 2** | Terraform — Kubernetes namespaces + PostgreSQL (Bitnami Helm) |
| **Phase 3** | Terraform — Prometheus, Alertmanager, Loki, Promtail, Grafana |
| **Phase 4** | Terraform + Docker — Flask chaos-target Deployment (2 replicas) |
| **Phase 5** | Terraform + Docker — aiops-brain: RBAC, Alembic migration Job, Deployment |
| **Phase 6** | Chaos scripts — end-to-end pipeline validation |
| **Phase 7A** | README and architecture diagram |
| **Phase 7B** | Grafana dashboard — 8-panel "AIOps Incident Response" (PostgreSQL + Prometheus) |
| **Phase 7C** | Slack notifications — Block Kit messages with severity emoji, root cause, and GitHub issue button |
| **Phase 7D** | Alembic migration Kubernetes Job — runs `alembic upgrade head` automatically before every deploy |
| **Phase 8A** ✓ | CryptoFlux deployed to k3s — 8 services in `cryptoflux` namespace, NodePort 30500, DR replica |
| **Phase 8B** ✓ | Security monitoring — SQLi, XSS, InfoLeak, hardcoded secret, transaction gap, DR sync detection |
| **Phase 8C** ✓ | Attack Console (DVWA-style) + deduplication + DR sync fixed |

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
├── terraform/                 # Phases 2–8 — all Kubernetes resources
│   ├── main.tf                # Module wiring (no logic here)
│   ├── variables.tf           # All input variables with descriptions
│   └── modules/
│       ├── namespaces/        # Six namespaces including cryptoflux
│       ├── database/          # Phase 2 — PostgreSQL via Bitnami Helm
│       ├── observability/     # Phase 3 — Prometheus, Alertmanager, Loki, Grafana
│       │   ├── alerts.tf      #   flask-app-alerts + cryptoflux-alerts PrometheusRules
│       │   └── grafana-dashboard.tf
│       ├── apps/              # Phase 4 — Flask chaos-target
│       ├── aiops/             # Phase 5 — aiops-brain RBAC, Secret, Deployment
│       └── cryptoflux/        # Phase 8 — CryptoFlux 8 services + CronJob
│
├── src/
│   ├── aiops-brain/           # Phase 5 + 8B — FastAPI incident response service
│   │   ├── main.py            # /webhook /health /incidents /security-scan /security-events
│   │   ├── analyzer.py        # Claude API integration
│   │   ├── loki_client.py     # Loki HTTP query client
│   │   ├── security_monitor.py# Phase 8B — log-based attack detection (6 patterns)
│   │   ├── github_client.py   # GitHub issue creation
│   │   ├── slack_client.py    # Slack Block Kit notifications
│   │   ├── remediation.py     # Pod restart / rollout restart via k8s Python client
│   │   ├── models.py          # SQLAlchemy Incident model
│   │   ├── database.py        # Async engine and session factory
│   │   └── migrations/        # Alembic revisions
│   │
│   ├── flask-apps/            # Phase 4 — chaos target microservice
│   │   └── app.py             # /health /cpu /memory /error /slow /metrics
│   │
│   └── cryptoflux/            # Phase 8A — CryptoFlux image builder
│       └── build-and-load-all.sh  # Builds all 6 custom images → k3s
│
└── chaos/                     # Phase 6 — chaos injection scripts
    ├── inject.sh              # Interactive menu
    ├── cpu_spike.sh
    ├── memory_leak.sh
    ├── disk_fill.sh
    ├── network_drop.sh
    └── pod_kill.sh
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
| Slack incoming webhook | Optional — create at api.slack.com/apps; omit to disable notifications |
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
# Edit terraform.tfvars — set all required values:
#   db_password, grafana_admin_password, claude_api_key,
#   github_token, github_repo
#   slack_webhook_url  (optional — leave as "" to disable Slack)

terraform init

# Namespaces and PostgreSQL
terraform apply -target=module.namespaces -target=module.database -var-file=terraform.tfvars

# Observability stack (Prometheus, Alertmanager, Loki, Grafana + dashboard)
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

# Deploy the full aiops module:
#   1. Kubernetes Secret (all env vars)
#   2. Alembic migration Job (runs alembic upgrade head, blocks until complete)
#   3. aiops-brain Deployment + Service + RBAC
cd ../../terraform
terraform apply -target=module.aiops -var-file=terraform.tfvars

# Verify the migration Job succeeded and the pod is healthy
kubectl get jobs -n aiops
kubectl get pods -n aiops
kubectl logs -n aiops -l app=aiops-brain -f
```

### Phase 6 — Inject chaos and observe the full pipeline

```bash
# Interactive menu — pick a scenario and watch the pipeline fire end-to-end
bash chaos/inject.sh

# Or run a specific scenario directly
bash chaos/pod_kill.sh
bash chaos/cpu_spike.sh
```

After injecting chaos, verify all pipeline outputs:

```bash
# 1. Check Alertmanager fired the alert
kubectl port-forward -n observability svc/kube-prometheus-stack-alertmanager 9093:9093
# open http://localhost:9093

# 2. Tail aiops-brain logs to watch the pipeline
kubectl logs -n aiops -l app=aiops-brain -f

# 3. Query the incidents API
kubectl port-forward -n aiops svc/aiops-brain 8000:8000
curl http://localhost:8000/incidents | jq .

# 4. Open Grafana to see the dashboard
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80
# open http://localhost:3000  (admin / <grafana_admin_password>)
```

### Phase 8A — Deploy CryptoFlux

```bash
# Add CryptoFlux variables to terraform.tfvars:
#   cf_db_pass, cf_dr_db_pass, cf_secret_key,
#   cf_trading_data_api_key, cf_ext_api_key

# Build and load all 6 CryptoFlux images into k3s
bash src/cryptoflux/build-and-load-all.sh

# Deploy CryptoFlux namespace + all 8 services
cd terraform
terraform apply -target=module.cryptoflux -var-file=terraform.tfvars

# Verify all pods are running
kubectl get pods -n cryptoflux

# Access the trading UI
# open http://<node-ip>:30500
```

### Phase 8B — Security monitoring (automatic after Phase 8A)

The security scan CronJob starts automatically with the `cryptoflux` module. It fires every 5 minutes. To trigger a manual scan:

```bash
kubectl port-forward -n aiops svc/aiops-brain 8000:8000
curl -X POST http://localhost:8000/security-scan

# View detected security incidents
curl http://localhost:8000/security-events | jq .
```

---

## Kubernetes Namespaces

| Namespace | Contents | Purpose |
|---|---|---|
| `observability` | Prometheus, Alertmanager, Grafana, Loki, Promtail | Full observability stack |
| `database` | PostgreSQL 16 (Bitnami) | Persistent incident storage |
| `apps` | flask-app Deployment (2 replicas) | Chaos injection target |
| `aiops` | aiops-brain Deployment, migration Job, RBAC, Secrets | Incident response orchestrator |
| `chaos` | (reserved) | Chaos tooling and test workloads |
| `cryptoflux` | CryptoFlux trading platform (8 services) | Vulnerable app + security monitoring target |

---

## CryptoFlux Platform

CryptoFlux is an intentionally vulnerable eight-service trading platform deployed in the `cryptoflux` namespace. It serves as the target for Phase 8B security monitoring.

| Service | Port | Description |
|---|---|---|
| `trading-ui` | 30500 (NodePort) | Flask trading dashboard — vulnerable `/api/search` and `/internal/debug` |
| `trading-data` | 7100 (ClusterIP) | Market data microservice |
| `ext-api` | 8000 (ClusterIP) | External transaction API (SQLite-backed) |
| `liquidity-calc` | 8001 (ClusterIP) | Liquidity calculator — hardcoded `INTERNAL_SERVICE_KEY` |
| `data-ingestion` | — | Background worker — polls ext-api and inserts transactions |
| `dr-sync` | — | Background worker — replicates primary → DR every 5 minutes |
| `postgresql-primary` | 5432 (ClusterIP) | Primary PostgreSQL database |
| `postgresql-dr` | 5432 (ClusterIP) | DR replica — receives sync from dr-sync worker |

**Access:** `http://<node-ip>:30500`

**Disaster recovery targets:**
- RPO < 5 minutes (dr-sync interval)
- RTO < 2 minutes (manual promotion with runbook)

**Source:** [github.com/BeyondMachines/ceaao2025-cryptoflux](https://github.com/BeyondMachines/ceaao2025-cryptoflux)

---

## Security Monitoring

`security_monitor.py` scans the last 15 minutes of Loki logs for all CryptoFlux services every time `/security-scan` is called. A Kubernetes CronJob triggers this endpoint every 5 minutes. Every detected event follows the same pipeline as a regular incident: persisted to PostgreSQL, filed as a GitHub issue, and delivered via Slack — without invoking Claude (security events require human review).

| Detection | Severity | Source service | Pattern |
|---|---|---|---|
| SQL Injection | `critical` | `trading-ui` | `OR '1'='1'`, `UNION SELECT`, `DROP TABLE`, `--`, `1=1` in `SEARCH query=` log |
| XSS Attack | `critical` | `trading-ui` | `<script`, `javascript:`, `onerror=`, `onload=` in `SEARCH query=` log |
| Info Leak | `warning` | `trading-ui` | `/internal/debug` or `/internal/info` accessed |
| Hardcoded Secret | `warning` | `liquidity-calc` | Literal `hardcoded_secret_123` appears in any log line |
| Transaction Gap | `critical` | `data-ingestion` | No `Cycle OK` or `ok=N` log entry in 15 minutes |
| DR Sync Failure | `warning` | `dr-sync` | `Sync error` appears in logs |
| Command Injection | `critical` | `attack-console` | `CMD query=` log line containing shell metacharacters (`;`, `&`, `\|`, `` ` ``) |
| Broken Authentication | `critical` | `attack-console` | `LOGIN attempt` log line with `OR '1'='1'`, `admin' --`, or `' OR` SQLi pattern |

Each event type is deduplicated within a 1-hour window — the same attack type on the same service creates only one GitHub issue per hour, preventing alert spam.

**Trigger manually:**

```bash
kubectl port-forward -n aiops svc/aiops-brain 8000:8000
curl -X POST http://localhost:8000/security-scan

# View recent security events
curl http://localhost:8000/security-events | jq .
```

### Attack Demo Commands

Demonstrate each detection by hitting the vulnerable endpoints directly:

```bash
NODE_IP=<your-node-ip>

# SQL injection — OR '1'='1' bypass
curl -g "http://${NODE_IP}:30500/api/search?q=%27%20OR%20%271%27%3D%271%27%20--"

# SQL injection — UNION SELECT
curl -g "http://${NODE_IP}:30500/api/search?q=x%27%20UNION%20SELECT%201%2C2%2C3%2C4%2C5--"

# XSS — script tag in query parameter
curl "http://${NODE_IP}:30500/api/search?q=<script>alert('xss')</script>"

# XSS — event handler payload
curl "http://${NODE_IP}:30500/api/search?q=<img%20src=x%20onerror=alert(1)>"

# Info leak — dump all environment variables
curl "http://${NODE_IP}:30500/internal/debug"

# Broken auth bypass (Attack Console)
# Go to http://<node-ip>:30600/login
# Username: admin' OR '1'='1' --
# Password: (anything)

# Command injection (Attack Console)
# Go to http://<node-ip>:30600/cmd-injection
# Target: 127.0.0.1; id
```

After running any of these, wait up to 5 minutes for the CronJob to fire, or trigger a manual scan:

```bash
kubectl port-forward -n aiops svc/aiops-brain 8000:8000 &
curl -X POST http://localhost:8000/security-scan
sleep 5
curl http://localhost:8000/security-events | jq '.[0]'
```

---

## Attack Console

A DVWA-style vulnerability lab deployed at `http://<node-ip>:30600`. Built as a separate Flask service in the `cryptoflux` namespace, it demonstrates five OWASP vulnerability classes against the CryptoFlux platform. Every attack is logged via `logger.warning` so Loki captures it and the aiops-brain security scanner can detect it.

| Vulnerability | Severity | CWE | OWASP |
|---|---|---|---|
| SQL Injection | Critical | CWE-89 | A03:2021 |
| Cross-Site Scripting (XSS) | Critical | CWE-79 | A03:2021 |
| Broken Authentication | Critical | CWE-287 | A07:2021 |
| Information Leakage | High | CWE-200 | A05:2021 |
| Command Injection | Critical | CWE-78 | A03:2021 |

Each page shows:
- Vulnerable code vs the safe parameterized alternative
- Live attack form with results
- Example payloads
- All attacks logged to Loki and detected by aiops-brain

**Access:** `http://<node-ip>:30600`

**Build and deploy:**

```bash
bash src/attack-console/build-and-load.sh
cd terraform
terraform apply -target=module.cryptoflux -var-file=terraform.tfvars
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

**9. Slack notification** — `slack_client.py` sends a Block Kit message to the configured webhook URL. The message includes the severity emoji, alert name, service and severity fields, the first 300 characters of Claude's root cause, and a primary-style button linking directly to the GitHub issue.

**10. Auto-remediation** — `remediation.py` maps the alert name to a remediation strategy using the aiops-brain's Kubernetes ServiceAccount (ClusterRole: `get/list/delete` pods, `get/list/patch` deployments). CrashLoop/OOMKill alerts trigger a pod deletion; high-memory/high-CPU alerts trigger a rolling restart via annotation patch. Claude's `auto_remediation_safe` flag gates execution.

**11. Result update** — The `remediation_action` and `remediation_result` columns in PostgreSQL are updated with the outcome. The incident record is now complete and queryable via `GET /incidents`.

**Security scan pipeline** (Phase 8B) — The CronJob in the `cryptoflux` namespace posts to `/security-scan` every 5 minutes. `security_monitor.py` fetches 15 minutes of Loki logs per service, runs regex detectors for each attack pattern, and routes every `SecurityEvent` through steps 7–9 above (persist, GitHub, Slack). Claude analysis and auto-remediation are skipped — security findings always require human review.

---

## Observability & Dashboards

### Accessing Grafana

```bash
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80
# open http://localhost:3000
# username: admin
# password: <grafana_admin_password from terraform.tfvars>
```

### AIOps Incident Response Dashboard

The dashboard is provisioned automatically via a Kubernetes ConfigMap with label `grafana_dashboard=1`. The Grafana sidecar detects and loads it on startup. It contains eight panels across four rows:

| Panel | Type | Data source | What it shows |
|---|---|---|---|
| Total Incidents | Stat | PostgreSQL | `COUNT(*)` from incidents table, colour-coded by threshold |
| Auto-Remediation Success Rate | Stat | PostgreSQL | Percentage of incidents where auto-remediation was attempted |
| Pod Restarts (1h) | Stat | Prometheus | `increase(kube_pod_container_status_restarts_total[1h])` |
| Incidents by Severity | Pie chart | PostgreSQL | Distribution across critical / warning / info |
| Incidents over Time | Time series | PostgreSQL | Hourly bar chart for the selected time range |
| Flask App CPU Usage | Time series | Prometheus | `rate(container_cpu_usage_seconds_total[5m])` per pod |
| Flask App Memory Usage | Time series | Prometheus | `container_memory_working_set_bytes` per pod, bytes unit |
| Latest 10 Incidents | Table | PostgreSQL | Alert, severity (colour-coded), service, fired_at, root cause excerpt, GitHub issue link |

The PostgreSQL datasource (`uid: postgresql`) is provisioned directly in the kube-prometheus-stack Helm values alongside Loki, so no manual Grafana configuration is required.

---

## Notifications

### Slack Block Kit

When `SLACK_WEBHOOK_URL` is configured, every processed incident produces a message in the following format:

```
🔴  FlaskAppPodRestarted
─────────────────────────────────
Service       flask-app
Severity      critical
Fired At      2026-03-21 14:32:07 UTC

Root Cause
The flask-app container was force-terminated, triggering an immediate
restart by the Deployment controller...

[ View GitHub Issue ]  ← primary button

Responded by aiops-brain · powered by Claude AI
```

Severity emojis: 🔴 critical · 🟡 warning · 🔵 info · ⚪ unknown

The `View GitHub Issue` button is only rendered when a GitHub issue was successfully created. If Slack delivery fails, the error is logged as a warning and the pipeline continues unaffected.

### Configuration

**Terraform (recommended):** add to `terraform.tfvars`:

```hcl
slack_webhook_url = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
```

Terraform injects this into the `aiops-brain-env` Kubernetes Secret. Leave it as `""` or omit it entirely to disable Slack notifications without affecting any other pipeline step.

**Local development:** add to `.env`:

```bash
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ
```

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
| `SLACK_WEBHOOK_URL` | aiops-brain | Slack incoming webhook URL (optional — omit to disable) |

For local development, export variables from a `.env` file (never committed):

```bash
export $(grep -v '^#' .env | xargs)
cd src/aiops-brain && uvicorn main:app --reload --port 8080
```

---

## Demo

When a pod-kill chaos event fires, the full pipeline produces a GitHub issue and Slack notification within approximately 90 seconds:

```
[CRITICAL] FlaskAppPodRestarted — flask-app
```

**GitHub issue body:**

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

When a security scan detects SQL injection, the same pipeline produces:

```
[CRITICAL] SecurityScan:SQLInjection — trading-ui
```

```json
{
  "id": "b7e3a2f1-9c4d-4b8e-a1d2-3e4f5a6b7c8d",
  "alert_name": "SecurityScan:SQLInjection",
  "severity": "critical",
  "service": "trading-ui",
  "fired_at": "2026-03-22T10:15:00",
  "root_cause": "SQL injection pattern detected in trading-ui search query logs",
  "github_issue_url": "https://github.com/DeniStojanovski/aiops-ire/issues/7",
  "remediation_action": null,
  "remediation_result": null,
  "created_at": "2026-03-22T10:15:03"
}
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.
