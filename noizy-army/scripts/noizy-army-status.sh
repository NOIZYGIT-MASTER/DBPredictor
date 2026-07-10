#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="$HOME/.noizyarmy/logs"
echo "== NOIZYARMY STATUS =="
echo
echo "-- LaunchAgents --"
launchctl list 2>/dev/null | grep -E "noizy|ollama" || echo "  none loaded"
echo
echo "-- Ollama --"
curl -sf http://127.0.0.1:11434/api/tags 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('  models:', [m['name'] for m in d.get('models',[])])" 2>/dev/null || echo "  offline"
echo
echo "-- Watchdog log (last 10) --"
[[ -f "$LOG_DIR/watchdog.log" ]] && tail -10 "$LOG_DIR/watchdog.log" || echo "  no log yet"
echo
echo "-- Receipts (last 5) --"
[[ -f "$LOG_DIR/../../../noizy-audio-rag/mc96/receipts.log" ]] && tail -5 "$LOG_DIR/../../../noizy-audio-rag/mc96/receipts.log" || true
