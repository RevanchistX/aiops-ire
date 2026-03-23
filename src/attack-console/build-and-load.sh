#!/usr/bin/env bash
# Build the attack-console image and load it into k3s (no registry needed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="cryptoflux-attack-console:latest"

echo "[+] Building $IMAGE from $SCRIPT_DIR ..."
docker build -t "$IMAGE" "$SCRIPT_DIR"

echo "[+] Loading $IMAGE into k3s ..."
docker save "$IMAGE" | sudo k3s ctr images import -

echo "[+] Done — $IMAGE is available in k3s."
