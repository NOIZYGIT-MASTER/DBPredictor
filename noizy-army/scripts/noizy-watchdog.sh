#!/usr/bin/env bash
# NOIZYARMY WATCHDOG — 24/7/365 process supervisor
set -euo pipefail

ARMY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$HOME/.noizyarmy/logs"
RECEIPTS="$ARMY_ROOT/noizy-audio-rag/mc96/receipts.log"
INTERVAL="${NOIZY_WATCHDOG_INTERVAL:-300}"  # 5 min default

mkdir -p "$LOG_DIR"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] [WATCHDOG] $*" | tee -a "$LOG_DIR/watchdog.log"; }
receipt() { printf '{"receipt_id":"%s","verb":"%s","timestamp":"%s","operator":"WATCHDOG"}\n' \
  "$(printf '%s' "$1:$(ts)" | shasum -a 256 | cut -c1-24)" "$1" "$(ts)" >> "$RECEIPTS"; }

check_ollama() {
  if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    log "ollama: OK"
  else
    log "ollama: DOWN — restarting"
    ollama serve >> "$LOG_DIR/ollama.log" 2>&1 &
    sleep 3
    receipt "ollama_restart"
  fi
}

check_n8n() {
  if curl -sf http://127.0.0.1:5678/healthz >/dev/null 2>&1; then
    log "n8n: OK"
  else
    log "n8n: DOWN — attempting restart"
    receipt "n8n_down_detected"
  fi
}

nightly_capacity() {
  local hour
  hour=$(date +%H)
  local marker="$LOG_DIR/.capacity_$(date +%Y%m%d)"
  if [[ "$hour" -eq 3 && ! -f "$marker" ]]; then
    log "Running nightly capacity report"
    (cd "$ARMY_ROOT" && ./scripts/noizy-capacity-report.sh >> "$LOG_DIR/capacity_$(date +%Y%m%d).log" 2>&1)
    touch "$marker"
    receipt "nightly_capacity_report"
  fi
}

nightly_scan() {
  local hour
  hour=$(date +%H)
  local marker="$LOG_DIR/.scan_$(date +%Y%m%d)"
  if [[ "$hour" -eq 4 && ! -f "$marker" ]]; then
    log "Running nightly inventory scan"
    local input="${NOIZY_INPUT_PATH:-/NOIZY/raw_stems}"
    [[ -d "$input" ]] && (cd "$ARMY_ROOT" && ./noizy scan --input "$input" >> "$LOG_DIR/scan_$(date +%Y%m%d).log" 2>&1) || true
    touch "$marker"
    receipt "nightly_scan"
  fi
}

log "NOIZYARMY WATCHDOG STARTED — interval=${INTERVAL}s"
receipt "watchdog_start"

while true; do
  check_ollama
  check_n8n
  nightly_capacity
  nightly_scan
  log "Heartbeat OK — sleeping ${INTERVAL}s"
  receipt "heartbeat"
  sleep "$INTERVAL"
done
