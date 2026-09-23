#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

ACTION="${1:-status}"
TARGET="${2:-all}"

# Resolve tunnel index from name
tunnel_index() {
    local name="$1"
    for i in "${!TUNNEL_NAMES[@]}"; do
        [[ "${TUNNEL_NAMES[$i]}" == "$name" ]] && echo "$i" && return
    done
    echo "ERROR: Unknown tunnel '${name}'" >&2
    exit 1
}

# Check if a tunnel's proxy process is running
is_running() {
    local name="$1"
    local pf
    pf="$(pid_file "$name")"
    if [[ -f "$pf" ]]; then
        local pid
        pid=$(cat "$pf")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Stale PID file — clean up
            rm -f "$pf"
        fi
    fi
    return 1
}

# Start a tunnel
start_tunnel() {
    local name="$1"
    if is_running "$name"; then
        return 0
    fi

    local idx
    idx=$(tunnel_index "$name")
    local instance="${TUNNEL_INSTANCES[$idx]}"
    local port="${TUNNEL_PORTS[$idx]}"
    local pf lf
    pf="$(pid_file "$name")"
    lf="$(log_file "$name")"

    mkdir -p "${STATE_DIR}/sql"

    nohup "$PROXY_BINARY" --address 127.0.0.1 --port "$port" "$instance" \
        > "$lf" 2>&1 &
    local pid=$!
    echo "$pid" > "$pf"

    # Verify the process started successfully
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pf"
        notify-send "Tunnel Toggle" "Failed to start ${name} tunnel. Check logs." 2>/dev/null || true
        return 1
    fi
}

# Stop a tunnel
stop_tunnel() {
    local name="$1"
    local pf
    pf="$(pid_file "$name")"
    if [[ -f "$pf" ]]; then
        local pid
        pid=$(cat "$pf")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            # Wait for graceful shutdown
            for _ in {1..10}; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.2
            done
            # Force kill if still alive
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$pf"
    fi
}

# Toggle a tunnel on/off
toggle_tunnel() {
    local name="$1"
    if is_running "$name"; then
        stop_tunnel "$name"
    else
        start_tunnel "$name"
    fi
}

# Copy connection string to clipboard
copy_connection() {
    local name="$1"
    local idx
    idx=$(tunnel_index "$name")
    local port="${TUNNEL_PORTS[$idx]}"
    local conn="mysql -h 127.0.0.1 -P ${port}"
    echo "$conn" | { xclip -selection clipboard 2>/dev/null || wl-copy 2>/dev/null; } || echo "$conn"
}

# Run an action on one or all tunnels
run_on_targets() {
    local action="$1"
    local target="$2"
    if [[ "$target" == "all" ]]; then
        for name in "${TUNNEL_NAMES[@]}"; do
            "$action" "$name"
        done
    else
        "$action" "$target"
    fi
}

case "$ACTION" in
    start)  run_on_targets start_tunnel "$TARGET" ;;
    stop)   run_on_targets stop_tunnel "$TARGET" ;;
    toggle) run_on_targets toggle_tunnel "$TARGET" ;;
    copy)   copy_connection "$TARGET" ;;
    status)
        for name in "${TUNNEL_NAMES[@]}"; do
            if is_running "$name"; then
                echo "${name}:running"
            else
                echo "${name}:stopped"
            fi
        done
        ;;
    *)
        names=$(IFS="|"; echo "${TUNNEL_NAMES[*]}")
        echo "Usage: $0 <start|stop|toggle|status|copy> <${names}|all>" >&2
        exit 1
        ;;
esac
