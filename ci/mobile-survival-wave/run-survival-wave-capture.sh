#!/usr/bin/env bash
# QA only, real game viewport. Each view gets a disposable checkout and profile.
set -euo pipefail
[[ $# = 5 ]] || { echo 'Usage: run-survival-wave-capture.sh BASELINE CANDIDATE GODOT PINS NEW_OUTPUT' >&2; exit 2; }
BASE="$(realpath "$1")"; CANDIDATE="$(realpath "$2")"; GODOT="$(realpath "$3")"
PINS="$(realpath "$4")"; OUT="$(realpath -m "$5")"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$HERE/capture-survival-wave.gd"
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
for k in ("commit","tree","game_tree","build","game_sha","rules_sha","director_sha"):
 print(d[k])
PY
)
  [[ ${#pin[@]} == 7 ]]
  [[ "$(git -C "$checkout" rev-parse HEAD)" == "${pin[0]}" ]]
  [[ "$(git -C "$checkout" rev-parse 'HEAD^{tree}')" == "${pin[1]}" ]]
  [[ "$(git -C "$checkout" rev-parse HEAD:game)" == "${pin[2]}" ]]
  mkdir -p "$WORK/$role/source" "$WORK/$role/home"
  git -C "$checkout" archive "${pin[0]}" game | tar -x -C "$WORK/$role/source"
  local game="$WORK/$role/source/game"
  [[ "$(sha256sum "$game/scripts/game.gd" | cut -d' ' -f1)" == "${pin[4]}" ]]
  [[ "$(sha256sum "$game/scripts/rules.gd" | cut -d' ' -f1)" == "${pin[5]}" ]]
  [[ "$(sha256sum "$game/scripts/siege_challenge.gd" | cut -d' ' -f1)" == "${pin[6]}" ]]
  export HOME="$WORK/$role/home" XDG_DATA_HOME="$WORK/$role/home/data" XDG_CONFIG_HOME="$WORK/$role/home/config" XDG_CACHE_HOME="$WORK/$role/home/cache"
  # The known earned Chapter 1 test state has no identities or player
  # data. Its exact 39 bytes are reproduced in each disposable profile.
  python3 -B - "$PINS" "$XDG_DATA_HOME/godot/app_userdata/Valley & Crown/isolated-survival-progress.json" <<'SEED'
import hashlib,json,sys
from pathlib import Path
seed=json.loads(Path(sys.argv[1]).read_text())["isolated_earned_campaign_seed"]
value=seed["bytes"].encode()
assert len(value)==39 and hashlib.sha256(value).hexdigest()==seed["sha256"]
assert json.loads(value)=={"completed":1,"revision":1,"schema":1}
target=Path(sys.argv[2])
target.parent.mkdir(parents=True,exist_ok=True)
with target.open("xb") as fh:fh.write(value)
SEED
  log "import_begin role=$role build=${pin[3]}"
  timeout --kill-after=10s 145s "$GODOT" --headless --path "$game" --editor --import >"$OUT/$role-import.log" 2>&1
  log "import_ok role=$role"
  log "capture_begin role=$role display=568x320 software=llvmpipe fps=30"
  if timeout --kill-after=12s 420s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' stdbuf -oL -eL "$GODOT"     --path "$game" --resolution 568x320 --audio-driver Dummy --rendering-method gl_compatibility     --single-threaded-scene --disable-render-loop --max-fps 30 --script "$FIXTURE" --     "$OUT/$role" "$role" "${pin[3]}" "${pin[4]}" "${pin[5]}" "${pin[6]}" >"$OUT/$role.log" 2>&1; then
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
import hashlib,json,struct,sys,zlib
from pathlib import Path
out=Path(sys.argv[1]);pins=json.loads(Path(sys.argv[2]).read_text())
metadata_only=len(sys.argv)==4 and sys.argv[3]=="--metadata-only"  # Never passed by hosted.
frames={}
evidence={}
def original_png(data):
    assert data[:8]==b"\x89PNG\r\n\x1a\n"
    pos=8; kinds=[]
    while pos<len(data):
        assert pos+12<=len(data)
        n=struct.unpack_from(">I",data,pos)[0];end=pos+12+n
        assert end<=len(data)
        kind=data[pos+4:pos+8];payload=data[pos+8:end-4]
        assert zlib.crc32(kind+payload)==struct.unpack_from(">I",data,end-4)[0]
        if not kinds:
            assert kind==b"IHDR" and n==13
            assert struct.unpack_from(">II",payload,0)==(568,320)
        kinds.append(kind);pos=end
        if kind==b"IEND":
            assert n==0 and end==len(data)
            break
    assert kinds[0]==b"IHDR" and kinds.count(b"IHDR")==1 and b"IDAT" in kinds and kinds[-1]==b"IEND"
for role in ("baseline","candidate"):
    folder=out/role
    obs=json.loads((folder/"report.json").read_text())
    assert obs["failed"]==0 and obs["gestures"]==19 and obs["metadata_only"]==metadata_only
    assert obs["size"]==[568,320] and obs["engine"]["hex"]==0x040603
    if metadata_only:
        assert obs["result"]=="METADATA_ONLY" and obs["png_count"]==0
    else:
        assert obs["result"]=="RENDERED" and obs["display"]!="headless" and obs["renderer"]=="gl_compatibility"
        assert "llvmpipe" in obs["video_adapter"].lower() and obs["png_count"]==2
    assert obs["role"]==role
    for field in ("build","game_sha","rules_sha","director_sha"):
        assert obs[field]==pins[role][field]
    assert tuple(f["name"] for f in obs["frames"])==("intermission","final-wave-after-toast")
    frames[role]=obs["frames"];evidence[role]=obs["evidence"]
    for f in obs["frames"]:
        if metadata_only:continue
        assert f["file"]==f["name"]+".png"
        data=(folder/f["file"]).read_bytes()
        original_png(data)
        assert hashlib.sha256(data).hexdigest()==f["sha256"]
    actual={p.name for p in folder.glob("*.png")}
    assert actual==({f["file"] for f in obs["frames"]} if not metadata_only else set())
landmarks=[]
fields=("name","tick","wave","wave_active","next_tick_model","camera","camera_focus","zoom","selection","active_ids","active_hp","owned",
        "keep_hp","bank","commands","clock","clock_rect","pause_button","battle_alert_rect","menu_button","landscape_world_cap","during_wave_context")
for ix,(old,new) in enumerate(zip(frames["baseline"],frames["candidate"],strict=True)):
    for k in fields:
        assert old[k]==new[k], (k,old[k],new[k])
    assert old["tick"]==(2230,4985)[ix] and old["wave_active"]==(False,True)[ix]
    assert old["during_wave_context"]==("intermission","active_final")[ix]
    assert not old["menu_open"] and not new["menu_open"] and not old["toast"] and not new["toast"]
    assert old["visible_wave_ui"]==new["visible_wave_ui"]==[] and old["wave_actual"]=={}
    st=new["wave_actual"];text=("2/3 整備45秒","3/3 最後一波")[ix]
    assert st["text"]==text and st["visible"] and st["exact_rect"]==st["clipped_rect"]
    assert len(old["active_ids"])==(0,12)[ix]
    landmarks.append({"label":old["name"],"tick":old["tick"],"actual_clock":old["clock"],"camera":old["camera_focus"],
                      "matched_living_owned_and_active":True,"candidate_label":text,"candidate_label_rect":st["exact_rect"]})
a,b=(evidence[r] for r in ("baseline","candidate"))
assert a["outcome"]==b["outcome"] and a["next"]==b["next"] and a["waves"]["damage_events"]==b["waves"]["damage_events"]
assert a["outcome"]["tick"]==6595 and a["outcome"]["keep_hp"]==676 and a["outcome"]["reason"]=="waves_defended"
assert a["next"]["progress"]==2 and a["next"]["selected"]==2
if not metadata_only:
    assert len({f["sha256"] for group in frames.values() for f in group})==4
summary={
 "result":"METADATA_ONLY" if metadata_only else "RENDERED","size":[568,320],
 "game_builds":[pins[r]["build"] for r in ("baseline","candidate")],
 "matched":["same selected actors, camera, world positions and orders","real wave 1 clear followed by intermission",
            "real final wave after launch toast expires","same terminal outcome and next briefing"],"landmarks":landmarks,
 "png_count":0 if metadata_only else 4,"gestures":19,
 "files":{role:[f["file"] for f in vals if "file" in f] for role,vals in frames.items()}
}
(out/"comparison.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n")
print(json.dumps(summary,ensure_ascii=False))
PY
log "comparison_verified"
