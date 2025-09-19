#!/bin/bash
# Flare Node Update Script
# Updates the node to a new version

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to fetch latest version tags from Docker Hub
fetch_latest_tags() {
    # Send status message to stderr so it doesn't interfere with tag data
    print_status "Fetching latest tags from Docker Hub..." >&2
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed" >&2
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed" >&2
        return 1
    fi
    
    # Fetch tags from Docker Hub API
    local api_url="https://registry.hub.docker.com/v2/repositories/flarefoundation/go-flare/tags/?page_size=100"
    local tags_json
    
    if ! tags_json=$(curl -s "$api_url" 2>/dev/null); then
        print_error "Failed to fetch tags from Docker Hub" >&2
        return 1
    fi
    
    # Extract and filter tags that start with "v", sort by date, take latest 5
    local version_tags
    version_tags=$(echo "$tags_json" | jq -r '.results[] | select(.name | startswith("v")) | .name' | head -5)
    
    if [ -z "$version_tags" ]; then
        print_error "No version tags found" >&2
        return 1
    fi
    
    # Only echo the tags to stdout (for capture by command substitution)
    echo "$version_tags"
}

# Interactive tag selection
select_tag_interactively() {
    local tags
    if ! tags=$(fetch_latest_tags); then
        print_error "Failed to fetch tags. Please specify tag manually:"
        echo "Usage: $0 <new-tag-version>"
        echo "Examples:"
        echo "  $0 go-flare:v1.11.1"
        echo "  $0 go-flare:latest"
        echo ""
        echo "Available tags: https://hub.docker.com/r/flarefoundation/go-flare/tags"
        exit 1
    fi
    
    echo ""
    print_status "Available latest version tags:"
    echo ""
    
    # Convert to array for selection
    local tag_array=()
    local i=1
    while IFS= read -r tag; do
        if [ -n "$tag" ]; then
            echo "  $i) go-flare:$tag"
            tag_array+=("go-flare:$tag")
            ((i++))
        fi
    done <<< "$tags"
    
    echo "  $i) Custom version (enter manually)"
    echo "  0) Cancel"
    echo ""
    
    local choice
    while true; do
        read -p "Select version (0-$i): " choice
        
        if [[ "$choice" == "0" ]]; then
            print_status "Update cancelled"
            exit 0
        elif [[ "$choice" == "$i" ]]; then
            # Custom version
            read -p "Enter custom tag (e.g., go-flare:v1.11.1): " NEW_TAG
            if [ -z "$NEW_TAG" ]; then
                print_error "No tag specified"
                continue
            fi
            break
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            NEW_TAG="${tag_array[$((choice-1))]}"
            break
        else
            print_error "Invalid choice. Please select a number between 0 and $i"
        fi
    done
}

# Check if tag provided as argument or use interactive selection
if [ $# -eq 0 ]; then
    select_tag_interactively
else
    NEW_TAG="$1"
fi

# Check if .env file exists
if [ ! -f .env ]; then
    print_error ".env file not found. Please run ./setup.sh first."
    exit 1
fi

# Get current tag for comparison
current_tag=$(grep "^NODE_TAG=" .env | cut -d'=' -f2 || echo "unknown")

print_status "Flare Node Update Process"
echo "  Current version: $current_tag"
echo "  New version: $NEW_TAG"
echo ""

# Confirm the update
read -p "Continue with update? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_status "Update cancelled"
    exit 0
fi

print_status "Starting update process..."

# Step 1: Update the .env file
print_status "Updating NODE_TAG in .env file..."
if sed -i.backup "s|^NODE_TAG=.*|NODE_TAG=$NEW_TAG|" .env; then
    print_status "Updated NODE_TAG to: $NEW_TAG"
    print_status "Backup saved as: .env.backup"
else
    print_error "Failed to update .env file"
    exit 1
fi

# Step 2: Stop the current container
print_status "Stopping current container..."
if docker compose down; then
    print_status "Container stopped successfully"
else
    print_warning "No container was running or failed to stop"
fi

# Step 3: Pull the new image
print_status "Pulling new image: flarefoundation/$NEW_TAG"
if docker compose pull; then
    print_status "Successfully pulled new image"
else
    print_error "Failed to pull new image"
    print_status "Restoring previous configuration..."
    mv .env.backup .env
    exit 1
fi

# Step 4: Start with new image
print_status "Starting node with new version..."
if docker compose up -d; then
    print_status "Node started successfully with new version"
else
    print_error "Failed to start node with new version"
    print_status "Restoring previous configuration..."
    mv .env.backup .env
    docker compose up -d
    exit 1
fi

# Step 5: Verify the update
print_status "Waiting for node to start..."
sleep 10

# Check if container is running
if docker compose ps | grep -q "Up"; then
    print_status "✅ Update completed successfully!"
    echo "  Updated from: $current_tag"
    echo "  Updated to: $NEW_TAG"
    echo ""
    print_status "Next steps:"
    echo "  - Check node status and version: ./health-check.sh"
    echo "  - View logs: docker compose logs -f"
    echo "  - Monitor sync progress in the logs"
    
    # Clean up backup on success
    rm -f .env.backup
    
else
    print_error "Update failed - container is not running"
    print_status "Restoring previous configuration..."
    mv .env.backup .env
    docker compose up -d
    exit 1
fi
