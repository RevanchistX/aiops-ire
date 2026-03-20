# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
A self-healing infrastructure platform on bare Ubuntu Server. When failures occur, the system automatically detects them, pulls logs, analyzes root cause via Claude API, persists the incident to PostgreSQL, opens a GitHub issue with a remediation runbook, and attempts auto-remediation — zero human involvement.

## Full Stack
- Ansible → k3s + Helm + OS hardening
- Terraform (providers: kubernetes, helm, postgresql, github) → all k8s resources
- Kubernetes k3s single node → all workloads
- Prometheus + Alertmanager + Loki + Promtail + Grafana → observability
- PostgreSQL 16 + SQLAlchemy + Alembic → incident persistence
- Flask Python 3.12 → chaos target microservices
- FastAPI Python 3.12 → AI-Ops brain / webhook receiver
- Claude API claude-sonnet-4-20250514 → log analysis + runbook generation
- GitHub API → auto issue creation
- Chaos scripts → CPU spike, memory leak, disk fill, network drop, pod kill

## Architecture Flow
```
Chaos injects failure
  → Prometheus detects degradation → fires alert
  → Alertmanager sends POST to aiops-brain /webhook
  → aiops-brain extracts alert metadata, queries Loki for logs (last 10 min)
  → alert + logs sent to Claude API → returns root cause + remediation runbook
  → incident saved to PostgreSQL
  → GitHub issue auto-created with Claude's runbook
  → auto-remediation attempted (pod restart, scale up, etc.)
  → remediation result updated in PostgreSQL
  → Grafana reflects new incident in real time
```

## Build Phases (sequential — do not skip)
1. **Ansible** — server setup, k3s, Helm, OS hardening
2. **Terraform** — namespaces + PostgreSQL (Bitnami Helm chart) → `module.namespaces`, `module.database`
3. **Terraform** — observability stack (Prometheus, Alertmanager, Loki, Grafana) → `module.observability`
4. **Terraform** — Flask chaos-target apps → `module.apps`
5. **Terraform** — aiops-brain, Alertmanager webhook wired, GitHub integration → `module.aiops`
6. **Chaos scripts** — end-to-end pipeline validation

## Common Commands

### Ansible
```bash
# Verify connectivity before running playbooks
ansible -i ansible/inventory.ini all -m ping

# Run full server setup
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-server.yml

# Run OS hardening
ansible-playbook -i ansible/inventory.ini ansible/playbooks/hardening.yml

# Run a specific tag only
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-server.yml --tags k3s
```

### Terraform
```bash
cd terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# Target a single module
terraform apply -target=module.observability
```

### aiops-brain (Python / FastAPI)
```bash
cd src/aiops-brain

# Install dependencies
pip install -r requirements.txt

# Run locally (requires env vars set)
uvicorn main:app --reload --port 8080

# Run DB migrations
alembic upgrade head

# Create a new migration
alembic revision --autogenerate -m "describe change"
```

### Docker / k3s image loading
```bash
# Build and load image into k3s (no registry needed)
docker build -t aiops-brain:latest src/aiops-brain/
docker save aiops-brain:latest | sudo k3s ctr images import -

docker build -t flask-app:latest src/flask-apps/
docker save flask-app:latest | sudo k3s ctr images import -
```

### Chaos injection
```bash
# Run a specific chaos scenario
bash chaos/cpu_spike.sh
bash chaos/pod_kill.sh

# Run the main chaos runner (prompts for scenario selection)
bash chaos/inject.sh
```

## Codebase Layout
- `ansible/roles/` — three roles: `common` (base packages), `k3s` (k3s install), `helm` (Helm install)
- `terraform/modules/` — one module per Terraform build phase (namespaces, database, observability, apps, aiops)
- `kubernetes/` — raw manifests organized by concern (namespaces, database, observability, apps, aiops, chaos); referenced by Terraform via `file()`
- `src/aiops-brain/` — FastAPI app; `migrations/` holds Alembic revisions
- `src/flask-apps/` — Flask chaos-target microservices
- `chaos/` — shell scripts for each failure scenario

## Tool Responsibilities
- **Ansible**: server configuration only — never application logic
- **Terraform**: all Kubernetes resource definitions; all state in terraform.tfstate
- **kubectl**: never used manually — all changes go through Terraform
- **Kubernetes manifests**: stored in `/kubernetes/`, referenced via Terraform `file()` or applied via Helm

## Kubernetes Conventions
- Namespace per concern; never deploy to `default`
- All secrets via Kubernetes Secrets — never hardcoded or in ConfigMaps
- Resource requests AND limits required on every container
- Liveness and readiness probes required on every Deployment
- kubeconfig at `/etc/rancher/k3s/k3s.yaml`

## Database Schema
```
incidents
  id                  UUID PRIMARY KEY
  alert_name          VARCHAR
  severity            VARCHAR
  service             VARCHAR
  fired_at            TIMESTAMP
  resolved_at         TIMESTAMP NULLABLE
  raw_alert           JSONB          -- full Alertmanager payload
  logs_snapshot       TEXT           -- Loki logs at time of incident
  claude_analysis     TEXT           -- full Claude API response
  root_cause          TEXT
  runbook             TEXT
  github_issue_url    VARCHAR NULLABLE
  remediation_action  VARCHAR NULLABLE
  remediation_result  VARCHAR NULLABLE
  created_at          TIMESTAMP DEFAULT NOW()
```

## Environment Variables
All injected as Kubernetes Secrets — never hardcoded.

| Variable | Used By | Format |
|---|---|---|
| `CLAUDE_API_KEY` | aiops-brain | Anthropic API key |
| `GITHUB_TOKEN` | aiops-brain | PAT with repo scope |
| `GITHUB_REPO` | aiops-brain | `owner/repo` |
| `DATABASE_URL` | aiops-brain | `postgresql://user:pass@host:5432/aiops` |
| `LOKI_URL` | aiops-brain | `http://loki.observability.svc.cluster.local:3100` |
| `PROMETHEUS_URL` | aiops-brain | `http://prometheus.observability.svc.cluster.local:9090` |

For local development, set these in a `.env` file (never committed) and load with `export $(cat .env | xargs)`.

## Coding Style
- **Python**: type hints everywhere, docstrings on all functions, `logging` not `print()`, Pydantic models for all request/response schemas
- **Terraform**: one module per concern, no logic in root `main.tf`, all variables have descriptions
- **Ansible**: idempotent tasks only, tags on every task, prefer modules over `shell:`
- **YAML**: 2-space indent, comments on non-obvious config
- **Git**: conventional commits — `feat:`, `fix:`, `infra:`, `docs:`; one concern per commit
