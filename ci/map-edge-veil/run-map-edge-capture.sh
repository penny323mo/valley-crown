#!/usr/bin/env bash
# New disposable profiles and pinned source, no repo or network writes.
# Hosted requirement: official 4.6.3, Xvfb, xauth, llvmpipe GL 3.3, Python stdlib.
set -euo pipefail
[[ $# -ge 3 && $# -le 4 ]] || { echo 'Usage: run-map-edge-capture.sh READABLE_GIT_CHECKOUT PINNED_GODOT NEW_OUTPUT [--metadata-only]' >&2; exit 2; }
repo="$(realpath "$1")"; godot="$(realpath "$2")"; out="$(realpath -m "$3")"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode=RENDERED; args=()
if [[ $# = 4 ]]; then [[ $4 = --metadata-only ]]; mode=METADATA_ONLY; args=("$4"); fi
if [[ $mode = RENDERED ]]; then command -v xvfb-run >/dev/null; command -v xauth >/dev/null; fi
pin() { python3 - "$here/pins.json" "$1" <<'PY'
import json,sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text())[sys.argv[2]])
PY
}
chk() { [[ "$(sha256sum "$1"|cut -d' ' -f1)" == "$2" ]] || { echo "Hash mismatch: $1" >&2; exit 2; }; }
chk "$godot" "$(pin godot_linux_sha)"
chk "$here/map-edge-veil.patch" "$(pin patch_sha)"
chk "$here/capture-map-edge.gd" "$(pin fixture_sha)"
chk "$here/verify-map-edge.py" "$(pin verification_sha)"
source="$(pin source)"
[[ "$(git -C "$repo" rev-parse "$source")" = "$source" ]]
[[ "$(git -C "$repo" rev-parse "$source:game")" = "$(pin game_tree)" ]]
work="$(mktemp -d)"; trap 'rm -rf -- "$work"' EXIT
mkdir "$out"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
for role in baseline candidate; do
    mkdir -p "$work/$role/source" "$work/$role/home"
    git -C "$repo" archive "$source" game|tar -x -C "$work/$role/source"
    if [[ $role = candidate ]]; then
        git -C "$work/$role/source" apply --check "$here/map-edge-veil.patch"
        git -C "$work/$role/source" apply "$here/map-edge-veil.patch"
    fi
    export HOME="$work/$role/home" XDG_DATA_HOME="$work/$role/home/data" XDG_CONFIG_HOME="$work/$role/home/config" XDG_CACHE_HOME="$work/$role/home/cache"
    game="$work/$role/source/game"
    timeout --kill-after=10s 145s "$godot" --headless --path "$game" --editor --import --quit >"$out/$role-import.log" 2>&1
    opts=(--path "$game" --resolution 568x320 --audio-driver Dummy --rendering-method gl_compatibility --single-threaded-scene --disable-render-loop --max-fps 30 --script "$here/capture-map-edge.gd" -- "$out/$role" "$role" "${args[@]}")
    if [[ $mode = METADATA_ONLY ]]; then
        timeout --kill-after=12s 60s "$godot" --headless "${opts[@]}" >"$out/$role.log" 2>&1
    else
        timeout --kill-after=12s 200s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' "$godot" "${opts[@]}" >"$out/$role.log" 2>&1
    fi
done
python3 -B "$here/verify-map-edge.py" "$out/baseline/report.json" "$out/candidate/report.json" "$here/pins.json" "$mode" |tee "$out/comparison.json"
