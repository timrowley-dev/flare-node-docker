#!/bin/bash
# Check C-chain configs against the v1.15.1 (Helicon) rules that reject a node at startup.
# setup.sh installs the active file at /opt/flare/configs/config.json.

set -euo pipefail

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

CONFIG_DIR="/opt/flare/configs"
errors=0
warnings=0
files_checked=0

usage() {
    cat <<'EOF'
Usage: ./check-config.sh [--config-dir DIR]

Check C-chain config files for v1.15.1 (Helicon) values that stop the node
from starting.

The default directory is /opt/flare/configs, where setup.sh writes the active
config.json. The script checks config.json and any config.json.* templates
in that directory.

  -d, --config-dir DIR   Directory that holds the config files
  -h, --help             Show this help

Exit 0 when every file can start. Warnings (deprecated eth-apis, ignored
options) do not fail the check. Exit 1 when a value would be rejected.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--config-dir)
            if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
                print_error "Missing directory after $1"
                usage
                exit 1
            fi
            CONFIG_DIR="$2"
            shift 2
            ;;
        --config-dir=*)
            CONFIG_DIR="${1#--config-dir=}"
            if [ -z "$CONFIG_DIR" ]; then
                print_error "Missing directory after --config-dir="
                usage
                exit 1
            fi
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    print_error "jq is required but not installed"
    exit 1
fi

if [ ! -d "$CONFIG_DIR" ]; then
    print_error "Config directory not found: $CONFIG_DIR"
    echo "setup.sh installs the active config at /opt/flare/configs/config.json"
    exit 1
fi

# Go time.ParseDuration: optional sign, then one or more number+unit pairs.
# Units: ns, us, µs, μs, ms, s, m, h. "0" alone is not valid; "0s" is.
is_go_duration() {
    local value="$1"
    local num='([0-9]+(\.[0-9]*)?|\.[0-9]+)'
    local unit='(ns|us|µs|μs|ms|m|h|s)'
    [[ "$value" =~ ^[+-]?${num}${unit}(${num}${unit})*$ ]]
}

# Prints "ok <api>...", "removed", or "unknown". Always exits 0.
classify_legacy_api() {
    case "$1" in
        admin|debug|eth|internal-account|internal-personal)
            echo removed
            ;;
        debug-file-tracer|debug-tracer)
            echo "ok trace"
            ;;
        debug-handler)
            echo "ok profile"
            ;;
        eth-filter)
            echo "ok subscription"
            ;;
        internal-blockchain)
            echo "ok chain avalanche"
            ;;
        internal-debug)
            echo "ok db"
            ;;
        internal-eth)
            echo "ok price avalanche"
            ;;
        internal-transaction)
            echo "ok tx"
            ;;
        internal-tx-pool)
            echo "ok txpool"
            ;;
        net)
            echo "ok net"
            ;;
        web3)
            echo "ok web3"
            ;;
        *)
            echo unknown
            ;;
    esac
}

is_known_api() {
    case "$1" in
        web3|net|txpool|price|chain|tx|subscription|avalanche|trace|db|profile)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

join_words() {
    # shellcheck disable=SC2001
    echo "$1" | tr ' ' '\n' | sed '/^$/d' | sort -u | awk 'BEGIN{ORS=""} {if (NR>1) printf ", "; printf "%s", $0} END{if (NR>0) printf "\n"}'
}

note_error() {
    print_error "$1"
    errors=$((errors + 1))
}

note_warning() {
    print_warning "$1"
    warnings=$((warnings + 1))
}

