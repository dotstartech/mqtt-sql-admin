#!/bin/bash
# Build Docker image for mqtt-sql-admin
# Tags the image with both the version from msa.properties and 'latest'

set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Read version from msa.properties
PROPERTIES_FILE="$PROJECT_DIR/msa.properties"
if [[ ! -f "$PROPERTIES_FILE" ]]; then
    echo "Error: msa.properties not found at $PROPERTIES_FILE"
    exit 1
fi

VERSION=$(grep -E "^version=" "$PROPERTIES_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
if [[ -z "$VERSION" ]]; then
    echo "Error: version not found in msa.properties"
    exit 1
fi

IMAGE_NAME="mqtt-sql-admin"

echo "Building $IMAGE_NAME version $VERSION..."

# Build and tag with version
docker build -t "$IMAGE_NAME:$VERSION" -t "$IMAGE_NAME:latest" -f "$PROJECT_DIR/docker/Dockerfile" "$PROJECT_DIR"

echo ""
echo "Successfully built:"
echo "  - $IMAGE_NAME:$VERSION"
echo "  - $IMAGE_NAME:latest"
