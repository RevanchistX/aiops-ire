#!/usr/bin/env bash
# chaos/inject.sh
# Interactive chaos injection menu.
# Calls the appropriate scenario script based on user selection.
# All scenarios target flask-app pods in the apps namespace.

set -euo pipefail

CHAOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_ISSUES_URL="https://github.com/DeniStojanovski/aiops-ire/issues"

# ── Prerequisites check ───────────────────────────────────────────────────────
for cmd in kubectl curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[✗] Required command not found: ${cmd}"
        exit 1
    fi
done

# ── Verify cluster connectivity ───────────────────────────────────────────────
if ! kubectl get pods -n apps -l app=flask-app --no-headers &>/dev/null; then
    echo ""
    echo "[✗] Cannot reach flask-app pods in namespace 'apps'."
    echo "    Ensure k3s is running and terraform apply has completed through Phase 4."
    echo ""
    exit 1
fi

# ── Menu ──────────────────────────────────────────────────────────────────────
clear
cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║          aiops-ire  —  Chaos Injection Console               ║
║  Triggers Prometheus alerts → Alertmanager → aiops-brain     ║
║  → Claude analysis → GitHub issue → auto-remediation         ║
╚══════════════════════════════════════════════════════════════╝

  Current flask-app pods:
EOF

kubectl get pods -n apps -l app=flask-app \
    --no-headers \
    -o custom-columns="    NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount" \
    2>/dev/null || echo "    (unable to list pods)"

cat <<'EOF'

  Select a chaos scenario:

  [1]  CPU Spike       — Pin a CPU core at 100% for 60s
                         (triggers HighCPUUsage alert)

  [2]  Memory Leak     — Leak 10 MB every 3s for 60s (~200 MB total)
                         (triggers HighMemoryUsage / OOMKill alert)

  [3]  Disk Fill       — Write 200 MB to /tmp inside the pod
                         (triggers DiskPressure / EphemeralStorage alert)

  [4]  Network Latency — Add 500ms ± 100ms delay on eth0 for 60s
                         (triggers HighLatency / SLO breach alert)

  [5]  Pod Kill        — Force-delete a pod; Deployment auto-recreates it
                         (triggers KubePodNotReady / PodRestarting alert)

  [6]  All scenarios   — Run all five in sequence (destructive!)

  [q]  Quit

EOF

read -rp "  Choice: " CHOICE
echo ""

run_scenario() {
    local script="$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running: ${script}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "${CHAOS_DIR}/${script}"
}

case "$CHOICE" in
    1) run_scenario "cpu_spike.sh"     ;;
    2) run_scenario "memory_leak.sh"   ;;
    3) run_scenario "disk_fill.sh"     ;;
    4) run_scenario "network_drop.sh"  ;;
    5) run_scenario "pod_kill.sh"      ;;
    6)
        echo "[!] Running ALL scenarios in sequence. Press Ctrl-C to abort at any point."
        echo ""
        for s in cpu_spike.sh memory_leak.sh disk_fill.sh network_drop.sh pod_kill.sh; do
            run_scenario "$s"
            echo "[+] Pausing 30s before next scenario..."
            sleep 30
        done
        ;;
    q|Q)
        echo "Bye."
        exit 0
        ;;
    *)
        echo "[✗] Invalid choice: '${CHOICE}'"
        exit 1
        ;;
esac

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Chaos run complete."
echo ""
echo "  The aiops pipeline should have:"
echo "    1. Received the alert via Alertmanager webhook"
echo "    2. Pulled logs from Loki"
echo "    3. Sent alert + logs to Claude for analysis"
echo "    4. Saved the incident to PostgreSQL"
echo "    5. Opened a GitHub issue with the runbook"
echo "    6. Attempted auto-remediation"
echo ""
echo "  Watch for new issues at:"
echo "  ${GITHUB_ISSUES_URL}"
echo "════════════════════════════════════════════════════════════════"
echo ""