check_api_max_duration() {
    local file="$1"
    local value_type value

    value_type=$(jq -r 'if has("api-max-duration") then .["api-max-duration"] | type else "absent" end' "$file")
    if [ "$value_type" = "absent" ]; then
        return 0
    fi

    if [ "$value_type" = "number" ]; then
        value=$(jq -r '.["api-max-duration"]' "$file")
        note_error "api-max-duration is a number ($value). v1.15.1 accepts only a duration string such as \"30s\". A number is rejected after Helicon activates and the node fails to start. Use \"0s\" for no limit, or remove the key to keep the default (no limit)."
        return 0
    fi

    if [ "$value_type" != "string" ]; then
        note_error "api-max-duration must be a duration string such as \"30s\" or \"0s\" (found $value_type)."
        return 0
    fi

    value=$(jq -r '.["api-max-duration"]' "$file")
    if ! is_go_duration "$value"; then
        note_error "api-max-duration \"$value\" is not a valid duration. Use a string such as \"30s\", \"2h45m\", or \"0s\" for no limit. Units: ns, us, ms, s, m, h."
    fi
}

check_commit_interval() {
    local file="$1"
    local value_type scheme

    value_type=$(jq -r 'if has("commit-interval") then .["commit-interval"] | type else "absent" end' "$file")
    if [ "$value_type" = "absent" ]; then
        return 0
    fi

    if [ "$value_type" != "number" ]; then
        note_error "commit-interval must be the number 4096 or be omitted (found $value_type). Production networks reject any other value."
        return 0
    fi

    if ! jq -e '.["commit-interval"] | (. == floor and . >= 0)' "$file" >/dev/null 2>&1; then
        note_error "commit-interval must be a non-negative integer. Production networks must use 4096, or omit the key."
        return 0
    fi

    if jq -e '.["commit-interval"] == 0' "$file" >/dev/null; then
        note_error "commit-interval is 0. The node does not accept an explicit 0. Omit the key to keep the default (4096)."
        return 0
    fi

    if jq -e '.["commit-interval"] == 4096' "$file" >/dev/null; then
        return 0
    fi

    scheme=$(jq -r 'if (.["state-scheme"] | type) == "string" then .["state-scheme"] else "hash" end' "$file")
    if [ "$scheme" = "firewood" ]; then
        note_warning "commit-interval is not 4096. That is allowed only with state-scheme \"firewood\". Confirm this node is meant to use Firewood."
        return 0
    fi

    note_error "commit-interval must be 4096 on production networks (HashDB). Omit the key to keep the default. The node fails to start with any other value."
}

# Sets list_status to absent, invalid, or ok. Does not print the status.
check_name_list() {
    local file="$1"
    local key="$2"
    local value_type bad

    value_type=$(jq -r --arg key "$key" 'if has($key) then .[$key] | type else "absent" end' "$file")
    if [ "$value_type" = "absent" ]; then
        list_status="absent"
        return 0
    fi
    if [ "$value_type" != "array" ]; then
        note_error "$key must be an array of strings (found $value_type)."
        list_status="invalid"
        return 0
    fi

    bad=$(jq -r --arg key "$key" '[.[$key][] | select(type != "string")] | length' "$file")
    if [ "$bad" != "0" ]; then
        note_error "$key must contain only strings."
        list_status="invalid"
        return 0
    fi

    list_status="ok"
}

check_eth_apis() {
    local file="$1"
    local name result kind mapped_words removed_words unknown_words
    local mapped_csv removed_csv unknown_csv

    check_name_list "$file" "eth-apis"
    if [ "$list_status" != "ok" ]; then
        return 0
    fi

    mapped_words=""
    removed_words=""
    unknown_words=""

    while IFS= read -r name; do
        if [ -z "$name" ]; then
            note_error "eth-apis contains an empty name."
            continue
        fi
        result=$(classify_legacy_api "$name")
        kind=${result%% *}
        case "$kind" in
            ok)
                mapped_words="$mapped_words ${result#ok }"
                ;;
            removed)
                removed_words="$removed_words $name"
                ;;
            *)
                unknown_words="$unknown_words $name"
                ;;
        esac
    done <<EOF
