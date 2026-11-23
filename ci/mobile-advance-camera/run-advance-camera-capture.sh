#!/usr/bin/env bash
# QA only, real game viewport. Each view gets a disposable checkout and profile.
set -euo pipefail
[[ $# = 5 ]] || { echo 'Usage: run-advance-camera-capture.sh BASELINE CANDIDATE GODOT PINS NEW_OUTPUT' >&2; exit 2; }
BASE="$(realpath "$1")"; CANDIDATE="$(realpath "$2")"; GODOT="$(realpath "$3")"
PINS="$(realpath "$4")"; OUT="$(realpath -m "$5")"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$HERE/capture-advance-camera.gd"
ENGINE_SHA=f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3
[[ "$(sha256sum "$GODOT" | cut -d' ' -f1)" = "$ENGINE_SHA" ]] || exit 2
command -v xvfb-run >/dev/null; command -v xauth >/dev/null
WORK="$(mktemp -d)"; trap 'rm -rf -- "$WORK"' EXIT
mkdir "$OUT"
printf '%s\n' "$ENGINE_SHA" >"$OUT/engine-sha256.txt"
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$OUT/launcher.log"; }
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=3.3
check_render_identity() {
  local role=$1 checkout=$2
  local -a pin
  readarray -t pin < <(python3 -B - "$PINS" "$role" "$FIXTURE" <<'PY'
import hashlib,json,sys
from pathlib import Path
pins=json.loads(Path(sys.argv[1]).read_text())
assert pins["status"]=="REVIEWED_FOR_CAPTURE"
assert hashlib.sha256(Path(sys.argv[3]).read_bytes()).hexdigest()==pins["fixture_sha256"]
d=pins[sys.argv[2]]
for k in ("commit","tree","game_tree","build","game_sha","rules_sha"):
 print(d[k])
PY
)
  [[ ${#pin[@]} == 6 ]]
  [[ "$(git -C "$checkout" rev-parse HEAD)" == "${pin[0]}" ]]
  [[ "$(git -C "$checkout" rev-parse 'HEAD^{tree}')" == "${pin[1]}" ]]
  [[ "$(git -C "$checkout" rev-parse HEAD:game)" == "${pin[2]}" ]]
  mkdir -p "$WORK/$role/source" "$WORK/$role/home"
  git -C "$checkout" archive "${pin[0]}" game | tar -x -C "$WORK/$role/source"
  local game="$WORK/$role/source/game"
  [[ "$(sha256sum "$game/scripts/game.gd" | cut -d' ' -f1)" == "${pin[4]}" ]]
  [[ "$(sha256sum "$game/scripts/rules.gd" | cut -d' ' -f1)" == "${pin[5]}" ]]
  export HOME="$WORK/$role/home" XDG_DATA_HOME="$WORK/$role/home/data" XDG_CONFIG_HOME="$WORK/$role/home/config" XDG_CACHE_HOME="$WORK/$role/home/cache"
  log "import_begin role=$role build=${pin[3]}"
  timeout --kill-after=10s 145s "$GODOT" --headless --path "$game" --editor --import >"$OUT/$role-import.log" 2>&1
  log "import_ok role=$role"
  log "capture_begin role=$role display=568x320 software=llvmpipe fps=30"
  if timeout --kill-after=12s 265s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' stdbuf -oL -eL "$GODOT"     --path "$game" --resolution 568x320 --audio-driver Dummy --rendering-method gl_compatibility     --single-threaded-scene --disable-render-loop --max-fps 30 --script "$FIXTURE" --     "$OUT/$role" "$role" "${pin[3]}" "${pin[4]}" "${pin[5]}" >"$OUT/$role.log" 2>&1; then
    log "capture_ok role=$role"
  else
    local code=$?; log "capture_failed role=$role exit=$code"
    tail -n 14 "$OUT/$role.log"
    exit "$code"
  fi
}
check_render_identity baseline "$BASE"
check_render_identity candidate "$CANDIDATE"
python3 -B - "$OUT" "$PINS" <<'PY'
import hashlib,json,struct,sys
from pathlib import Path
out=Path(sys.argv[1]); pins=json.loads(Path(sys.argv[2]).read_text())
# Optional metadata-only switch is for an already-isolated local replay of the
# same fixture. Hosted launcher never enables it or substitutes for PNG proof.
metadata_only=len(sys.argv)==4 and sys.argv[3]=="--metadata-only"
frames={}
for role in ("baseline","candidate"):
    p=out/role
    d=json.loads((p/"report.json").read_text())
    expected=("before-stale-after-pan",) if role=="baseline" else ("after-cancel-after-pan","after-one-tap-rearm")
    assert d["failed"]==0 and d["metadata_only"] == metadata_only
    assert d["size"]==[568,320] and d["engine"]["hex"] == 0x040603
    if metadata_only:
        assert d["result"]=="METADATA_ONLY" and d["png_count"]==0
    else:
        assert d["result"]=="RENDERED" and d["display"]!="headless" and d["renderer"]=="gl_compatibility"
        assert "llvmpipe" in d["video_adapter"].lower()
        assert d["png_count"]==len(expected)
    assert d["role"]==role and d["build"]==pins[role]["build"] and d["game_sha"]==pins[role]["game_sha"] and d["rules_sha"]==pins[role]["rules_sha"]
    assert tuple(x["name"] for x in d["frames"])==expected
    frames[role]=d["frames"]
    for f in d["frames"]:
        if metadata_only:continue
        assert f["file"]==f["name"]+".png"
        data=(p/f["file"]).read_bytes()
        assert data[:8]==b"\x89PNG\r\n\x1a\n" and data[12:16]==b"IHDR"
        assert struct.unpack(">II",data[16:24])==(568,320)
        assert hashlib.sha256(data).hexdigest()==f["sha256"]
old=frames["baseline"][0];new,rearmed=frames["candidate"]
same=("camera","camera_transform","camera_before","zoom","map","tick","bank","troops","selected","gesture","commands","defense")
for k in same:
    assert old[k]==new[k]==rearmed[k],(k,old[k],new[k],rearmed[k])
assert old["gesture"]==["(154.0, 128.0)","(236.0, 128.0)","(32.0, 0.0)"]
assert old["camera_before"]!=old["camera"] and old["zoom"]==22 and len(old["selected"])==2
assert {x["kind"] for x in old["troops"]}=={"spearman","archer"}
assert old["defense"]["own_hit"] and (old["mode"],new["mode"],rearmed["mode"])==(False,False,True)
original="警戒前進：點目的地；射程內迎擊，敵軍離開後繼續，不追擊。"
assert old["toast"]==rearmed["toast"]==old["partial_lift_text"]==new["partial_lift_text"]==original
assert new["toast"]=="警戒前進已取消。請重選。"
assert all(f["toast_visible"] and f["text_px"] <= f["label_rect"][2] for f in (old,new,rearmed))
if not metadata_only:
    # The two original instruction views can be visually identical to one
    # another even though the old mode is off and the rearmed mode is on.
    assert old["sha256"]!=new["sha256"] and rearmed["sha256"]!=new["sha256"]
summary={"result":"METADATA_ONLY" if metadata_only else "RENDERED","size":[568,320],
         "game_builds":[pins[x]["build"] for x in ("baseline","candidate")],
         "matched":["fresh standard match and same paid defense","same two-finger constant-span pan and complete release",
                    "same camera/terrain/tick/troop positions/selection/bank/orders","no destination touched",
                    "previous stale prompt versus visible cancellation, then one actual candidate rearm"],
         "png_count":0 if metadata_only else 3, "camera_before":old["camera_before"],
         "camera_after":old["camera"],"pan":old["gesture"],"tick":old["tick"],"troop_ids":old["selected"],
         "files":{r:[f["file"] for f in ff if "file" in f] for r,ff in frames.items()}}
(out/"comparison.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n")
print(json.dumps(summary,ensure_ascii=False))
PY
log "comparison_verified"
