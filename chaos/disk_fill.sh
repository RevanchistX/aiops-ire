#!/usr/bin/env bash
# chaos/disk_fill.sh
# exec into a flask pod and write a large file to /tmp until the ephemeral
# storage limit is approached, triggering a DiskPressure / eviction alert.
# The file is removed on EXIT so the pod survives after the chaos run.

set -euo pipefail

NAMESPACE="apps"
SERVICE="flask-app"
FILL_MB=200          # MB to write — stays under the typical 1 Gi ephemeral limit
                     # but is large enough to trigger DiskPressure warnings
CHUNK_MB=10          # write in chunks so progress is visible
HOLD_SECONDS=45      # keep the file around long enough for Prometheus to scrape

source "$(dirname "$0")/_common.sh"

banner "DISK FILL"
echo "  Namespace : ${NAMESPACE}"
echo "  Fill size : ${FILL_MB} MB (in ${CHUNK_MB} MB chunks)"
echo "  Hold time : ${HOLD_SECONDS}s before cleanup"
echo ""

POD=$(get_pod "$NAMESPACE" "$SERVICE")
echo "[+] Target pod: ${POD}"
echo ""

TMPFILE="/tmp/chaos_disk_fill_$$.dat"

cleanup_pod_file() {
    echo ""
    echo "[+] Removing fill file from pod..."
    kubectl exec -n "$NAMESPACE" "$POD" -- rm -f "$TMPFILE" 2>/dev/null || true
    print_watch_url
}
trap cleanup_pod_file EXIT

echo "[+] Writing ${FILL_MB} MB to ${TMPFILE} inside pod..."
CHUNKS=$(( FILL_MB / CHUNK_MB ))

for (( i=1; i<=CHUNKS; i++ )); do
    kubectl exec -n "$NAMESPACE" "$POD" -- \
        dd if=/dev/urandom bs=1M count="$CHUNK_MB" >> "$TMPFILE" 2>/dev/null
    WRITTEN=$(( i * CHUNK_MB ))
    echo "    $(date '+%H:%M:%S')  written ${WRITTEN} / ${FILL_MB} MB"
done

echo ""
echo "[+] Disk filled. Holding for ${HOLD_SECONDS}s so Prometheus can scrape..."
echo "    Watch for KubeNodeDiskPressure / PersistentVolumeUsage alerts."
sleep "$HOLD_SECONDS"

echo ""
echo "[✓] Disk fill phase complete. File will be removed by cleanup trap."
