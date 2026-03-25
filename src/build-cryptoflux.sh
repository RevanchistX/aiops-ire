#!/bin/bash
# Build and load all CryptoFlux services into k3s

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRYPTOFLUX_DIR="$SCRIPT_DIR/src/cryptoflux"

if [ ! -d "$CRYPTOFLUX_DIR" ]; then
    echo "Error: CryptoFlux submodule not found at $CRYPTOFLUX_DIR"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

echo "Building and loading CryptoFlux services..."

# Get list of all Dockerfiles
services=$(find "$CRYPTOFLUX_DIR" -name "Dockerfile" -not -path "*/node_modules/*" | sed 's|/Dockerfile||')

for service_dir in $services; do
    service_name=$(basename "$service_dir")
    image_tag="cryptoflux-$service_name:latest"

    echo "Building $image_tag..."
    docker build -t "$image_tag" "$service_dir"

    echo "Loading into k3s..."
    docker save "$image_tag" | sudo k3s ctr images import -
done

echo "Done!"
