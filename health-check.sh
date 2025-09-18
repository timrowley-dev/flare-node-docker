#!/bin/bash
# Health check script for Flare node
# Equivalent to the --status option from the old script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if container is running
if ! docker-compose ps | grep -q "Up"; then
    print_error "Flare node container is not running"
    echo "Run 'docker-compose up -d' to start the node"
    exit 1
fi

print_status "Checking Flare node health..."

# Get health status
if ! curl_health=$(curl -s http://localhost:9650/ext/health 2>/dev/null); then
    print_error "Failed to connect to node health endpoint"
    print_warning "Make sure the node is fully started and accessible on port 9650"
    exit 1
fi

# Parse health information
healthy_value=$(echo "$curl_health" | jq -r '.healthy // "unknown"' 2>/dev/null || echo "unknown")
connected_peers=$(echo "$curl_health" | jq -r '.checks.network.message.connectedPeers // "unknown"' 2>/dev/null || echo "unknown")

# Get node version
if curl_version=$(curl -s --location 'http://localhost:9650/ext/info' \
    --header 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeVersion","params":[]}' 2>/dev/null); then
    node_version=$(echo "$curl_version" | jq -r '.result.version // "unknown"' 2>/dev/null || echo "unknown")
else
    node_version="unknown"
fi

# Get container status
container_status=$(docker-compose ps --format "table {{.Name}}\t{{.Status}}" | tail -n +2)

echo "========================================="
echo "           FLARE NODE STATUS"
echo "========================================="
echo
echo "Container Status:"
echo "$container_status"
echo
echo "Node Health:"
echo "  Healthy: $healthy_value"
echo "  Connected Peers: $connected_peers"
echo "  Node Version: $node_version"
echo

# Additional Docker info
print_status "Docker container details:"
docker-compose ps

# Check if there are any recent errors in logs
print_status "Recent log entries (last 10 lines):"
docker-compose logs --tail=10

if [ "$healthy_value" == "true" ]; then
    print_status "Node is healthy and operational!"
else
    print_warning "Node health check indicates issues. Check logs for details."
fi
