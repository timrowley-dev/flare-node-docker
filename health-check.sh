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
if ! docker compose ps | grep -q "Up"; then
    print_error "Flare node container is not running"
    echo "Run 'docker compose up -d' to start the node"
    exit 1
fi

print_status "Checking Flare node health..."

# Prefer curl inside the container. Fall back to the host if exec is unavailable.
node_curl() {
    local body
    if body=$(docker compose exec -T flare-node curl -s "$@" 2>/dev/null); then
        printf '%s\n' "$body"
        return 0
    fi
    curl -s "$@" 2>/dev/null
}

# Get health status
if ! curl_health=$(node_curl http://localhost:9650/ext/health); then
    print_error "Failed to connect to node health endpoint"
    print_warning "Make sure the node is fully started and accessible on port 9650"
    exit 1
fi

# Parse health information
healthy_value=$(echo "$curl_health" | jq -r '.healthy // "unknown"' 2>/dev/null || echo "unknown")
connected_peers=$(echo "$curl_health" | jq -r '.checks.network.message.connectedPeers // "unknown"' 2>/dev/null || echo "unknown")
disk_percentage=$(echo "$curl_health" | jq -r '.checks.diskspace.message.availableDiskPercentage // empty' 2>/dev/null || true)
failing_checks=$(echo "$curl_health" | jq -r '
  .checks // {} | to_entries[]
  | select(.value.error != null)
  | [
      .key,
      (
        .value.error
        | if type == "string" then .
          elif type == "object" then (.message // tostring)
          else tostring
          end
      )
    ]
  | @tsv
' 2>/dev/null || true)

# Get node version
if curl_version=$(node_curl --location 'http://localhost:9650/ext/info' \
    --header 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeVersion","params":[]}'); then
    node_version=$(echo "$curl_version" | jq -r '.result.version // "unknown"' 2>/dev/null || echo "unknown")
else
    node_version="unknown"
fi

# Get container status
container_status=$(docker compose ps --format "table {{.Name}}\t{{.Status}}" | tail -n +2)

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
if [ -n "$disk_percentage" ]; then
    echo "  Available disk: ${disk_percentage}%"
fi
echo

# Additional Docker info
print_status "Docker container details:"
docker compose ps

if [ "$healthy_value" == "true" ]; then
    print_status "Node is healthy and operational!"
else
    diskspace_failed=0
    bootstrapped_failed=0
    other_failed=0
    if [ -n "$failing_checks" ]; then
        echo "Failing checks:"
        while IFS=$'\t' read -r check_name check_error; do
            [ -n "$check_name" ] || continue
            echo "  ${check_name}: ${check_error}"
            case "$check_name" in
                diskspace) diskspace_failed=1 ;;
                bootstrapped) bootstrapped_failed=1 ;;
                *) other_failed=1 ;;
            esac
        done <<EOF
$failing_checks
EOF
        echo
    else
        print_warning "The health endpoint reported unhealthy and did not name a failing check."
    fi

    if [ "$diskspace_failed" -eq 1 ]; then
        if [ -n "$disk_percentage" ]; then
            print_warning "diskspace warning: ${disk_percentage}% free. The node keeps validating until free space is under 3%."
        else
            print_warning "diskspace warning. The node keeps validating until free space is under 3%."
        fi
        echo "This is not a sync failure."
    fi
    if [ "$bootstrapped_failed" -eq 1 ]; then
        print_status "bootstrapped check failed: sync is still in progress."
    fi
    if [ "$other_failed" -eq 1 ]; then
        print_warning "One or more checks other than diskspace and bootstrapped failed."
    fi
    echo
    print_status "Recent log entries (last 3 lines):"
    docker compose logs --tail=3
fi
