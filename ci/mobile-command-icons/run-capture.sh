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
# Run with a dedicated disposable checkout: engine import can update .godot
# and .import bookkeeping within the supplied source directory.
timeout 150s "$GODOT" --headless --path "$SOURCE/game" --editor --import   >"$OUT/import.log" 2>&1
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 GALLIUM_DRIVER=softpipe MESA_GL_VERSION_OVERRIDE=3.3
for SPEC in '390 844' '844 390'; do
  read -r W H <<< "$SPEC"
  SIZE="${W}x${H}"
  timeout 150s xvfb-run -a -s '-screen 0 1280x1024x24' "$GODOT"     --path "$SOURCE/game" --resolution "$SIZE" --audio-driver Dummy     --rendering-method gl_compatibility --single-threaded-scene     --script "$HERE/capture-mobile-command-icons.gd" --     "$OUT/$SIZE" "$W" "$H" "$BUILD" "$GAME_SHA" "$ICONS_SHA"     >"$OUT/$SIZE.log" 2>&1
  python3 -B - "$OUT/$SIZE" "$W" "$H" "$BUILD" <<'PY'
import hashlib,json,struct,sys
from pathlib import Path
p=Path(sys.argv[1]); w,h=map(int,sys.argv[2:4]); build=sys.argv[4]
d=json.loads((p/'report.json').read_text())
assert d['result']=='RENDERED' and d['failed']==0 and d['png_count']==3
assert d['build']==build and d['size']==[w,h] and d['display']!='headless'
assert not d['metadata_only'] and d['renderer']=='gl_compatibility'
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
done
