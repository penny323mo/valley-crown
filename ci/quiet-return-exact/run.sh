#!/usr/bin/env bash
# Disposable Git archives of exact committed games, never an overlay.
set -euo pipefail
[[ $# -eq 4 || $# -eq 5 ]] || { echo 'run.sh BASELINE_CHECKOUT CANDIDATE_CHECKOUT GODOT NEW_OUT [--metadata-only]' >&2; exit 2; }
baseline="$(realpath "$1")"; candidate="$(realpath "$2")"; engine="$(realpath "$3")"; out="$(realpath -m "$4")"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode=RENDERED
if [[ $# = 5 ]]; then [[ $5 = --metadata-only ]]; mode=METADATA_ONLY; fi
if [[ "$mode" = RENDERED ]]; then command -v xvfb-run >/dev/null; command -v xauth >/dev/null; fi
pin(){ python3 -B - "$here/pins.json" "$@" <<'PY'
import json,sys
from pathlib import Path
x=json.loads(Path(sys.argv[1]).read_text())
for a in sys.argv[2:]:x=x[a]
assert isinstance(x,str) and x
print(x)
PY
}
chk(){ [[ "$(sha256sum "$1"|cut -d' ' -f1)" = "$2" ]] || { echo "Hash mismatch: $1" >&2; exit 2; }; }
chk "$engine" "$(pin godot_linux_sha)"
for f in run.sh probe.gd verify.py; do chk "$here/$f" "$(pin "$f")"; done
mkdir "$out"; work="$(mktemp -d)"; trap 'rm -rf -- "$work"' EXIT
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
for role in baseline candidate; do
    repo="$baseline"; if [[ $role = candidate ]]; then repo="$candidate"; fi
    src="$(pin "$role" source)"
    [[ "$src" =~ ^[0-9a-f]{40}$ ]]
    [[ "$(git -C "$repo" rev-parse HEAD)" = "$src" ]]
    [[ "$(git -C "$repo" rev-parse "$src^{tree}")" = "$(pin "$role" tree)" ]]
    [[ "$(git -C "$repo" rev-parse "$src:game")" = "$(pin "$role" game_tree)" ]]
    mkdir -p "$work/$role/source" "$work/$role/import-home" "$out/$role"
    git -C "$repo" archive "$src" game | tar -x -C "$work/$role/source"
    export HOME="$work/$role/import-home" XDG_DATA_HOME="$work/$role/import-home/data" XDG_CONFIG_HOME="$work/$role/import-home/config" XDG_CACHE_HOME="$work/$role/import-home/cache"
    game="$work/$role/source/game"
    chk "$game/scripts/game.gd" "$(pin "$role" runtime_sha256)"
    chk "$game/scripts/battle_alerts.gd" "$(pin "$role" alert_sha256)"
    chk "$game/scripts/rules.gd" "$(pin "$role" rules_sha256)"
    chk "$game/reports/build-manifest.json" "$(pin "$role" manifest_sha256)"
    python3 -B "$game/tools/check_source.py" | tee "$out/$role/source-check.json"
    timeout --kill-after=10s 145s "$engine" --headless --path "$game" --editor --import --quit >"$out/$role/import.log" 2>&1
    for dim in 480x270 568x320; do
        w="${dim%x*}"; h="${dim#*x}"
        folder="$out/$role/$dim"; mkdir "$folder" "$work/$role/$dim-home"
        export HOME="$work/$role/$dim-home" XDG_DATA_HOME="$work/$role/$dim-home/data" XDG_CONFIG_HOME="$work/$role/$dim-home/config" XDG_CACHE_HOME="$work/$role/$dim-home/cache"
        export VC_QUIET_NATIVE_OUTPUT=""
        if [[ $mode = RENDERED ]]; then export VC_QUIET_NATIVE_OUTPUT="$folder"; fi
        args=(--path "$game" --resolution "$dim" --audio-driver Dummy --rendering-method gl_compatibility --single-threaded-scene --disable-render-loop --fixed-fps 30 --script "$here/probe.gd" -- "$w" "$h" "$role")
        if [[ $mode = RENDERED ]]; then
            timeout --kill-after=12s 420s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' "$engine" "${args[@]}" >"$folder/run.log" 2>&1
        else
            timeout --kill-after=12s 320s "$engine" --headless "${args[@]}" >"$folder/run.log" 2>&1
        fi
    done
done
python3 -B "$here/verify.py" "$out" "$here/pins.json" "$mode" | tee "$out/comparison.json"
