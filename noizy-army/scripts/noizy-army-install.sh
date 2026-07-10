#!/usr/bin/env bash
# NOIZYARMY — one-command install (runs at login, auto-restarts, 24/7)
set -euo pipefail

REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
ARMY_PLISTS_DIR="$REPO_PATH/noizy-army/launchagents"

mkdir -p "$HOME/.noizyarmy/logs"
mkdir -p "$LAUNCH_AGENTS_DIR"

echo "== NOIZYARMY INSTALL =="
echo "repo: $REPO_PATH"

install_agent() {
  local template="$1"
  local label="$2"
  local dest="$LAUNCH_AGENTS_DIR/$label.plist"

  sed "s|REPLACE_WITH_REPO_PATH|$REPO_PATH|g" "$template" > "$dest"

  launchctl unload "$dest" 2>/dev/null || true
  launchctl load -w "$dest"
  echo "  LOADED: $label"
}

install_agent "$ARMY_PLISTS_DIR/com.noizy.watchdog.plist" "com.noizy.watchdog"
install_agent "$ARMY_PLISTS_DIR/com.noizy.ollama.plist"   "com.noizy.ollama"

echo
echo "== NOIZYARMY STATUS =="
launchctl list | grep noizy || echo "(no noizy agents running yet)"

echo
echo "Logs: $HOME/.noizyarmy/logs/"
echo "Done. NOIZYARMY is live 24/7/365."
