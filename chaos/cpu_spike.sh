#!/usr/bin/env bash
# chaos/cpu_spike.sh
# Hit the Flask /cpu endpoint, which burns a CPU core for 30s per hit.
# Two concurrent hits = two threads pegged, enough to trigger HighCPU alerts.

set -euo pipefail

NAMESPACE="apps"
SERVICE="flask-app"
PORT="5000"
DURATION=60   # seconds to keep hammering
INTERVAL=5    # seconds between hits

source "$(dirname "$0")/_common.sh"

banner "CPU SPIKE"
echo "  Target   : http://${SERVICE}.${NAMESPACE}:${PORT}/cpu"
echo "  Duration : ${DURATION}s (2 concurrent curl workers)"
echo ""

POD=$(get_pod "$NAMESPACE" "$SERVICE")
echo "[+] Using pod: ${POD}"
echo ""

# We port-forward from the pod so we can hit it from the host
echo "[+] Opening port-forward on localhost:${PORT}..."
kubectl port-forward -n "$NAMESPACE" "pod/${POD}" "${PORT}:${PORT}" &>/dev/null &
PF_PID=$!
sleep 2   # give port-forward time to establish

cleanup() {
    echo ""
    echo "[+] Stopping port-forward (pid ${PF_PID})"
    kill "$PF_PID" 2>/dev/null || true
    print_watch_url
}
trap cleanup EXIT

echo "[+] Hammering /cpu for ${DURATION}s (hitting endpoint every ${INTERVAL}s)..."
END=$(( $(date +%s) + DURATION ))

while [[ $(date +%s) -lt $END ]]; do
    echo "    $(date '+%H:%M:%S')  POST /cpu  →  $(curl -sf "http://localhost:${PORT}/cpu" || echo 'connection error')"
    sleep "$INTERVAL"
done

echo ""
echo "[✓] CPU spike phase complete."
