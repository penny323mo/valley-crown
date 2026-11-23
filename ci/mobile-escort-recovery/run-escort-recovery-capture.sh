#!/usr/bin/env bash
# QA only, real game viewport. Each view gets a disposable checkout and profile.
set -euo pipefail
[[ $# = 5 ]] || { echo 'Usage: run-escort-recovery-capture.sh BASELINE CANDIDATE GODOT PINS NEW_OUTPUT' >&2; exit 2; }
BASE="$(realpath "$1")"; CANDIDATE="$(realpath "$2")"; GODOT="$(realpath "$3")"
PINS="$(realpath "$4")"; OUT="$(realpath -m "$5")"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$HERE/capture-escort-recovery.gd"
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
assert all(len(pins[r][k])==40 and all(c in "0123456789abcdef" for c in pins[r][k]) for r in ("baseline","candidate") for k in ("commit","tree","game_tree"))
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
  [[ "$(sha256sum "$game/scripts/frontier_escort.gd" | cut -d' ' -f1)" == "${pin[6]}" ]]
  export HOME="$WORK/$role/home" XDG_DATA_HOME="$WORK/$role/home/data" XDG_CONFIG_HOME="$WORK/$role/home/config" XDG_CACHE_HOME="$WORK/$role/home/cache"
  # The known earned Chapter 2 test state has no identities or player
  # data. Its exact 39 bytes are reproduced in each disposable profile.
  python3 -B - "$PINS" "$XDG_DATA_HOME/godot/app_userdata/Valley & Crown/isolated-escort-progress.json" <<'SEED'
import hashlib,json,sys
from pathlib import Path
seed=json.loads(Path(sys.argv[1]).read_text())["isolated_earned_campaign_seed"]
value=seed["bytes"].encode()
assert len(value)==39 and hashlib.sha256(value).hexdigest()==seed["sha256"]
assert json.loads(value)=={"completed":2,"revision":2,"schema":1}
target=Path(sys.argv[2])
target.parent.mkdir(parents=True,exist_ok=True)
with target.open("xb") as fh:fh.write(value)
SEED
  log "import_begin role=$role build=${pin[3]}"
  timeout --kill-after=10s 145s "$GODOT" --headless --path "$game" --editor --import >"$OUT/$role-import.log" 2>&1
  log "import_ok role=$role"
  log "capture_begin role=$role display=568x320 software=llvmpipe fps=30"
  if timeout --kill-after=12s 420s xvfb-run -a -s '-screen 0 1280x1024x24 -nolisten tcp' stdbuf -oL -eL "$GODOT" \
    --path "$game" --resolution 568x320 --audio-driver Dummy --rendering-method gl_compatibility \
    --single-threaded-scene --disable-render-loop --max-fps 30 --script "$FIXTURE" -- \
    "$OUT/$role" "$role" "${pin[3]}" "${pin[4]}" "${pin[5]}" "${pin[6]}" >"$OUT/$role.log" 2>&1; then
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
import hashlib, json, struct, sys, zlib
from pathlib import Path

# Godot 4.6.3 gl_compatibility get_image/save_png validated against the
# prior real X11/llvmpipe witness. Fail closed on any other pixel encoding.
def original_png(data):
    def paeth(a,b,c):
        p=a+b-c
        da,db,dc=abs(p-a),abs(p-b),abs(p-c)
        return a if da<=db and da<=dc else b if db<=dc else c
    assert data[:8]==b"\x89PNG\r\n\x1a\n"
    pos=8
    kinds=[]
    payloads=[]
    while pos<len(data):
        assert pos+12<=len(data)
        n=struct.unpack_from(">I",data,pos)[0]
        end=pos+12+n
        assert end<=len(data)
        kind=data[pos+4:pos+8]
        payload=data[pos+8:end-4]
        assert zlib.crc32(kind+payload)==struct.unpack_from(">I",data,end-4)[0]
        if not kinds:
            assert kind==b"IHDR" and n==13
            assert struct.unpack(">IIBBBBB",payload)==(568,320,8,6,0,0,0)
        assert kind in (b"IHDR",b"IDAT",b"IEND") or kind[:1].islower()
        if kind==b"IDAT":
            assert not payloads or kinds[-1]==b"IDAT"
            payloads.append(payload)
        kinds.append(kind);pos=end
        if kind==b"IEND":
            assert n==0 and end==len(data)
            break
    assert kinds[0]==b"IHDR" and kinds.count(b"IHDR")==1 and payloads and kinds[-1]==b"IEND"
    pixels_per_row=568*4
    expected=(pixels_per_row+1)*320
    stream=zlib.decompressobj()
    raw=stream.decompress(b"".join(payloads),expected+1)
    assert len(raw)==expected and stream.eof and not stream.unused_data and not stream.unconsumed_tail
    previous=bytearray(pixels_per_row)
    palette=set()
    for y in range(320):
        i=y*(pixels_per_row+1)
        f=raw[i]
        assert f in (0,1,2,3,4)
        row=bytearray(raw[i+1:i+1+pixels_per_row])
        if f:
            for x,v in enumerate(row):
                a=row[x-4] if x>=4 else 0
                b=previous[x]
                c=previous[x-4] if x>=4 else 0
                q=a if f==1 else b if f==2 else (a+b)//2 if f==3 else paeth(a,b,c)
                row[x]=(v+q)&255
        if y%13==0:
            palette.update(bytes(row[x:x+4]) for x in range(0,pixels_per_row,13*4))
        previous=row
    assert len(palette)>24
    return len(palette)

out=Path(sys.argv[1])
pins=json.loads(Path(sys.argv[2]).read_text())
metadata_only=len(sys.argv)==4 and sys.argv[3]=="--metadata-only"  # Never passed in hosted run.
assert pins["status"]=="REVIEWED_FOR_CAPTURE" or metadata_only
reports={}
frame_names=("counter-cleared","paid-rebuild-unfinished")
language={
    "baseline":"回到所選 · 護送拓荒隊 · 守住前哨\n村民 3/3 · 敵軍 0/6",
    "candidate":"回到所選 · 護送拓荒隊 · 反攻已擊退\n重建倉庫 0/1 · 箭塔 1/1",
}
for role in ("baseline","candidate"):
    folder=out/role
    obs=json.loads((folder/"report.json").read_text())
    reports[role]=obs
    assert obs["failed"]==0 and obs["gestures"]==32 and len(obs["routed"])==32 and obs["metadata_only"]==metadata_only
    assert obs["size"]==[568,320] and obs["engine"]["hex"]==0x040603 and obs["engine"]["hash"]=="7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3"
    assert obs["role"]==role and tuple(f["name"] for f in obs["frames"])==frame_names
    if metadata_only:
        assert obs["result"]=="METADATA_ONLY" and obs["png_count"]==0
    else:
        assert obs["result"]=="RENDERED" and obs["display"]=="X11" and obs["renderer"]=="gl_compatibility"
        assert "llvmpipe" in obs["video_adapter"].lower() and obs["png_count"]==2
    for field in ("build","game_sha","rules_sha","director_sha"):
        assert obs[field]==pins[role][field], (role,field)
    assert obs["tick"]==11056 and obs["stage"]==3 and obs["stage_ticks"]==[6704,8116,11056]
    assert obs["outcome"]=="victory" and obs["reason"]=="escort_complete" and obs["alive"]==3 and obs["audit"]
    assert obs["evidence"]["terminal"]["progress"]==obs["evidence"]["terminal"]["revision"]==3
    for f in obs["frames"]:
        assert f["objective"]==language[role]
        assert f["objective_visible"] and not f["menu_open"] and not f["terminal_visible"]
        if metadata_only:
            assert {"sha256","file","palette_samples"}.isdisjoint(f)
            continue
        assert f["file"]==f["name"]+".png"
        data=(folder/f["file"]).read_bytes()
        assert hashlib.sha256(data).hexdigest()==f["sha256"]
        assert original_png(data)==f["palette_samples"]
    actual={p.name for p in folder.glob("*.png")}
    assert actual==({name+".png" for name in frame_names} if not metadata_only else set())

old,new=(reports[k] for k in ("baseline","candidate"))
for k in ("routed","gestures","strategic_orders","tick","stage","stage_ticks","finished","outcome","reason","alive","losses","built","trained","bank","paused","audit"):
    assert old[k]==new[k], k
old_ev=old["evidence"]
new_ev=new["evidence"]
for k in ("economic_opening","party_shortcut","arrival","first_storehouse_layout","first_storehouse_bill","first_storehouse_birth",
          "first_tower_layout","first_tower_bill","first_tower_birth","counter_preparation","counter_launch","late_defense_order",
          "earned_replacement_storehouse","recovery_storehouse_layout","recovery_storehouse_bill","recovery_storehouse_birth","terminal"):
    assert old_ev[k]==new_ev[k], k
old_drawer=old_ev["zero_enemies_recovery_gate"]
new_drawer=new_ev["zero_enemies_recovery_gate"]
assert old_drawer["menu"].endswith("擊退餘下0名敵軍；前哨被毀可重建。")
assert new_drawer["menu"].endswith("在前哨界線內付費重建倉庫，完成才計。")
assert {k:v for k,v in old_drawer.items() if k not in {"menu","objective"}}=={k:v for k,v in new_drawer.items() if k not in {"menu","objective"}}
landmarks=[]
different={"objective","file","sha256","palette_samples"}
for ix,(a,b) in enumerate(zip(old["frames"],new["frames"],strict=True)):
    for k in a.keys()|b.keys():
        if k not in different:
            assert a[k]==b[k], k
    assert a["tick"]==(10170,10514)[ix] and a["stage"]==2 and a["launched"] and a["remaining"]==0 and a["living"]==3
    assert a["counted"]=={"tower":100} and a["losses"]=={"storehouse":1}
    if ix==0:
        assert not a["paid_unfinished"] and not a["toast"]
    else:
        assert a["paid_unfinished"]["site"]["id"]==107 and a["paid_unfinished"]["site"]["pos"]==[-5.0,0.0,6.0]
        assert not a["paid_unfinished"]["site"]["built"]
        assert a["paid_unfinished"]["ledger_receipt"]["state"]=="open"
        assert a["paid_unfinished"]["ledger_receipt"]["cost_units"]=={"wood":80}
        assert a["bank"]["wood"]==435480 and old_ev["recovery_storehouse_bill"]["raw_before"]["wood"]==515480
    landmarks.append({"name":a["name"],"tick":a["tick"],"clock":a["clock"],"camera":a["camera_focus"],
                      "objective_rect":a["objective_rect"],"consistent_world_entities":len(a["world_entities"]),
                      "counted":a["counted"],"wood_milli":a["bank"]["wood"],"site_screen":a["site_screen"],
                      "baseline_label":a["objective"],"candidate_label":b["objective"]})
if not metadata_only:
    assert len({f["sha256"] for report in reports.values() for f in report["frames"]})==4
summary={
    "result":"METADATA_ONLY" if metadata_only else "RENDERED","size":[568,320],
    "game_builds":[pins[r]["build"] for r in ("baseline","candidate")],
    "scope":"Exact native Chapter 3 A/B, same routed touchscreen sequence, public stock economic/retreat/combat commands. No Web or physical phone.",
    "matched":["32 identical routed gestures","both real actors and camera, bank, and command history",
               "last enemy defeated and exactly one lost required warehouse","80 wood actually paid but not completed",
               "same ordinary recovery victory and Chapter 3 completion"],"landmarks":landmarks,
    "terminal_tick":11056,"campaign_progress":3,
    "png_count":0 if metadata_only else 4,"gestures":32,
    "files":{role:[f["file"] for f in obs["frames"] if "file" in f] for role,obs in reports.items()},
}
(out/"comparison.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n")
print(json.dumps(summary,ensure_ascii=False))
PY
log "comparison_verified"
