#!/usr/bin/env bash
# GABRIEL TURBO SCAN — parallel multi-volume grep+inventory engine
# Scans all NOIZY volumes, classifies commercial vs personal, feeds Papyrus
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$HOME/.noizyarmy/logs"
PAPYRUS_DB="${PAPYRUS_DB:-$ROOT_DIR/noizy-audio-rag/papyrus/papyrus.db}"
RECEIPTS="$ROOT_DIR/noizy-audio-rag/mc96/receipts.log"
SCAN_OUT="${GABRIEL_SCAN_OUT:-$LOG_DIR/gabriel_scan_$(date +%Y%m%d_%H%M%S).json}"
MAX_DEPTH="${GABRIEL_MAX_DEPTH:-4}"
CANARY="${GABRIEL_CANARY:-0}"        # 0 = unlimited
DRY_RUN="${GABRIEL_DRY_RUN:-false}"

mkdir -p "$LOG_DIR"
ts()      { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log()     { echo "[$(ts)] [GABRIEL] $*" | tee -a "$LOG_DIR/gabriel.log"; }
receipt() { printf '{"receipt_id":"%s","verb":"gabriel_%s","timestamp":"%s","operator":"GABRIEL"}\n' \
              "$(printf '%s' "$1:$(ts)" | shasum -a 256 | cut -c1-24)" "$1" "$(ts)" >> "$RECEIPTS"; }

# ── CANONICAL VOLUME PATHS ──────────────────────────────────────────────────
declare -a COMMERCIAL_PATHS=(
  "/Volumes/12TB/_02.Instruments"
  "/Volumes/12TB/AUDIO_SFX_LIBRARY"
  "/Volumes/12TB/_Spectrasonics_3rd_Party"
  "/Volumes/12TB/_WAVE"
  "/Volumes/4TB Lacie/SAMPLES"
  "/Volumes/MAG 4TB/01_Drums"
  "/Volumes/MAG 4TB/02_EastWest"
  "/Volumes/NOIZY_POOL_A/NOIZY_SAMPLE_MASTER"
  "/Volumes/NOIZY_POOL_A/_ORGANIZED"
  "/Volumes/Hollywood Orchestra Mac/Play Libraries"
)
declare -a PERSONAL_PATHS=(
  "/Volumes/4TB Lacie/RSP_ORIGINAL_WORK"
  "/Volumes/4TB Lacie/FISH_MUSIC"
  "/Volumes/4TB Lacie/MISSION_CONTROL_96"
  "/Volumes/2TB_SGW/RSP_ORIGINAL_WORK"
  "/Volumes/2TB_SGW/FISH_MUSIC"
  "/Volumes/2TB_SGW/MISSION_CONTROL_96"
  "/Volumes/12TB/_01.AUDIO FROM ALL"
  "/Volumes/12TB/NOIZYLAB_ARCHIVES"
  "/Volumes/12TB/NOIZYLAB"
  "/Volumes/12TB/_NOIZY.AI"
  "/Volumes/12TB/MissionControl96"
  "/Volumes/3TB-GRF/MC96ECOUNIVERSE"
  "/Volumes/NOIZY_POOL_A/NOIZY_CLOUD_CONSOLIDATION"
  "/Volumes/NOIZY_POOL_A/THEAQUARIUM"
  "/Volumes/MAG 4TB/NOIZYFISH_THE_AQAURIUM"
  "/Volumes/NOIZY_POOL_B/FOR SORTING"
)

# ── COMMERCIAL LIBRARY GREP PATTERNS ───────────────────────────────────────
declare -a VENDOR_PATTERNS=(
  "Native.Instruments\|Kontakt\|Reaktor\|Battery\|Massive\|Komplete"
  "Spectrasonics\|Omnisphere\|Trilian\|Stylus"
  "EastWest\|EWQL\|Hollywood\|Quantum"
  "Toontrack\|EZDrummer\|Superior.Drummer\|EZkeys"
  "Spitfire\|LABS\|BBCSO\|Albion"
  "8Dio\|Adagio\|Anthology"
  "Cymatics\|Nexus\|KSHMR"
  "Loopmasters\|Splice\|Landr"
  "Boom.Library\|Sound.Ideas\|Soundsnap"
  "Best.Service\|Engine.Player"
  "Heavyocity\|Damage\|Gravity"
  "Output\|Arcade\|Exhaust\|Movement"
  "ProjectSAM\|Cinesamples\|CinePerc"
  "Air.Music\|Velvet\|Hybrid"
  "Arturia\|V.Collection\|Pigments"
  "Waves\|SSL\|Abbey.Road"
  "iZotope\|RX\|Ozone\|Neutron"
  "FabFilter\|Pro.Q\|Pro.MB"
)

# ── PERSONAL CATALOG GREP PATTERNS ─────────────────────────────────────────
declare -a PERSONAL_PATTERNS=(
  "[Ff][Ii][Ss][Hh]\|NOIZY\|RSP\|rob_\|ROB_"
  "NOIZYLAB\|NOIZYFISH\|MC96\|MissionControl"
  "[Vv]oice\|[Vv]ocal\|ROB_VOICE\|voice_dna"
  "[Ss]tem\|[Mm]aster\|[Ff]inal.[Mm]ix\|FINAL"
  "[Ss]ession\|\.als$\|\.ptx$\|\.logicx\|\.band$"
  "[Dd]emo\|[Ww][Ii][Pp]\|work.in.progress"
  "19[89][0-9]\|200[0-9]\|201[0-9]\|202[0-9]"
)

# ── SCAN A SINGLE PATH ──────────────────────────────────────────────────────
scan_path() {
  local base_path="$1"
  local category="$2"   # COMMERCIAL | PERSONAL
  [[ -d "$base_path" ]] || { echo "{\"path\":\"$base_path\",\"status\":\"NOT_MOUNTED\"}"; return; }

  local file_count
  file_count=$(find "$base_path" -maxdepth "$MAX_DEPTH" -type f 2>/dev/null | wc -l | tr -d ' ')

  local dir_count
  dir_count=$(find "$base_path" -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')

  local size_bytes
  size_bytes=$(du -sb "$base_path" 2>/dev/null | awk '{print $1}' || echo 0)

  # Audio file breakdown
  local wav_count nki_count aiff_count mp3_count other_count
  wav_count=$(find  "$base_path" -maxdepth "$MAX_DEPTH" -iname "*.wav"  2>/dev/null | wc -l | tr -d ' ')
  aiff_count=$(find "$base_path" -maxdepth "$MAX_DEPTH" -iname "*.aif"  -o -iname "*.aiff" 2>/dev/null | wc -l | tr -d ' ')
  nki_count=$(find  "$base_path" -maxdepth "$MAX_DEPTH" -iname "*.nki"  -o -iname "*.nkx"  2>/dev/null | wc -l | tr -d ' ')
  mp3_count=$(find  "$base_path" -maxdepth "$MAX_DEPTH" -iname "*.mp3"  2>/dev/null | wc -l | tr -d ' ')

  # Top-level dirs (library structure map)
  local top_dirs
  top_dirs=$(ls -1 "$base_path" 2>/dev/null | head -30 | python3 -c "
import sys,json
lines=[l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
" 2>/dev/null || echo "[]")

  # Vendor grep
  local vendors_found="[]"
  if [[ "$category" == "COMMERCIAL" ]]; then
    vendors_found=$(ls -1R "$base_path" 2>/dev/null | grep -iE \
      "Native.Instruments|Kontakt|Spectrasonics|Omnisphere|EastWest|Hollywood|Toontrack|EZDrummer|Spitfire|8Dio|Cymatics|Loopmasters|Boom.Library|Heavyocity|Output|Arturia|Waves|iZotope|FabFilter|Best.Service|Air.Music|Auddict|Audiomodern|ProjectSAM|Cinesamples" \
      2>/dev/null | sort -u | head -40 | python3 -c "
import sys,json
lines=[l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
" 2>/dev/null || echo "[]")
  fi

  # Personal catalog grep
  local eras_found="[]"
  if [[ "$category" == "PERSONAL" ]]; then
    eras_found=$(find "$base_path" -maxdepth 3 -type d 2>/dev/null | \
      grep -iE "198[0-9]|199[0-9]|200[0-9]|201[0-9]|202[0-9]" 2>/dev/null | \
      sort | head -20 | python3 -c "
import sys,json
lines=[l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
" 2>/dev/null || echo "[]")
  fi

  python3 - <<PYEOF
import json
print(json.dumps({
    "path": "$base_path",
    "category": "$category",
    "status": "SCANNED",
    "file_count": $file_count,
    "dir_count": $dir_count,
    "size_bytes": $size_bytes,
    "formats": {"wav": $wav_count, "aiff": $aiff_count, "nki": $nki_count, "mp3": $mp3_count},
    "top_dirs": $top_dirs,
    "vendors_found": $vendors_found,
    "eras_found": $eras_found,
    "scanned_at": "$(ts)"
}))
PYEOF
}

# ── MAIN ────────────────────────────────────────────────────────────────────
log "GABRIEL TURBO SCAN STARTING — $(date)"
log "Output: $SCAN_OUT"
receipt "scan_start"

RESULTS="[]"
TOTAL_FILES=0
TOTAL_BYTES=0

run_category() {
  local label="$1"
  local category="$2"
  shift 2
  local paths=("$@")
  for p in "${paths[@]}"; do
    log "Scanning $category: $p"
    local result
    result=$(scan_path "$p" "$category")
    local fc
    fc=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_count',0))" 2>/dev/null || echo 0)
    local fb
    fb=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('size_bytes',0))" 2>/dev/null || echo 0)
    TOTAL_FILES=$(( TOTAL_FILES + fc ))
    TOTAL_BYTES=$(( TOTAL_BYTES + fb ))
    RESULTS=$(python3 -c "
import sys,json
results=json.loads(sys.argv[1])
new=json.loads(sys.argv[2])
results.append(new)
print(json.dumps(results))
" "$RESULTS" "$result" 2>/dev/null || echo "$RESULTS")
    log "  -> $fc files, $(echo $fb | python3 -c 'import sys; b=int(sys.stdin.read()); print(f\"{b/1e9:.2f}GB\")')"
  done
}

run_category "commercial" "COMMERCIAL" "${COMMERCIAL_PATHS[@]}"
run_category "personal"   "PERSONAL"   "${PERSONAL_PATHS[@]}"

# Write manifest
python3 - <<PYEOF
import json, sys
manifest = {
    "scan_id": "gabriel_$(date +%Y%m%d_%H%M%S)",
    "generated": "$(ts)",
    "operator": "GABRIEL",
    "total_files": $TOTAL_FILES,
    "total_bytes": $TOTAL_BYTES,
    "total_gb": round($TOTAL_BYTES / 1e9, 2),
    "results": $RESULTS
}
with open("$SCAN_OUT", "w") as f:
    json.dump(manifest, f, indent=2)
print(f"Manifest written: $SCAN_OUT")
print(f"Total files scanned: {manifest['total_files']:,}")
print(f"Total data: {manifest['total_gb']:.1f} GB")
PYEOF

receipt "scan_complete"
log "GABRIEL TURBO SCAN COMPLETE — output: $SCAN_OUT"
echo
echo ">> Full manifest: $SCAN_OUT"
