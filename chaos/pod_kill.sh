#!/usr/bin/env bash
# chaos/pod_kill.sh
# Delete one flask-app pod to simulate a crash / OOMKill.
# The Deployment controller immediately schedules a replacement pod.
# kube-prometheus-stack fires KubePodNotReady / PodRestarting alerts
# within ~1–2 minutes while the new pod initialises.

set -euo pipefail

NAMESPACE="apps"
SERVICE="flask-app"
WAIT_AFTER=60   # seconds to watch the pod come back up

source "$(dirname "$0")/_common.sh"

banner "POD KILL"
echo "  Namespace : ${NAMESPACE}"
echo "  Service   : ${SERVICE}"
echo ""

POD=$(get_pod "$NAMESPACE" "$SERVICE")
echo "[+] Selected pod to kill: ${POD}"
echo ""

echo "[+] Current pod state before kill:"
kubectl get pods -n "$NAMESPACE" -l "app=${SERVICE}" \
    --no-headers \
    -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName"
echo ""

echo "[+] Deleting pod ${POD}..."
kubectl delete pod -n "$NAMESPACE" "$POD" --grace-period=0 --force 2>/dev/null || \
    kubectl delete pod -n "$NAMESPACE" "$POD"

echo ""
echo "[+] Pod deleted. Watching Deployment schedule a replacement for ${WAIT_AFTER}s..."
echo "    (Alertmanager should fire within ~1 min)"
echo ""

END=$(( $(date +%s) + WAIT_AFTER ))
while [[ $(date +%s) -lt $END ]]; do
    echo "--- $(date '+%H:%M:%S') ---"
    kubectl get pods -n "$NAMESPACE" -l "app=${SERVICE}" \
        --no-headers \
        -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount" \
        2>/dev/null || echo "  (pods not yet listed)"
    sleep 5
done

echo ""
echo "[✓] Pod kill complete. Check that a new pod reached Running/Ready state above."

print_watch_url
