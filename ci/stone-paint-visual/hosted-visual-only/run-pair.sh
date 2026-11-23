#!/usr/bin/env bash
# Offline test launcher for an already available authorized Linux Xvfb runner.
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: bash run-pair.sh GIT_REPO GODOT_4_6_3 NEW_OUT'; exit 2; }
REPO="$(realpath "$1")"; GODOT="$(realpath "$2")"; OUT="$(realpath -m "$3")"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PIN=223b8678905bab8c63f1c0963f08ae5b0894b249
TIMELINE=938b5a670bb9b51d1c4883022f409f993cf2d649
ENGINE_SHA=f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3
[[ "$(git -C "$REPO" rev-parse "$PIN:game")" == "$TIMELINE" ]]
[[ "$(sha256sum "$GODOT" | cut -d' ' -f1)" == "$ENGINE_SHA" ]]
[[ "$(sha256sum "$HERE/../stone-color-only-study.patch" | cut -d' ' -f1)" == "3ce41f75414c13f479a6b24ebe75147eb2a7e6758ef67d071d66141fac952aa4" ]]
command -v xvfb-run >/dev/null; command -v xauth >/dev/null
python3 -c 'import PIL'
mkdir "$OUT"
STATE="$(mktemp -d)"; trap 'rm -rf -- "$STATE"' EXIT
{
  printf 'source %s\ngame_tree %s\nengine %s\n' "$PIN" "$TIMELINE" "$ENGINE_SHA"
  sha256sum "$HERE"/capture-stone-paint.gd "$HERE"/verify-pair.py "$HERE"/../stone-color-only-study.patch
} >"$OUT/input-receipt.txt"
for ROLE in baseline paint; do
  mkdir "$STATE/$ROLE"
  git -C "$REPO" archive "$PIN" game | tar -xf - -C "$STATE/$ROLE"
done
(
  cd "$STATE/paint"; git apply --check "$HERE/../stone-color-only-study.patch"; git apply "$HERE/../stone-color-only-study.patch"
)
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
for ROLE in baseline paint; do
  export HOME="$STATE/$ROLE/user" XDG_CONFIG_HOME="$STATE/$ROLE/user/config" XDG_DATA_HOME="$STATE/$ROLE/user/data" XDG_CACHE_HOME="$STATE/$ROLE/user/cache"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
  timeout --kill-after=10s 180s "$GODOT" --headless --path "$STATE/$ROLE/game" --editor --import --quit >"$OUT/$ROLE-import.log" 2>&1
  if grep -qE 'SCRIPT ERROR|Parse Error' "$OUT/$ROLE-import.log"; then tail -n 30 "$OUT/$ROLE-import.log"; exit 1; fi
  for SPEC in '390 844' '844 390'; do
    read -r W H <<< "$SPEC"; SIZE="${W}x${H}"
    mkdir -p "$OUT/$ROLE/$SIZE"
    timeout --kill-after=12s 540s xvfb-run -a -s '-screen 0 1280x1024x24' stdbuf -oL -eL "$GODOT" \
      --path "$STATE/$ROLE/game" --resolution "$SIZE" --audio-driver Dummy --rendering-method gl_compatibility \
      --single-threaded-scene --disable-render-loop --max-fps 30 --script "$HERE/capture-stone-paint.gd" -- \
      "$OUT/$ROLE/$SIZE" "$W" "$H" >"$OUT/$ROLE-$SIZE.log" 2>&1
  done
done
python3 "$HERE/verify-pair.py" "$OUT"
