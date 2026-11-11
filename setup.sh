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

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"
# shellcheck source=staking-identity.sh
source "$SCRIPT_DIR/staking-identity.sh"

usage() {
    echo "Usage: ./setup.sh [--tag go-flare:v1.15.1] [--new-validator] [observer|validator|1|2] [public|private]"
    echo "  Validators use the web3-only template."
    echo "  Observers choose public (default) or private."
    echo "  --tag sets NODE_TAG. Without it, an existing NODE_TAG is left unchanged."
    echo "  --new-validator allows a first start to create a staking identity."
    echo "  A validator with no staking files is treated as a restore unless --new-validator is set."
}

node_type=""
template_choice=""
node_type_explicit=0
template_explicit=0
requested_tag=""
new_validator=0
positionals=()

while [ $# -gt 0 ]; do
    case "$1" in
        --tag)
            if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
                print_error "Missing value after --tag"
                usage
                exit 1
            fi
            requested_tag="$2"
            shift 2
            ;;
        --tag=*)
            requested_tag="${1#--tag=}"
            if [ -z "$requested_tag" ]; then
                print_error "Missing value after --tag="
                usage
                exit 1
            fi
            shift
            ;;
        --new-validator)
            new_validator=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            positionals+=("$@")
            break
            ;;
        -*)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            positionals+=("$1")
            shift
            ;;
    esac
done

if [ "${#positionals[@]}" -gt 2 ]; then
    print_error "Too many arguments"
    usage
    exit 1
fi

print_status "Setting up Flare node directories..."

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

normalize_node_type() {
    case "$1" in
        ""|1|observer)
            echo observer
            ;;
        2|validator)
            echo validator
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_template() {
    case "$1" in
        ""|1|public)
            echo public
            ;;
        2|private)
            echo private
            ;;
        *)
            return 1
            ;;
    esac
}

current_node_type=$(read_env NODE_TYPE)
current_tag=$(read_env NODE_TAG)

if [ "${#positionals[@]}" -ge 1 ]; then
    if node_type=$(normalize_node_type "${positionals[0]}"); then
        node_type_explicit=1
        if [ "${#positionals[@]}" -eq 2 ]; then
            if ! template_choice=$(normalize_template "${positionals[1]}"); then
                print_error "Invalid template \"${positionals[1]}\". Use public or private."
                exit 1
            fi
            template_explicit=1
        fi
    elif template_choice=$(normalize_template "${positionals[0]}"); then
        node_type="observer"
        node_type_explicit=1
        template_explicit=1
        if [ "${#positionals[@]}" -eq 2 ]; then
            print_error "Unexpected second argument \"${positionals[1]}\" after template \"${positionals[0]}\""
            usage
            exit 1
        fi
    else
        print_error "Invalid argument \"${positionals[0]}\". Use observer, validator, public, or private."
        exit 1
    fi
fi

if [ -z "$node_type" ]; then
    if [ -t 0 ]; then
        default_choice=1
        if [ "$current_node_type" = "validator" ]; then
            default_choice=2
        fi
        print_status "Please select a node type:"
        echo "  1) Observer"
        echo "  2) Validator"
        echo ""
        read -p "Enter your choice (1-2) [default: ${default_choice}]: " node_input
        if ! node_type=$(normalize_node_type "${node_input:-$default_choice}"); then
            print_error "Invalid choice. Please select 1 or 2"
            exit 1
        fi
        node_type_explicit=1
    else
        node_type=${current_node_type:-observer}
        print_status "No node type given and stdin is not a terminal. Leaving NODE_TYPE unchanged (${node_type})."
    fi
fi

# Validators always use the web3-only template. Observers choose public or private.
if [ "$node_type" = "validator" ]; then
    if [ -n "$template_choice" ] && [ "$template_choice" != "validator" ]; then
        print_warning "Validators always use the validator template. Ignoring \"${template_choice}\"."
    fi
    template_choice="validator"
    template_explicit=1
elif [ -z "$template_choice" ]; then
    if [ -t 0 ]; then
        print_status "Please select a config template:"
        echo "  1) Public (default)"
        echo "     APIs: avalanche, chain, net, price, subscription, tx, web3"
        echo "     api-max-duration 5s, batch-request-limit 100"
        echo "  2) Private"
        echo "     APIs: avalanche, chain, net, price, subscription, trace, tx, txpool, web3"
        echo "     api-max-duration 0s (no limit)"
        echo ""
        read -p "Enter your choice (1-2) [default: 1]: " template_input
        if ! template_choice=$(normalize_template "${template_input:-1}"); then
            print_error "Invalid choice. Please select 1 or 2"
            exit 1
        fi
        template_explicit=1
    elif [ "$node_type_explicit" -eq 1 ]; then
        template_choice="public"
        template_explicit=1
        print_status "No template given and stdin is not a terminal. Using the public template."
    fi
fi

if [ -n "$requested_tag" ]; then
    set_env_var NODE_TAG "$requested_tag"
    print_status "NODE_TAG set to ${requested_tag}"
