#!/usr/bin/env bash
# Build all CryptoFlux Docker images and load them into k3s.
# Run from anywhere — paths are resolved relative to ~/ceaao2025-cryptoflux.
set -euo pipefail

CRYPTOFLUX_DIR="${HOME}/ceaao2025-cryptoflux"

if [[ ! -d "${CRYPTOFLUX_DIR}" ]]; then
  echo "ERROR: ${CRYPTOFLUX_DIR} not found. Clone the repo first:"
  echo "  git clone https://github.com/BeyondMachines/ceaao2025-cryptoflux ~/ceaao2025-cryptoflux"
  exit 1
fi

build_and_load() {
  local image_name="$1"
  local context_dir="$2"

  echo ""
  echo ">>> Building ${image_name} from ${context_dir}"
  docker build -t "${image_name}" "${context_dir}"

  echo ">>> Loading ${image_name} into k3s"
  docker save "${image_name}" | sudo k3s ctr images import -

  echo ">>> Done: ${image_name}"
}

build_and_load "cryptoflux-ext-api:latest"       "${CRYPTOFLUX_DIR}/external-transactions-api"
build_and_load "cryptoflux-trading-data:latest"   "${CRYPTOFLUX_DIR}/trading_data_microservice"
build_and_load "cryptoflux-trading-ui:latest"     "${CRYPTOFLUX_DIR}/trading-platform-ui"
build_and_load "cryptoflux-liquidity-calc:latest" "${CRYPTOFLUX_DIR}/liquidity_calc"
build_and_load "cryptoflux-data-ingestion:latest" "${CRYPTOFLUX_DIR}/data_ingestion_service"
build_and_load "cryptoflux-dr-sync:latest"        "${CRYPTOFLUX_DIR}/dr_sync_service"

echo ""
echo "All CryptoFlux images built and loaded into k3s."
echo "Verify with: sudo k3s ctr images list | grep cryptoflux"
