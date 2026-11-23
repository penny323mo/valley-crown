#!/usr/bin/env bash
# Test-only example for the existing authorized Linux/Xvfb capture runner.
set -euo pipefail
if [[ $# != 4 ]]; then
  echo "Usage: bash run-capture.sh REVIEWED_SOURCE_DIR GODOT_4_6_3_BINARY MANIFEST NEW_OUTPUT_DIR" >&2
  exit 2
fi
SOURCE="$(realpath "$1")"
GODOT="$(realpath "$2")"
MANIFEST="$(realpath "$3")"
OUT="$(realpath -m "$4")"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test -f "$SOURCE/game/project.godot"
test -x "$GODOT"
command -v xvfb-run >/dev/null
command -v xauth >/dev/null
ENGINE_SHA=f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3
[[ "$(sha256sum "$GODOT" | cut -d' ' -f1)" == "$ENGINE_SHA" ]] || { echo "Wrong pinned Godot 4.6.3 engine bytes" >&2; exit 2; }
readarray -t PINS < <(python3 -B - "$SOURCE" "$MANIFEST" "$HERE/capture-mobile-command-icons.gd" <<'PY'
import hashlib,json,sys
from pathlib import Path
source,manifest,fixture=map(Path,sys.argv[1:])
d=json.loads(manifest.read_text())
assert hashlib.sha256(fixture.read_bytes()).hexdigest()==d['fixture_sha256'], 'Wrong fixture bytes'
for rel, sha in d['source_files_sha256'].items():
 assert hashlib.sha256((source/rel).read_bytes()).hexdigest()==sha, rel
print(d['build'])
print(d['source_files_sha256']['game/scripts/game.gd'])
print(d['source_files_sha256']['game/scripts/command_icons.gd'])
PY
)
[[ ${#PINS[@]} == 3 ]] || { echo "Candidate or fixture identity rejected" >&2; exit 2; }
BUILD="${PINS[0]}" GAME_SHA="${PINS[1]}" ICONS_SHA="${PINS[2]}"
mkdir "$OUT"
STATE="$(mktemp -d)"
trap 'rm -rf -- "$STATE"' EXIT
export HOME="$STATE" XDG_DATA_HOME="$STATE/data" XDG_CONFIG_HOME="$STATE/config" XDG_CACHE_HOME="$STATE/cache"
log_stage() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$OUT/launcher.log"; }
# Run in a disposable checkout. Import writes only its local bookkeeping.
log_stage "import_begin build=$BUILD"
if timeout --kill-after=10s 150s "$GODOT" --headless --path "$SOURCE/game" --editor --import >"$OUT/import.log" 2>&1; then
  log_stage "import_ok"
else
  CODE=$?; log_stage "import_failed exit=$CODE"; tail -n 15 "$OUT/import.log"; exit "$CODE"
fi
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
RESULT=0
for SPEC in '390 844' '844 390'; do
  read -r W H <<< "$SPEC"
  SIZE="${W}x${H}"
  log_stage "capture_begin size=$SIZE driver=$GALLIUM_DRIVER threads=$LP_NUM_THREADS max_fps=30 timeout_s=220"
  START=$SECONDS
  if timeout --kill-after=12s 220s xvfb-run -a -s '-screen 0 1280x1024x24' \
    stdbuf -oL -eL "$GODOT" --path "$SOURCE/game" --resolution "$SIZE" --audio-driver Dummy \
    --rendering-method gl_compatibility --single-threaded-scene --disable-render-loop --max-fps 30 \
    --script "$HERE/capture-mobile-command-icons.gd" -- \
    "$OUT/$SIZE" "$W" "$H" "$BUILD" "$GAME_SHA" "$ICONS_SHA" >"$OUT/$SIZE.log" 2>&1; then
    log_stage "capture_process_ok size=$SIZE elapsed_s=$((SECONDS-START))"
  else
    CODE=$?
    log_stage "capture_process_failed size=$SIZE exit=$CODE elapsed_s=$((SECONDS-START))"
    if [[ -f "$OUT/$SIZE/progress.jsonl" ]]; then tail -n 6 "$OUT/$SIZE/progress.jsonl"; fi
    tail -n 18 "$OUT/$SIZE.log"
    if [[ "$RESULT" == 0 ]]; then RESULT=$CODE; fi
    continue
  fi
  if python3 -B - "$OUT/$SIZE" "$W" "$H" "$BUILD" <<'PY'
import hashlib,json,struct,sys
from pathlib import Path
p=Path(sys.argv[1]); w,h=map(int,sys.argv[2:4]); build=sys.argv[4]
d=json.loads((p/'report.json').read_text())
assert d['result']=='RENDERED' and d['failed']==0 and d['png_count']==3
assert d['build']==build and d['size']==[w,h] and d['display']!='headless'
assert not d['metadata_only'] and d['renderer']=='gl_compatibility'
assert 'llvmpipe' in d['video_adapter'].lower(), d['video_adapter']
expected=['01-house-confirm','02-paid-age-queue','03-paid-supply-queue']
assert [f['name'] for f in d['frames']]==expected
for f in d['frames']:
 assert f['file']==f['name']+'.png'
 data=(p/f['file']).read_bytes()
 assert data[:8]==b'\x89PNG\r\n\x1a\n' and data[12:16]==b'IHDR'
 assert struct.unpack('>II',data[16:24])==(w,h)
 assert hashlib.sha256(data).hexdigest()==f['sha256']
print(f'{w}x{h}: 3 authentic PNGs passed dimensions and SHA-256 checks')
PY
  then
    log_stage "capture_verified size=$SIZE"
  else
    CODE=$?; log_stage "capture_verify_failed size=$SIZE exit=$CODE"
    if [[ "$RESULT" == 0 ]]; then RESULT=$CODE; fi
  fi
done
log_stage "capture_final exit=$RESULT"
exit "$RESULT"
