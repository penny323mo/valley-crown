#!/usr/bin/env bash
# Exact stamped native A/B, no gameplay overlay or source edits in either role.
set -euo pipefail
[[ $# -ge 4 && $# -le 5 ]] || { echo 'Usage: run-map-edge-capture.sh EXACT_BASELINE_CHECKOUT EXACT_CANDIDATE_CHECKOUT PINNED_GODOT NEW_OUTPUT [--metadata-only]' >&2; exit 2; }
baseline="$(realpath "$1")"; candidate="$(realpath "$2")"; godot="$(realpath "$3")"; out="$(realpath -m "$4")"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode=RENDERED; args=()
if [[ $# = 5 ]]; then [[ $5 = --metadata-only ]]; mode=METADATA_ONLY; args=("$5"); fi
if [[ $mode = RENDERED ]]; then command -v xvfb-run >/dev/null; command -v xauth >/dev/null; fi
pin() { python3 -B - "$here/pins.json" "$@" <<'PY'
import json,sys
from pathlib import Path
v=json.loads(Path(sys.argv[1]).read_text())
for k in sys.argv[2:]:v=v[k]
print(v)
PY
}
chk() { [[ "$(sha256sum "$1"|cut -d' ' -f1)" == "$2" ]] || { echo "Hash mismatch: $1" >&2; exit 2; }; }
chk "$godot" "$(pin godot_linux_sha)"
chk "$here/capture-map-edge.gd" "$(pin fixture_sha)"
chk "$here/verify-map-edge.py" "$(pin verification_sha)"
work="$(mktemp -d)"; trap 'rm -rf -- "$work"' EXIT
mkdir "$out"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
for role in baseline candidate; do
    checkout="$baseline"; if [[ $role = candidate ]]; then checkout="$candidate"; fi
    source="$(pin "$role" source)"
    [[ "$(git -C "$checkout" rev-parse "$source")" = "$source" ]]
    [[ "$(git -C "$checkout" rev-parse "$source^{tree}")" = "$(pin "$role" tree)" ]]
    [[ "$(git -C "$checkout" rev-parse "$source:game")" = "$(pin "$role" game_tree)" ]]
    mkdir -p "$work/$role/source" "$work/$role/home"
    git -C "$checkout" archive "$source" game |tar -x -C "$work/$role/source"
    export HOME="$work/$role/home" XDG_DATA_HOME="$work/$role/home/data" XDG_CONFIG_HOME="$work/$role/home/config" XDG_CACHE_HOME="$work/$role/home/cache"
    game="$work/$role/source/game"
    chk "$game/scripts/game.gd" "$(pin "$role" game_sha)"
    chk "$game/scripts/fog_inward_edge.gd" "$(pin "$role" fog_sha)"
    chk "$game/scripts/rules.gd" "$(pin "$role" rules_sha)"
    chk "$game/reports/build-manifest.json" "$(pin "$role" manifest_sha)"
    python3 -B "$game/tools/check_source.py" |tee "$out/$role-source-check.json"
    timeout --kill-after=10s 145s "$godot" --headless --path "$game" --editor --import --quit >"$out/$role-import.log" 2>&1
    opts=(--path "$game" --resolution 568x320 --audio-driver Dummy --rendering-method gl_compatibility --single-threaded-scene --disable-render-loop --max-fps 30 --script "$here/capture-map-edge.gd" -- "$out/$role" "$role" "${args[@]}")
    if [[ $mode = METADATA_ONLY ]]; then
        timeout --kill-after=12s 60s "$godot" --headless "${opts[@]}" >"$out/$role.log" 2>&1
    else
        timeout --kill-after=12s 200s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' "$godot" "${opts[@]}" >"$out/$role.log" 2>&1
    fi
done
python3 -B "$here/verify-map-edge.py" "$out/baseline/report.json" "$out/candidate/report.json" "$here/pins.json" "$mode" |tee "$out/comparison.json"
