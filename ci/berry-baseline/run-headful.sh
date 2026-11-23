#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: bash run-headful.sh READ_ONLY_GIT_REPO GODOT_4_6_3 NEW_OUT'; exit 2; }
REPO="$(realpath "$1")"; GODOT="$(realpath "$2")"; OUT="$(realpath -m "$3")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONDONTWRITEBYTECODE=1
python3 "$HERE/verify-berry-capture.py" preflight "$REPO" "$GODOT"
command -v xvfb-run >/dev/null; command -v xauth >/dev/null
python3 -c 'import PIL'
mkdir "$OUT"
STATE="$(mktemp -d)"; trap 'rm -rf -- "$STATE"' EXIT
PIN=4966433bfca3ebfd7a02f37342e9a58776d94508
git -C "$REPO" archive "$PIN" game | tar -xf - -C "$STATE"
export HOME="$STATE/user" XDG_CONFIG_HOME="$STATE/user/config" XDG_DATA_HOME="$STATE/user/data" XDG_CACHE_HOME="$STATE/user/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
timeout --kill-after=10s 180s "$GODOT" --headless --path "$STATE/game" --editor --import --quit >"$OUT/import.log" 2>&1
if grep -qE 'SCRIPT ERROR|Parse Error' "$OUT/import.log"; then tail -n 20 "$OUT/import.log"; exit 1; fi
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
for SPEC in '568 320' '844 390'; do
 read -r W H <<< "$SPEC"; SIZE="${W}x${H}"
 mkdir "$OUT/$SIZE"
 timeout --kill-after=12s 320s xvfb-run -a -s '-screen 0 1280x1024x24' stdbuf -oL -eL "$GODOT" \
   --path "$STATE/game" --resolution "$SIZE" --audio-driver Dummy --rendering-method gl_compatibility \
   --single-threaded-scene --disable-render-loop --max-fps 30 --script "$HERE/capture-berry-baseline.gd" -- \
   "$OUT/$SIZE" "$W" "$H" >"$OUT/$SIZE.log" 2>&1
 if grep -qE 'SCRIPT ERROR|Parse Error' "$OUT/$SIZE.log"; then tail -n 30 "$OUT/$SIZE.log"; exit 1; fi
done
cp "$HERE/input-pin.json" "$OUT/input-pin.json"
python3 "$HERE/verify-berry-capture.py" rendered "$OUT"