elif [ -t 0 ] && { [ -z "$current_tag" ] || [ "$current_tag" = "go-flare:latest" ]; }; then
    echo "go-flare:latest on Docker Hub was last pushed on 2024-12-02 and does not include Helicon."
    echo "Enter a tag to run, for example go-flare:v1.15.1, or press Enter to keep go-flare:latest."
    read -p "Node image tag [${current_tag:-go-flare:latest}]: " tag_input
    if [ -n "$tag_input" ]; then
        set_env_var NODE_TAG "$tag_input"
        print_status "NODE_TAG set to ${tag_input}"
    else
        print_status "Keeping NODE_TAG at ${current_tag:-go-flare:latest}"
    fi
fi

# Create directories under /opt/flare
print_status "Creating directories under /opt/flare..."
sudo mkdir -p /opt/flare/configs /opt/flare/logs /opt/flare/staking

install_template=0
if [ "$template_explicit" -eq 1 ] || [ "$node_type_explicit" -eq 1 ]; then
    install_template=1
elif [ ! -f /opt/flare/configs/config.json ]; then
    install_template=1
    if [ "$node_type" = "validator" ]; then
        template_choice="validator"
    else
        template_choice=${template_choice:-public}
    fi
fi

allow_new_identity=0
refresh_staking_container
if [ "$node_type" = "validator" ] || { [ "$node_type_explicit" -eq 0 ] && deploy_is_validator; }; then
    salvage_staking_files
else
    salvage_staking_files || true
fi

if [ "$node_type" = "validator" ]; then
    if staking_files_complete; then
        allow_new_identity=0
        print_status "Staking identity is present in $STAKING_DIR"
    elif [ -n "$STAKING_CONTAINER_ID" ]; then
        print_restore_instructions
        print_error "Refusing to point this validator at an empty staking directory."
        exit 1
    elif [ "$new_validator" -eq 1 ]; then
        allow_new_identity=1
    elif [ -t 0 ]; then
        print_status "No staking identity was found in $STAKING_DIR, and there is no container to copy it from."
        echo "  1) Restore an existing validator (default)"
        echo "  2) Create a new validator identity on first start"
        echo ""
        read -p "Enter your choice (1-2) [default: 1]: " identity_choice
        identity_choice=${identity_choice:-1}
        case "$identity_choice" in
            1)
                print_restore_instructions
                exit 1
                ;;
            2)
                allow_new_identity=1
                ;;
            *)
                print_error "Invalid choice. Please select 1 or 2"
                exit 1
                ;;
        esac
    else
        print_restore_instructions
        exit 1
    fi
elif [ "$node_type_explicit" -eq 0 ] && deploy_is_validator; then
    if ! staking_files_complete; then
        print_restore_instructions
        print_error "Refusing to continue while this validator identity is incomplete."
        exit 1
    fi
fi

if [ "$node_type_explicit" -eq 1 ]; then
    set_env_var NODE_TYPE "$node_type"
    print_status "NODE_TYPE set to ${node_type}"
fi

if [ "$node_type" = "validator" ]; then
    if staking_files_complete || [ "$allow_new_identity" -eq 1 ]; then
        append_staking_flags
    fi
elif [ "$node_type_explicit" -eq 0 ] && deploy_is_validator && staking_files_complete; then
    append_staking_flags
fi

if [ "$install_template" -eq 1 ]; then
    template_file="configs/config.json.${template_choice}"
    if [ ! -f "$template_file" ]; then
        print_error "Config template not found: $template_file"
        exit 1
    fi
    sudo cp "$template_file" /opt/flare/configs/config.json
    if [ "$node_type" = "validator" ]; then
        print_status "Validator configuration copied to /opt/flare/configs/config.json"
    elif [ "$template_choice" = "public" ]; then
        print_status "Public configuration copied to /opt/flare/configs/config.json"
    else
        print_status "Private configuration copied to /opt/flare/configs/config.json"
    fi
else
    print_status "Leaving the existing /opt/flare/configs/config.json in place"
fi

# Set basic permissions (optional but recommended)
if command -v docker &> /dev/null; then
    if [ ! -t 0 ]; then
        print_status "No terminal attached. Leaving /opt/flare ownership unchanged."
    else
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

            # Set ownership on directories. Key files are locked again below.
            sudo chown -R "${current_user}:docker" /opt/flare
            sudo chmod -R g+rwX /opt/flare
            print_status "Docker permissions configured"
        else
            print_warning "Skipped Docker permissions setup"
            print_warning "You'll need to use 'sudo docker compose' commands"
        fi
    fi
else
    print_warning "Docker not found. Please install Docker before proceeding."
fi

lock_staking_key_modes

print_status "Setup completed!"
if [ "$install_template" -eq 1 ]; then
    print_status "Selected configuration has been copied to /opt/flare/configs/config.json"
fi
print_status "Next steps:"
echo "  1. Edit .env file with your configuration (network, db path, and other settings)"
if [ "$node_type" = "validator" ]; then
    if [ "$allow_new_identity" -eq 1 ]; then
        echo "  2. Start the node: docker compose up -d"
        echo "     The first start creates staker.crt, staker.key, and signer.key in $STAKING_DIR."
        echo "     Those files are the node identity. Back them up before any later move."
        echo "  3. Check status: ./health-check.sh"
    else
        echo "  2. Staking identity is in $STAKING_DIR (staker.crt, staker.key, signer.key)."
        echo "     staker.key and signer.key are mode 600. Do not replace these files."
        echo "  3. Start the node: docker compose up -d"
        echo "  4. Check status: ./health-check.sh"
    fi
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
usage
