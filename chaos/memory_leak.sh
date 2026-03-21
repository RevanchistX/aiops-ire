#!/usr/bin/env bash
# chaos/memory_leak.sh
# Repeatedly hit the Flask /memory endpoint, which appends 10 MB per call.
# After ~25 calls the pod will be at ~250 MB — past its 256 Mi limit,
# triggering an OOMKill and HighMemory alerts.

set -euo pipefail

NAMESPACE="apps"
SERVICE="flask-app"
PORT="5000"
DURATION=60   # seconds to keep hitting
INTERVAL=3    # seconds between calls — fast enough to breach the limit

source "$(dirname "$0")/_common.sh"

banner "MEMORY LEAK"
echo "  Target   : http://${SERVICE}.${NAMESPACE}:${PORT}/memory"
echo "  Leaks    : +10 MB per call, every ${INTERVAL}s"
echo "  Duration : ${DURATION}s"
echo ""

POD=$(get_pod "$NAMESPACE" "$SERVICE")
echo "[+] Using pod: ${POD}"
echo ""

echo "[+] Opening port-forward on localhost:${PORT}..."
kubectl port-forward -n "$NAMESPACE" "pod/${POD}" "${PORT}:${PORT}" &>/dev/null &
PF_PID=$!
sleep 2

cleanup() {
    echo ""
    echo "[+] Stopping port-forward (pid ${PF_PID})"
    kill "$PF_PID" 2>/dev/null || true
    print_watch_url
}
trap cleanup EXIT

echo "[+] Leaking memory for ${DURATION}s..."
END=$(( $(date +%s) + DURATION ))
CALL=0

while [[ $(date +%s) -lt $END ]]; do
    (( CALL++ ))
    RESP=$(curl -sf "http://localhost:${PORT}/memory" || echo '{"error":"connection failed"}')
    TOTAL=$(echo "$RESP" | grep -o '"total_leaked_mb":[0-9]*' | grep -o '[0-9]*' || echo '?')
    echo "    $(date '+%H:%M:%S')  call #${CALL}  total_leaked_mb=${TOTAL}"
    sleep "$INTERVAL"
done

echo ""
echo "[✓] Memory leak phase complete."
