#!/bin/bash
# Shared staking-identity helpers for setup.sh and update.sh.
# Sourced by those scripts. Requires print_status, print_warning, and print_error.

STAKING_DIR="/opt/flare/staking"
STAKING_FILES="staker.crt staker.key signer.key"
STAKING_CONTAINER_ID=""
STAKING_CONTAINER_NAME=""

read_env() {
    local key="$1"
    local line
    if [ ! -f .env ]; then
        return 0
    fi
    line=$(grep -E "^${key}=" .env | tail -n 1 || true)
    printf '%s' "${line#"${key}"=}"
}

set_env_var() {
    local key="$1"
    local value="$2"
    local tmp
    tmp=$(mktemp)
    if [ -f .env ]; then
        awk -v k="$key" -v v="$value" '
            BEGIN { found = 0 }
            $0 ~ "^" k "=" { print k "=" v; found = 1; next }
            { print }
            END { if (!found) print k "=" v }
        ' .env > "$tmp"
    else
        printf '%s=%s\n' "$key" "$value" > "$tmp"
    fi
    mv "$tmp" .env
}

staking_files_complete() {
    local file
    for file in $STAKING_FILES; do
        if [ ! -s "$STAKING_DIR/$file" ]; then
            return 1
        fi
    done
    return 0
}

ensure_staking_dir() {
    if [ -d "$STAKING_DIR" ]; then
        return 0
    fi
    if mkdir -p "$STAKING_DIR" 2>/dev/null; then
        return 0
    fi
    sudo mkdir -p "$STAKING_DIR"
}

install_staking_file() {
    local src="$1"
    local dest="$2"
    if cp "$src" "$dest" 2>/dev/null; then
        return 0
    fi
    sudo cp "$src" "$dest"
}

lock_staking_key_modes() {
    local file dest
    for file in staker.key signer.key; do
        dest="$STAKING_DIR/$file"
        if [ -f "$dest" ]; then
            chmod 600 "$dest" 2>/dev/null || sudo chmod 600 "$dest"
        fi
    done
}

refresh_staking_container() {
    local ids
    STAKING_CONTAINER_ID=""
    STAKING_CONTAINER_NAME=""
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    ids=$(docker compose ps -aq flare-node 2>/dev/null || true)
    STAKING_CONTAINER_ID=${ids%%$'\n'*}
    if [ -n "$STAKING_CONTAINER_ID" ]; then
        STAKING_CONTAINER_NAME=$(docker inspect -f '{{.Name}}' "$STAKING_CONTAINER_ID" 2>/dev/null || true)
        STAKING_CONTAINER_NAME=${STAKING_CONTAINER_NAME#/}
    fi
}

# Keep a non-empty host file. Warn when the container has a different copy.
# Copy a missing file from the container home, then from the staking mount.
copy_staking_file_from_container() {
    local file="$1"
    local dest="$STAKING_DIR/$file"
    local path tmp found_diff=0

    if [ -z "$STAKING_CONTAINER_ID" ]; then
        return 1
    fi

    if [ -s "$dest" ]; then
        for path in "/root/.avalanchego/staking/$file" "/app/staking/$file"; do
            tmp=$(mktemp)
            if docker cp "$STAKING_CONTAINER_ID:$path" "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
                if ! cmp -s "$dest" "$tmp"; then
                    found_diff=1
                    print_warning "Keeping existing $dest. The container copy at $path is different."
                fi
            fi
            rm -f "$tmp"
            if [ "$found_diff" -eq 1 ]; then
                break
            fi
        done
        return 0
    fi

    for path in "/root/.avalanchego/staking/$file" "/app/staking/$file"; do
        tmp=$(mktemp)
        if docker cp "$STAKING_CONTAINER_ID:$path" "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            ensure_staking_dir
            install_staking_file "$tmp" "$dest"
            rm -f "$tmp"
            if [ "$file" = "staker.key" ] || [ "$file" = "signer.key" ]; then
                chmod 600 "$dest" 2>/dev/null || sudo chmod 600 "$dest"
            fi
            print_status "Copied $file from the container to $STAKING_DIR"
            return 0
        fi
        rm -f "$tmp"
    done
    return 1
}

salvage_staking_files() {
    local file
    ensure_staking_dir
    refresh_staking_container
    for file in $STAKING_FILES; do
        copy_staking_file_from_container "$file" || true
    done
    lock_staking_key_modes
}

deploy_is_validator() {
    local selected="${1:-}"
    local extra
    if [ "$selected" = "validator" ]; then
        return 0
    fi
    if [ "$(read_env NODE_TYPE)" = "validator" ]; then
        return 0
    fi
    extra=$(read_env EXTRA_ARGUMENTS)
    if [[ "$extra" == *"--staking-tls-cert-file="* ]] || [[ "$extra" == *"--staking-tls-key-file="* ]] || [[ "$extra" == *"--staking-signer-key-file="* ]]; then
        return 0
    fi
    if [[ "$STAKING_CONTAINER_NAME" == *-validator ]]; then
        return 0
    fi
    return 1
}

append_staking_flags() {
    local current name value
    current=$(read_env EXTRA_ARGUMENTS)
    for name in \
        --staking-tls-cert-file \
        --staking-tls-key-file \
        --staking-signer-key-file
    do
        case "$name" in
            --staking-tls-cert-file) value="/app/staking/staker.crt" ;;
            --staking-tls-key-file) value="/app/staking/staker.key" ;;
            --staking-signer-key-file) value="/app/staking/signer.key" ;;
        esac
        if [[ "$current" == *"${name}="* ]]; then
            continue
        fi
        if [ -z "$current" ]; then
            current="${name}=${value}"
        else
            current="${current} ${name}=${value}"
        fi
    done
    set_env_var EXTRA_ARGUMENTS "$current"
    print_status "Staking flags in EXTRA_ARGUMENTS point at /app/staking"
}

print_restore_instructions() {
    print_error "Validator staking files are not complete in $STAKING_DIR."
    echo "Copy these files from the existing validator before the node starts:"
    echo "  staker.crt"
    echo "  staker.key"
    echo "  signer.key"
    echo "Put them in $STAKING_DIR and run ./setup.sh validator again."
    echo "Starting without them creates a new node identity."
    echo "To create a new validator on purpose, run: ./setup.sh --new-validator validator"
}
