#!/usr/bin/env bash
# Disposable snapshots of two committed, stamped Git sources. Never applies an overlay.
set -euo pipefail
[[ $# -ge 4 && $# -le 5 ]] || { echo 'Usage: run-exact-capture.sh BASELINE_CHECKOUT CANDIDATE_CHECKOUT GODOT NEW_OUT [--metadata-only]' >&2; exit 2; }
baseline="$(realpath "$1")"; candidate="$(realpath "$2")"; g="$(realpath "$3")"; out="$(realpath -m "$4")"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode=RENDERED
if [[ $# = 5 ]]; then [[ $5 = --metadata-only ]]; mode=METADATA_ONLY; fi
if [[ "$mode" = RENDERED ]]; then command -v xvfb-run >/dev/null; command -v xauth >/dev/null; fi
pin(){ python3 -B - "$here/pins.json" "$@" <<'PY'
import json,sys
from pathlib import Path
v=json.loads(Path(sys.argv[1]).read_text())
for k in sys.argv[2:]:v=v[k]
assert isinstance(v,str) and v
print(v)
PY
}
chk(){ [[ "$(sha256sum "$1"|cut -d' ' -f1)" = "$2" ]] || { echo "Hash mismatch: $1" >&2; exit 2; }; }
chk "$g" "$(pin godot_linux_sha)"
for artifact in run-exact-capture.sh probe-baseline.gd probe-candidate.gd earned-chapter-two.json verify-original-capture.py; do chk "$here/$artifact" "$(pin "$artifact")"; done
mkdir "$out"; work="$(mktemp -d)"; trap 'rm -rf -- "$work"' EXIT
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
for role in baseline candidate; do
    repo="$baseline"; if [[ $role = candidate ]]; then repo="$candidate"; fi
    src="$(pin "$role" source)"
    [[ "$src" =~ ^[0-9a-f]{40}$ ]]
    [[ "$(git -C "$repo" rev-parse HEAD)" = "$src" ]]
    [[ "$(git -C "$repo" rev-parse "$src^{tree}")" = "$(pin "$role" tree)" ]]
    [[ "$(git -C "$repo" rev-parse "$src:game")" = "$(pin "$role" game_tree)" ]]
    mkdir -p "$work/$role/source" "$work/$role/home" "$out/$role"
    git -C "$repo" archive "$src" game | tar -x -C "$work/$role/source"
    export HOME="$work/$role/home" XDG_DATA_HOME="$work/$role/home/data" XDG_CONFIG_HOME="$work/$role/home/config" XDG_CACHE_HOME="$work/$role/home/cache"
    export VC_NATIVE_PLACEMENT_CAPTURE_DIR=
    if [[ "$mode" = RENDERED ]]; then export VC_NATIVE_PLACEMENT_CAPTURE_DIR="$out/$role"; fi
    export VC_NATIVE_PLACEMENT_BASELINE="$out/baseline/report.json"
    save="$XDG_DATA_HOME/godot/app_userdata/Valley & Crown"
    mkdir -p "$save"; cp "$here/earned-chapter-two.json" "$save/isolated-escort-progress.json"
    game="$work/$role/source/game"
    chk "$game/scripts/game.gd" "$(pin "$role" game_sha)"
    chk "$game/scripts/rules.gd" "$(pin "$role" rules_sha)"
    chk "$game/reports/build-manifest.json" "$(pin "$role" manifest_sha)"
    python3 -B "$game/tools/check_source.py" | tee "$out/$role-source-check.json"
    timeout --kill-after=10s 145s "$g" --headless --path "$game" --editor --import --quit >"$out/$role-import.log" 2>&1
    opts=(--path "$game" --resolution 568x320 --audio-driver Dummy --rendering-method gl_compatibility --single-threaded-scene --disable-render-loop --max-fps 30 --script "$here/probe-$role.gd" -- 568 320 "$out/$role/report.json")
    if [[ "$mode" = RENDERED ]]; then
        timeout --kill-after=12s 300s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' "$g" "${opts[@]}" >"$out/$role.log" 2>&1
    else
        timeout --kill-after=12s 160s "$g" --headless "${opts[@]}" >"$out/$role.log" 2>&1
    fi
done
python3 -B "$here/verify-original-capture.py" "$out" "$here/pins.json" "$mode" | tee "$out/comparison.json"
