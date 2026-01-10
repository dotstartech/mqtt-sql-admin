#!/bin/bash
# Deploy mqbase to Docker Swarm
# Reads version from mqbase.properties and deploys with that tag

set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Read version from mqbase.properties
PROPERTIES_FILE="$PROJECT_DIR/mqbase.properties"
if [[ ! -f "$PROPERTIES_FILE" ]]; then
    echo "Error: mqbase.properties not found at $PROPERTIES_FILE"
    exit 1
fi

VERSION=$(grep -E "^version=" "$PROPERTIES_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
if [[ -z "$VERSION" ]]; then
    echo "Error: version not found in mqbase.properties"
    exit 1
fi

export MQBASE_VERSION="$VERSION"

echo "Deploying mqbase version $MQBASE_VERSION..."

cd "$PROJECT_DIR"
docker stack deploy -c compose.yml mqbase

echo ""
echo "Deployed mqbase:$MQBASE_VERSION"
