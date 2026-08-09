#!/usr/bin/env bash
# Configuration for Tunnel Toggle
# Loads SQL and SSH tunnel definitions from tunnels.json

# Resolve script directory (works when sourced from any location)
if [[ -n "${SCRIPT_DIR:-}" ]]; then
    CONFIG_DIR="$SCRIPT_DIR"
elif [[ -n "${PROJECT_DIR:-}" ]]; then
    CONFIG_DIR="$PROJECT_DIR"
else
    CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CONFIG_FILE="${CONFIG_DIR}/tunnels.json"
STATE_DIR="${HOME}/.tunnel-toggle"

# --- Validate dependencies ---

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found. Install it with your package manager (brew install jq / apt install jq / pacman -S jq)." >&2
    exit 1
fi

# --- Load and validate JSON config ---

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}" >&2
    echo "       Copy tunnels.json.example to tunnels.json and edit it." >&2
    exit 1
fi

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "ERROR: Invalid JSON in ${CONFIG_FILE}" >&2
    echo "       Check for syntax errors (missing commas, brackets, quotes)." >&2
    exit 1
fi

# --- SQL Proxy tunnels ---

# Read proxy binary (default: auto-detect from PATH)
PROXY_BINARY=$(jq -r '.proxy_binary // empty' "$CONFIG_FILE")
if [[ -z "$PROXY_BINARY" ]]; then
    PROXY_BINARY=$(command -v cloud-sql-proxy 2>/dev/null || echo "")
fi

# Read tunnel count
tunnel_count=$(jq '.tunnels | length' "$CONFIG_FILE")

# Populate tunnel arrays from JSON
TUNNEL_NAMES=()
TUNNEL_LABELS=()
TUNNEL_INSTANCES=()
TUNNEL_PORTS=()

for ((i=0; i<tunnel_count; i++)); do
    name=$(jq -r ".tunnels[$i].name // empty" "$CONFIG_FILE")
    label=$(jq -r ".tunnels[$i].label // empty" "$CONFIG_FILE")
    instance=$(jq -r ".tunnels[$i].instance // empty" "$CONFIG_FILE")
    port=$(jq -r ".tunnels[$i].port // empty" "$CONFIG_FILE")

    # Validate required fields
    if [[ -z "$name" ]]; then
        echo "ERROR: Tunnel at index ${i} is missing 'name'" >&2
        exit 1
    fi
    if [[ -z "$instance" ]]; then
        echo "ERROR: Tunnel '${name}' is missing 'instance'" >&2
        exit 1
    fi
    if [[ -z "$port" ]]; then
        echo "ERROR: Tunnel '${name}' is missing 'port'" >&2
        exit 1
    fi

    # Default label to capitalized name
    if [[ -z "$label" ]]; then
        label="${name^}"
    fi

    # Check for duplicate names
    for existing in "${TUNNEL_NAMES[@]}"; do
        if [[ "$existing" == "$name" ]]; then
            echo "ERROR: Duplicate tunnel name '${name}'" >&2
            exit 1
        fi
    done

    # Check for duplicate ports
    for existing in "${TUNNEL_PORTS[@]}"; do
        if [[ "$existing" == "$port" ]]; then
            echo "ERROR: Duplicate port ${port} (tunnel '${name}')" >&2
            exit 1
        fi
    done

    TUNNEL_NAMES+=("$name")
    TUNNEL_LABELS+=("$label")
    TUNNEL_INSTANCES+=("$instance")
    TUNNEL_PORTS+=("$port")
done

# --- SSH Tunnels ---

ssh_tunnel_count=$(jq '.ssh_tunnels // [] | length' "$CONFIG_FILE")

SSH_NAMES=()
SSH_LABELS=()
SSH_FORWARDS=()
SSH_HOSTS=()
SSH_OPTS=()

for ((i=0; i<ssh_tunnel_count; i++)); do
    name=$(jq -r ".ssh_tunnels[$i].name // empty" "$CONFIG_FILE")
    label=$(jq -r ".ssh_tunnels[$i].label // empty" "$CONFIG_FILE")
    forward=$(jq -r ".ssh_tunnels[$i].forward // empty" "$CONFIG_FILE")
    host=$(jq -r ".ssh_tunnels[$i].host // empty" "$CONFIG_FILE")
    opts=$(jq -r ".ssh_tunnels[$i].opts // empty" "$CONFIG_FILE")

    # Validate required fields
    if [[ -z "$name" ]]; then
        echo "ERROR: SSH tunnel at index ${i} is missing 'name'" >&2
        exit 1
    fi
    if [[ -z "$forward" ]]; then
        echo "ERROR: SSH tunnel '${name}' is missing 'forward'" >&2
        exit 1
    fi
    if [[ -z "$host" ]]; then
        echo "ERROR: SSH tunnel '${name}' is missing 'host'" >&2
        exit 1
    fi

    # Default label to capitalized name
    if [[ -z "$label" ]]; then
        label="${name^}"
    fi

    # Check for duplicate names (across both SQL and SSH)
    for existing in "${TUNNEL_NAMES[@]}" "${SSH_NAMES[@]}"; do
        if [[ "$existing" == "$name" ]]; then
            echo "ERROR: Duplicate tunnel name '${name}'" >&2
            exit 1
        fi
    done

    SSH_NAMES+=("$name")
    SSH_LABELS+=("$label")
    SSH_FORWARDS+=("$forward")
    SSH_HOSTS+=("$host")
    SSH_OPTS+=("$opts")
done

# --- Path helpers ---

sql_pid_file() { echo "${STATE_DIR}/sql/${1}.pid"; }
sql_log_file() { echo "${STATE_DIR}/sql/${1}.log"; }
ssh_pid_file() { echo "${STATE_DIR}/ssh/${1}.pid"; }
ssh_log_file() { echo "${STATE_DIR}/ssh/${1}.log"; }

# Legacy aliases for proxy-ctl.sh compatibility
pid_file() { sql_pid_file "$1"; }
log_file() { sql_log_file "$1"; }
