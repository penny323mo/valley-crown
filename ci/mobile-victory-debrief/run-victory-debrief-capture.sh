#!/usr/bin/env bash
# QA only, real game viewport. Each view gets a disposable checkout and profile.
set -euo pipefail
[[ $# = 5 ]] || { echo 'Usage: run-victory-debrief-capture.sh BASELINE CANDIDATE GODOT PINS NEW_OUTPUT' >&2; exit 2; }
BASE="$(realpath "$1")"; CANDIDATE="$(realpath "$2")"; GODOT="$(realpath "$3")"
PINS="$(realpath "$4")"; OUT="$(realpath -m "$5")"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$HERE/capture-victory-debrief.gd"
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
for k in ("commit","tree","game_tree","build","game_sha","rules_sha","report_sha"):
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
  [[ "$(sha256sum "$game/scripts/match_report.gd" | cut -d' ' -f1)" == "${pin[6]}" ]]
  export HOME="$WORK/$role/home" XDG_DATA_HOME="$WORK/$role/home/data" XDG_CONFIG_HOME="$WORK/$role/home/config" XDG_CACHE_HOME="$WORK/$role/home/cache"
  log "import_begin role=$role build=${pin[3]}"
  timeout --kill-after=10s 145s "$GODOT" --headless --path "$game" --editor --import >"$OUT/$role-import.log" 2>&1
  log "import_ok role=$role"
  log "capture_begin role=$role display=568x320 software=llvmpipe fps=30"
  if timeout --kill-after=12s 355s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' stdbuf -oL -eL "$GODOT"     --path "$game" --resolution 568x320 --audio-driver Dummy --rendering-method gl_compatibility     --single-threaded-scene --disable-render-loop --max-fps 30 --script "$FIXTURE" --     "$OUT/$role" "$role" "${pin[3]}" "${pin[4]}" "${pin[5]}" "${pin[6]}" >"$OUT/$role.log" 2>&1; then
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
out=Path(sys.argv[1]);pins=json.loads(Path(sys.argv[2]).read_text())
metadata_only=len(sys.argv)==4 and sys.argv[3]=="--metadata-only"  # Disabled in hosted witness.
frames={}
evidence={}
for role in ("baseline","candidate"):
    folder=out/role
    obs=json.loads((folder/"report.json").read_text())
    expected=("before-victory-overview",) if role=="baseline" else ("after-victory-overview","after-victory-buildings")
    assert obs["failed"]==0 and obs["metadata_only"]==metadata_only
    assert obs["size"]==[568,320] and obs["engine"]["hex"]==0x040603
    if metadata_only:
        assert obs["result"]=="METADATA_ONLY" and obs["png_count"]==0
    else:
        assert obs["result"]=="RENDERED" and obs["display"]!="headless" and obs["renderer"]=="gl_compatibility"
        assert "llvmpipe" in obs["video_adapter"].lower()
        assert obs["png_count"]==len(expected)
    assert obs["role"]==role
    for field in ("build","game_sha","rules_sha","report_sha"):
        assert obs[field]==pins[role][field]
    assert tuple(f["name"] for f in obs["frames"])==expected
    frames[role]=obs["frames"]
    evidence[role]=obs["evidence"]
    for f in obs["frames"]:
        if metadata_only:continue
        assert f["file"]==f["name"]+".png"
        data=(folder/f["file"]).read_bytes()
        assert data[:8]==b"\x89PNG\r\n\x1a\n" and data[12:16]==b"IHDR"
        assert struct.unpack(">II",data[16:24])==(568,320)
        assert hashlib.sha256(data).hexdigest()==f["sha256"]
old=frames["baseline"][0];new,buildings=frames["candidate"]
a,b=(evidence[r] for r in ("baseline","candidate"))
assert a==b,"Objective taps, authoritative battle, earned facts, and persisted pages must all match"
assert a["objective_ticks"]==[2254,4590]
assert all(a[k]["tap_succeeded" if k=="first_objective" else "tapped"] and a[k]["no_order"] for k in ("first_objective","second_objective"))
result=a["result"]
assert result["tick"]==4590 and result["outcome"]=="victory" and result["reason"]=="breach_complete"
assert result["unlocked"]==1 and result["completed"]=={"house":1} and result["trained"]=={"spearman":1}
assert old["title"]==new["title"]==buildings["title"]=="攻城突破完成"
assert old["tick"]==new["tick"]==buildings["tick"]==result["tick"]
assert old["page"]==new["page"]=="overview" and buildings["page"]=="buildings"
assert old["body"]==new["body"] and old["body_visible"] and new["body_visible"] and not buildings["body_visible"]
assert old["scroll_px"]==new["scroll_px"]==buildings["scroll_px"]==0
assert (old["scroll_rect"][3],new["scroll_rect"][3],buildings["scroll_rect"][3])==(64,116,116)
assert (old["report_px_visible"],new["report_px_visible"],buildings["report_px_visible"])==(3,55,116)
assert not old["visible_report_rows"] and new["visible_report_rows"]==["本局階段紀錄","00:18 · 首次擊中敵方目標"]
assert "民居　1／0" in buildings["visible_report_rows"]
assert buildings["report_text"]==a["saved_pages"]["buildings"]
def fact_lines(text):
    return sorted(x for x in text.splitlines() if x)
assert old["report_text"]==a["saved_pages"]["overview"]
assert fact_lines(old["report_text"])==fact_lines(new["report_text"])
assert all(len(f["actions"])==4 and f["actions"]["下一場"]["reached"] for f in (old,new,buildings))
assert new["actions"]==buildings["actions"]
assert all(v["rect"][2:]==[121,46] for v in new["actions"].values())
if not metadata_only:
    assert len({f["sha256"] for f in (old,new,buildings)})==3
summary={
 "result":"METADATA_ONLY" if metadata_only else "RENDERED","size":[568,320],
 "game_builds":[pins[r]["build"] for r in ("baseline","candidate")],
 "matched":["same real Chapter 1 authored win","same mission objective taps, earned milestones, bank and camera",
            "same persisted report on all four pages","same visible victory title and reachability of Next",
            "first milestone and paid house visible without scrolling on candidate"],
 "png_count":0 if metadata_only else 3,"tick":result["tick"],"camera":result["camera_focus"],
 "objective_ticks":a["objective_ticks"],"report_visible_px":[old["report_px_visible"],new["report_px_visible"]],
 "new_visible_first_milestone":new["visible_report_rows"][1],"new_visible_building_row":"民居　1／0",
 "files":{role:[f["file"] for f in vals if "file" in f] for role,vals in frames.items()}
}
(out/"comparison.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n")
print(json.dumps(summary,ensure_ascii=False))
PY
log "comparison_verified"
