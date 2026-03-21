#!/usr/bin/env bash
# Build the flask-app Docker image and import it directly into k3s.
# No registry required — the image is loaded via containerd's ctr tool.

set -euo pipefail

IMAGE="flask-app:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building ${IMAGE} from ${SCRIPT_DIR}"
docker build -t "${IMAGE}" "${SCRIPT_DIR}"

echo "==> Loading ${IMAGE} into k3s containerd"
docker save "${IMAGE}" | sudo k3s ctr images import -

echo "==> Done. Image available in k3s:"
sudo k3s ctr images ls | grep flask-app
