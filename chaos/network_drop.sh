#!/usr/bin/env bash
# chaos/network_drop.sh
# exec into a flask pod and use `tc` (traffic control) to add 500 ms of
# network latency on the eth0 interface, causing /slow-style latency even
# on normal requests and triggering HighLatency / SLO alerts.
# tc is available in the python:3.12-slim base image via iproute2.

set -euo pipefail

NAMESPACE="apps"
SERVICE="flask-app"
LATENCY_MS=500       # added delay in milliseconds
JITTER_MS=100        # ± jitter
HOLD_SECONDS=60      # how long to keep the rule active
PORT="5000"

source "$(dirname "$0")/_common.sh"

banner "NETWORK LATENCY"
echo "  Namespace : ${NAMESPACE}"
echo "  Latency   : ${LATENCY_MS}ms ± ${JITTER_MS}ms on eth0"
echo "  Hold time : ${HOLD_SECONDS}s"
echo ""

POD=$(get_pod "$NAMESPACE" "$SERVICE")
echo "[+] Target pod: ${POD}"
echo ""

# Verify tc is available inside the image
if ! kubectl exec -n "$NAMESPACE" "$POD" -- which tc &>/dev/null; then
    echo "[!] 'tc' not found in pod — installing iproute2..."
    kubectl exec -n "$NAMESPACE" "$POD" -- apt-get install -y -q iproute2 2>/dev/null || {
        echo "[✗] Could not install iproute2. Ensure the image includes it, or use a privileged pod."
        exit 1
    }
fi

cleanup_tc() {
    echo ""
    echo "[+] Removing tc netem rule from pod ${POD}..."
    kubectl exec -n "$NAMESPACE" "$POD" -- \
        tc qdisc del dev eth0 root 2>/dev/null || true
    print_watch_url
}
trap cleanup_tc EXIT

echo "[+] Applying tc netem: ${LATENCY_MS}ms delay, ${JITTER_MS}ms jitter..."
kubectl exec -n "$NAMESPACE" "$POD" -- \
    tc qdisc add dev eth0 root netem delay "${LATENCY_MS}ms" "${JITTER_MS}ms"

echo ""
echo "[+] Verifying rule:"
kubectl exec -n "$NAMESPACE" "$POD" -- tc qdisc show dev eth0

# Open a port-forward and measure round-trip latency visually
echo ""
echo "[+] Opening port-forward on localhost:${PORT} to show impact..."
kubectl port-forward -n "$NAMESPACE" "pod/${POD}" "${PORT}:${PORT}" &>/dev/null &
PF_PID=$!
sleep 2
trap "kill $PF_PID 2>/dev/null || true; cleanup_tc" EXIT

echo "[+] Measuring /health latency (expect ~${LATENCY_MS}ms+):"
END=$(( $(date +%s) + HOLD_SECONDS ))
while [[ $(date +%s) -lt $END ]]; do
    TIME_MS=$(curl -sf -o /dev/null -w "%{time_total}" "http://localhost:${PORT}/health" \
        | awk '{printf "%.0f", $1 * 1000}' || echo '?')
    echo "    $(date '+%H:%M:%S')  /health response time: ${TIME_MS}ms"
    sleep 5
done

echo ""
echo "[✓] Network latency phase complete. tc rule will be removed by cleanup trap."
