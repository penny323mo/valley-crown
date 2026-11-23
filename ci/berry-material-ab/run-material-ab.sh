#!/usr/bin/env bash
# Offline, authorized host only; no workflow dispatch, publish or worktree mutation.
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: bash run-material-ab.sh READ_ONLY_GIT_REPO GODOT_4_6_3 NEW_OUT'; exit 2; }
REPO="$(realpath "$1")"; GODOT="$(realpath "$2")"; OUT="$(realpath -m "$3")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QA="$(realpath "$HERE/../berry-baseline")"
PATCH="$HERE/berry-late-foliage.patch"
export PYTHONDONTWRITEBYTECODE=1
[[ "$(sha256sum "$QA/input-pin.json" | cut -d' ' -f1)" == "f6c8ab48f2ce1c0bb68cb3fcbcf2abe166a83d29c3b77a13f7b8d324d74d05d6" ]]
python3 "$QA/verify-berry-capture.py" preflight "$REPO" "$GODOT"
command -v xvfb-run >/dev/null; command -v xauth >/dev/null
python3 -c 'import PIL'
[[ "$(sha256sum "$PATCH" | cut -d' ' -f1)" == "aa395df148813f0e490abd9788a82d67980ab644f30d4a40d5fd7c5e3e136bac" ]]
mkdir "$OUT"
STATE="$(mktemp -d)"; trap 'rm -rf -- "$STATE"' EXIT
PIN=4966433bfca3ebfd7a02f37342e9a58776d94508
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
for ROLE in baseline candidate; do
 mkdir "$STATE/$ROLE" "$OUT/$ROLE"
 git -C "$REPO" archive "$PIN" game | tar -xf - -C "$STATE/$ROLE"
 if [[ "$ROLE" == candidate ]]; then
  ( cd "$STATE/$ROLE"; git apply --check "$PATCH"; git apply "$PATCH" )
  FILE="$STATE/$ROLE/game/scripts/bush_donor_diagnostic.gd"
  [[ "$(sha256sum "$FILE" | cut -d' ' -f1)" == "972f4f31ea144a7e8af7fec9ec19cdda42a4f36467deb0c3fe1a686aa08d32a0" ]]
 fi
 export HOME="$STATE/$ROLE/user" XDG_CONFIG_HOME="$STATE/$ROLE/user/config" XDG_DATA_HOME="$STATE/$ROLE/user/data" XDG_CACHE_HOME="$STATE/$ROLE/user/cache"
 mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
 timeout --kill-after=10s 180s "$GODOT" --headless --path "$STATE/$ROLE/game" --editor --import --quit >"$OUT/$ROLE/import.log" 2>&1
 if grep -qE 'SCRIPT ERROR|Parse Error' "$OUT/$ROLE/import.log"; then tail -n 30 "$OUT/$ROLE/import.log"; exit 1; fi
 for SPEC in '568 320' '844 390'; do
  read -r W H <<< "$SPEC"; SIZE="${W}x${H}"
  mkdir "$OUT/$ROLE/$SIZE"
  timeout --kill-after=12s 320s xvfb-run -a -s '-screen 0 1280x1024x24' stdbuf -oL -eL "$GODOT" \
    --path "$STATE/$ROLE/game" --resolution "$SIZE" --audio-driver Dummy --rendering-method gl_compatibility \
    --single-threaded-scene --disable-render-loop --max-fps 30 --script "$QA/capture-berry-baseline.gd" -- \
    "$OUT/$ROLE/$SIZE" "$W" "$H" >"$OUT/$ROLE/$SIZE.log" 2>&1
  if grep -qE 'SCRIPT ERROR|Parse Error' "$OUT/$ROLE/$SIZE.log"; then tail -n 30 "$OUT/$ROLE/$SIZE.log"; exit 1; fi
 done
 python3 "$QA/verify-berry-capture.py" rendered "$OUT/$ROLE"
done
{
 echo 'Release stamp identifies pinned base only; candidate is an isolated material experiment'
 sha256sum "$PATCH" "$HERE"/{run-material-ab.sh,verify-material-ab.py} "$QA"/input-pin.json
} > "$OUT/input-receipt.txt"
python3 "$HERE/verify-material-ab.py" "$OUT"
