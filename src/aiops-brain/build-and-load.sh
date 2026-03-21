#!/usr/bin/env bash
# Build the aiops-brain Docker image and import it directly into k3s.
# No registry required — the image is loaded via containerd's ctr tool.

set -euo pipefail

IMAGE="aiops-brain:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building ${IMAGE} from ${SCRIPT_DIR}"
docker build -t "${IMAGE}" "${SCRIPT_DIR}"

echo "==> Loading ${IMAGE} into k3s containerd"
docker save "${IMAGE}" | sudo k3s ctr images import -

echo "==> Done. Image available in k3s:"
sudo k3s ctr images ls | grep aiops-brain
