#!/usr/bin/env bash
# NOIZY MCP GATEWAY — keeps all MCP servers alive and routes requests
set -euo pipefail

LOG_DIR="$HOME/.noizyarmy/logs"
mkdir -p "$LOG_DIR"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [MCP-GW] $*" | tee -a "$LOG_DIR/mcp-gateway.log"; }

# MCP servers to keep alive
declare -A MCP_SERVERS=(
  ["firebase"]="npx -y firebase-tools@latest mcp --only firestore,storage"
  ["desktop-commander"]="npx -y @desktop-commander/mcp-server"
)

start_mcp() {
  local name="$1"
  local cmd="${MCP_SERVERS[$name]}"
  local pidfile="$LOG_DIR/mcp-$name.pid"

  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    log "$name: already running (pid $(cat $pidfile))"
    return
  fi

  log "$name: starting — $cmd"
  eval "$cmd >> $LOG_DIR/mcp-$name.log 2>&1 &"
  echo $! > "$pidfile"
  log "$name: started (pid $!)"
}

stop_mcp() {
  local name="$1"
  local pidfile="$LOG_DIR/mcp-$name.pid"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid=$(cat "$pidfile")
    kill "$pid" 2>/dev/null && log "$name: stopped" || log "$name: already dead"
    rm -f "$pidfile"
  fi
}

case "${1:-start}" in
  start)
    log "Starting all MCP servers"
    for srv in "${!MCP_SERVERS[@]}"; do start_mcp "$srv"; done
    log "All MCP servers started"
    ;;
  stop)
    for srv in "${!MCP_SERVERS[@]}"; do stop_mcp "$srv"; done
    ;;
  status)
    for srv in "${!MCP_SERVERS[@]}"; do
      local pidfile="$LOG_DIR/mcp-$srv.pid"
      if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        echo "  $srv: RUNNING (pid $(cat $pidfile))"
      else
        echo "  $srv: DOWN"
      fi
    done
    ;;
  restart)
    for srv in "${!MCP_SERVERS[@]}"; do stop_mcp "$srv"; done
    sleep 2
    for srv in "${!MCP_SERVERS[@]}"; do start_mcp "$srv"; done
    ;;
esac
