#!/bin/bash
# Docker Installation Script
# Installs Docker using the official Docker apt repository (safest method)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}[DOCKER INSTALL]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please run this script as a regular user, not root"
    print_error "The script will use sudo when needed"
    exit 1
fi

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    docker_version=$(docker --version 2>/dev/null || echo "unknown")
    print_warning "Docker is already installed: $docker_version"
    read -p "Reinstall Docker? (y/N): " reinstall
    if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled"
        exit 0
    fi
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    print_error "Cannot detect OS. This script supports Ubuntu/Debian systems."
    exit 1
fi

# Check for supported OS
case "$OS" in
    ubuntu|debian)
        print_status "Detected: $PRETTY_NAME"
        ;;
    *)
        print_error "Unsupported OS: $OS"
        print_error "This script supports Ubuntu and Debian systems only"
        exit 1
        ;;
esac

print_header "Docker Installation using Official Repository"
echo "This script will:"
echo "  1. Update package manager"
echo "  2. Install required dependencies" 
echo "  3. Add Docker's official GPG key"
echo "  4. Add Docker apt repository"
echo "  5. Install Docker CE"
echo "  6. Start and enable Docker service"
echo ""
print_warning "This requires sudo privileges"
print_warning "Docker group setup will be handled by setup.sh"
echo ""

read -p "Continue with Docker installation? (Y/n): " confirm
confirm=${confirm:-Y}

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_status "Installation cancelled"
    exit 0
fi

print_status "Starting Docker installation..."

# Step 1: Update package manager
print_status "Updating package manager..."
sudo apt-get update

# Step 2: Install prerequisites
print_status "Installing required dependencies..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Step 3: Add Docker's official GPG key
print_status "Adding Docker's official GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Step 4: Set up the repository
print_status "Adding Docker apt repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Step 5: Update apt again and install Docker
print_status "Updating package lists with Docker repository..."
sudo apt-get update

print_status "Installing Docker CE..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker compose-plugin

# Step 6: Start and enable Docker
print_status "Starting and enabling Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

# Step 7: Docker group handling removed (will be handled by setup.sh if needed)

# Step 8: Verify installation
print_status "Verifying Docker installation..."
if sudo docker run --rm hello-world &>/dev/null; then
    print_status "✅ Docker installation completed successfully!"
    
    docker_version=$(docker --version)
    compose_version=$(docker compose version)
    
    echo ""
    print_header "Installation Summary"
    echo "  Docker: $docker_version"
    echo "  Compose: $compose_version"
    echo "  Service: Started and enabled"
    echo ""
    
    print_status "Next steps:"
    echo "  1. Run Flare node setup: ./setup.sh"
    echo "  2. Setup script will handle Docker permissions if needed"
    echo "  3. Test with: sudo docker run hello-world (until permissions configured)"
    
else
    print_error "Docker installation verification failed"
    exit 1
fi