$(jq -r '.["eth-apis"][]' "$file")
EOF

    unknown_csv=$(join_words "$unknown_words")
    if [ -n "$unknown_csv" ]; then
        note_error "eth-apis has unknown names: $unknown_csv. An unknown name is a fatal configuration error."
    fi

    note_warning "eth-apis is deprecated and will be removed in the next release. Set \"apis\" instead."

    mapped_csv=$(join_words "$mapped_words")
    if [ -n "$mapped_csv" ]; then
        print_status "eth-apis maps to apis: $mapped_csv"
    else
        note_warning "eth-apis maps to no APIs, so the node would serve no C-chain RPC methods. Set \"apis\" to the methods you need."
    fi

    removed_csv=$(join_words "$removed_words")
    if [ -n "$removed_csv" ]; then
        note_warning "Ignoring eth-apis names whose methods no longer exist: $removed_csv"
    fi
}

check_apis() {
    local file="$1"
    local name unknown_words unknown_csv count

    check_name_list "$file" "apis"
    if [ "$list_status" != "ok" ]; then
        return 0
    fi

    unknown_words=""
    while IFS= read -r name; do
        if [ -z "$name" ]; then
            note_error "apis contains an empty name."
            continue
        fi
        if ! is_known_api "$name"; then
            unknown_words="$unknown_words $name"
        fi
    done <<EOF
$(jq -r '.apis[]' "$file")
EOF

    unknown_csv=$(join_words "$unknown_words")
    if [ -n "$unknown_csv" ]; then
        note_error "apis has unknown names: $unknown_csv. An unknown name is a fatal configuration error."
    fi

    count=$(jq -r '.apis | length' "$file")
    if [ "$count" = "0" ]; then
        note_warning "apis is empty, so the node would serve no C-chain RPC methods."
    fi
}

check_unrecognized() {
    local file="$1"
    local ignored

    ignored=$(jq -r --argjson known '["min-price-target","gas-target","min-delay-target","pruning-enabled","commit-interval","trie-clean-cache","snapshot-cache","allow-missing-tries","state-scheme","local-txs-enabled","tx-pool-account-slots","tx-pool-global-slots","apis","allow-unprotected-txs","batch-request-limit","api-max-duration","api-resolve-pending-to-last-executed","state-sync-enabled","warp-off-chain-messages","state-sync-ids","eth-apis"]' '
        [ keys[] | select(. as $k | ($known | index($k)) == null) ] | sort | join(", ")
    ' "$file")

    if [ -n "$ignored" ]; then
        note_warning "Ignoring unrecognized options (the node logs these and continues): $ignored"
    fi
}

check_file() {
    local file="$1"

    local parse_output

    echo
    print_status "Checking $file"
    files_checked=$((files_checked + 1))

    if ! parse_output=$(jq -e 'type == "object"' "$file" 2>&1); then
        note_error "Not a JSON object. The node rejects this file: $parse_output"
        return 0
    fi

    check_api_max_duration "$file"
    check_commit_interval "$file"
    check_eth_apis "$file"
    check_apis "$file"
    check_unrecognized "$file"
}

files=()
if [ -f "$CONFIG_DIR/config.json" ]; then
    files+=("$CONFIG_DIR/config.json")
fi
for config_file in "$CONFIG_DIR"/config.json.*; do
    if [ -f "$config_file" ]; then
        files+=("$config_file")
    fi
done

if [ "${#files[@]}" -eq 0 ]; then
    print_error "No config.json or config.json.* files in $CONFIG_DIR"
    exit 1
fi

print_status "Config directory: $CONFIG_DIR"

for config_file in "${files[@]}"; do
    check_file "$config_file"
done

echo
if [ "$errors" -gt 0 ]; then
    print_error "Checked $files_checked file(s): $errors error(s), $warnings warning(s)"
    exit 1
fi

print_status "Checked $files_checked file(s): $errors error(s), $warnings warning(s)"
exit 0
