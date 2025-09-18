#!/bin/bash
# Flare Node Docker Compose Setup Script
# Creates necessary directories and basic setup

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

print_status "Setting up Flare node directories..."

# Check for command line argument (for non-interactive mode)
config_choice=""
if [ $# -gt 0 ]; then
    config_choice="$1"
    print_status "Non-interactive mode: using config choice $config_choice"
fi

# Check if .env file exists
if [ ! -f .env ]; then
    if [ -f env.example ]; then
        print_status "Copying env.example to .env"
        cp env.example .env
        print_warning "Please edit .env file with your configuration before starting the node"
    else
        print_error ".env file not found and no env.example available"
        exit 1
    fi
fi

# Create directories under /opt/flare
print_status "Creating directories under /opt/flare..."
sudo mkdir -p /opt/flare/configs /opt/flare/logs /opt/flare/staking

# Interactive config selection (only if not provided as argument)
if [ -z "$config_choice" ]; then
    print_status "Please select a configuration:"
    echo "  1) Observer (default - pruning enabled)"
    echo "  2) Validator (pruning enabled, limited APIs)"
    echo "  3) Archival (no pruning, full history)"
    echo ""
    read -p "Enter your choice (1-3) [default: 1]: " config_choice
fi

# Set default if no input
config_choice=${config_choice:-1}

# Copy the selected configuration
case $config_choice in
    1)
        if [ -f configs/config.json.observer ]; then
            sudo cp configs/config.json.observer /opt/flare/configs/config.json
            print_status "Observer configuration selected and copied to /opt/flare/configs/config.json"
        else
            print_error "Observer config template not found"
            exit 1
        fi
        ;;
    2)
        if [ -f configs/config.json.validator ]; then
            sudo cp configs/config.json.validator /opt/flare/configs/config.json
            print_status "Validator configuration selected and copied to /opt/flare/configs/config.json"
            print_warning "For validators, ensure you place staker.crt, staker.key, and signer.key in /opt/flare/staking/"
            print_warning "Also add validator staking arguments to EXTRA_ARGUMENTS in .env file"
        else
            print_error "Validator config template not found"
            exit 1
        fi
        ;;
    3)
        if [ -f configs/config.json.archival ]; then
            sudo cp configs/config.json.archival /opt/flare/configs/config.json
            print_status "Archival configuration selected and copied to /opt/flare/configs/config.json"
            print_warning "Archival nodes require significantly more disk space and sync time"
        else
            print_error "Archival config template not found"
            exit 1
        fi
        ;;
    *)
        print_error "Invalid choice. Please select 1, 2, or 3"
        exit 1
        ;;
esac

# Set basic permissions (optional but recommended)
if command -v docker &> /dev/null; then
    current_user=$(whoami)
    
    print_status "Setting up Docker permissions..."
    echo "This will:"
    echo "  - Add your user to docker group (avoids needing sudo for docker commands)"
    echo "  - Set proper ownership on /opt/flare directories"
    echo ""
    read -p "Configure Docker permissions? (Y/n): " setup_perms
    setup_perms=${setup_perms:-Y}
    
    if [[ "$setup_perms" =~ ^[Yy]$ ]]; then
        # Ensure user is in docker group
        if ! groups | grep -q docker; then
            print_status "Adding user to docker group (may require logout/login)"
            sudo usermod -aG docker "$current_user"
        fi
        
        # Set ownership on directories
        sudo chown -R "${current_user}:docker" /opt/flare
        sudo chmod -R g+rwX /opt/flare
        print_status "Docker permissions configured"
    else
        print_warning "Skipped Docker permissions setup"
        print_warning "You'll need to use 'sudo docker compose' commands"
    fi
else
    print_warning "Docker not found. Please install Docker before proceeding."
fi

print_status "Setup completed!"
print_status "Selected configuration has been copied to /opt/flare/configs/config.json"
print_status "Next steps:"
echo "  1. Edit .env file with your configuration (network, version, db path, etc.)"
if [ "$config_choice" = "2" ]; then
    echo "  2. (Optional) Place validator certificates in /opt/flare/staking/ (staker.crt, staker.key, signer.key)"
    echo "  3. (Optional) Review config.json in /opt/flare/configs/config.json"
    echo "  4. Add staking arguments to EXTRA_ARGUMENTS in .env:"
    echo "     EXTRA_ARGUMENTS=\"--staking-tls-cert-file=/app/staking/staker.crt --staking-tls-key-file=/app/staking/staker.key --staking-signer-key-file=/app/staking/signer.key\""
    echo "  5. Start the node: docker compose up -d"
    echo "  6. Check status: ./health-check.sh"
else
    echo "  2. (Optional) Review config.json in /opt/flare/configs/config.json"
    echo "  3. Start the node: docker compose up -d"
    echo "  4. Check status: ./health-check.sh"
fi
echo ""
print_status "Created directories:"
echo "  - /opt/flare/configs/ (node configuration)"
echo "  - /opt/flare/logs/ (node logs)"
echo "  - /opt/flare/staking/ (validator certificates)"
echo ""
print_status "Usage: ./setup.sh [1|2|3] (optional: 1=observer, 2=validator, 3=archival)"
