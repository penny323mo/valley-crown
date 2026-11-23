#!/usr/bin/env python3
"""One exact stock exported Survival camera A/B. Fresh hosted Chrome only."""
import base64
import functools
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, ProxyHandler, build_opener

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
SIZE=(568,320)
FILES=tuple("index."+p for p in (
    "apple-touch-icon.png","audio.position.worklet.js","audio.worklet.js","html","icon.png","js","pck","png","wasm"))
ROLES=("baseline","candidate")
# Exact normal Survival opens in preparation; first possible authored wave
# is tick 900 (45s). Bound actual browser start much tighter (6s), with no
# paid actions/order/selection/pose drift, so no synthetic tick zero claim.
MAX_OPENING_TICK=120
FIRST_WAVE_TICK=900
OPENING_FOCUS=(-25,0,11)
# Genuine normal camera input. Pinned native baseline+candidate found all 18
# visible unit mesh bounds below y=381 and all directed shadows below y=391.
# Guard the actual public center, not assigned coordinates or altered pixels.
NORTH_FOCUS=(-33.8262481689453,0,-24.5124206542969)
NORTH_FINGERS=((250,123),(350,123))
NORTH_STEPS=((-9,20),(-18,39),(-27,58),(-36,77),(-46,96))
NORTH_SWIPE_COUNT=5

TERRAIN_SETTLE_TIMEOUT=195

def northerly_camera(camera):
    f=(camera or {}).get("focus")
    return isinstance(f,list) and len(f)==3 and all(abs(a-b)<=.00015 for a,b in zip(f,NORTH_FOCUS)) and camera.get("zoom")==22
INITIAL_BANK={"food":150000,"wood":200000,"stone":100000,"iron":0}

# Exact settled 568x320 controls independently matched by native routing
# and both stock-browser arms. The pre-layout Survival x46 maps to Breach.
STOCK_MENU_CONTROLS={
    ("home","StartMatchButton"):("開始戰役",[64,88,162,54]),
    ("battle_groups","BattleGroup3"):("劇本挑戰",[160,164,126,54]),
    ("battle_options","ChooseBattle_survival"):("三波守城挑戰",[178,100,144,54]),
    ("setup","LaunchMatchButton"):("出征",[338,74,198,54]),
}

def settled_menu_target(o,page,identity):
    m=o.get("menu") or {}; text,rect=STOCK_MENU_CONTROLS[(page,identity)]
    if not m.get("visible") or m.get("page")!=page or m.get("match_exists") or o.get("css")!=[568,320,1] or o.get("canvas")!=[568,320]:return None
    found=[b for b in m.get("buttons",[]) if b.get("id")==identity and b.get("text")==text and b.get("rect")==rect]
    return found[0] if len(found)==1 else None

def opening_clock(s):
    tick=s.get("tick")
    return type(tick) is int and 0<=tick<=MAX_OPENING_TICK<FIRST_WAVE_TICK and abs(s["time"]-tick*.05)<1e-6
ERROR=re.compile(
    r"shader error|shader compilation (?:failed|error)|failed to (?:compile|link)|(?:compile|link)(?:ing)? [^\n]{0,30}shader.*(?:failed|error)|"
    r"gl_invalid_(?:enum|value|operation|framebuffer_operation)|context lost|wasm.*(?:trap|unreachable)|"
    r"runtimeerror|syntaxerror|parse error",
    re.I)
def require(flag,label):
    if not flag:raise RuntimeError(label)
def sha(body):return hashlib.sha256(body).hexdigest()
def jdump(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n")
def loader(name,script):
    spec=importlib.util.spec_from_file_location(name,script)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
def digest_fields(row):
    return all(isinstance(row[k],str) and re.fullmatch("[0-9a-f]{64}",row[k]) for k in ("metadata_sha256","zip_sha256","shader_source_sha")) and all(
        re.fullmatch("[0-9a-f]{40}",row[k]) for k in ("formal_commit","source_commit","game_tree")) and all(
        type(row[k]) is int and row[k]>0 for k in ("run_id","artifact_id"))
def unpack(raw,row,folder,archive):
    entries=archive.verified_members(raw,row)
    meta=json.loads(entries["candidate-metadata.json"])
    require(all(meta[k]==row[k] for k in ("source_commit","game_tree","build")),"archive exact product source provenance")
    require(meta["export_run"].endswith("/"+str(row["run_id"])),"archive exact formal run")
    hashes=meta["export_files_sha256"]
    require(set(hashes)==set(FILES),"stock Web release inventory")
    folder.mkdir()
    for name in FILES:
        a,b=(entries[f"artifacts/{c}/{name}"] for c in ("clean-a","clean-b"))
        require(a==b and sha(a)==hashes[name],"stock clean exports match: "+name)
        (folder/name).write_bytes(a)
    return hashes
def prepare(pins,stage,out):
    archive=loader("archive",ROOT/"scripts/web_release_archive.py")
    require(all(digest_fields(pins[r]) for r in ROLES),"unbound exact product artifact pins")
    api=archive.GitHub("penny323mo/valley-crown")
    report={}
    for role in ROLES:
        row=pins[role]
        run=api.request(f"/actions/runs/{row['run_id']}")
        require(run["status"]=="completed" and run["conclusion"]=="success" and run["head_sha"]==row["formal_commit"] and run["head_branch"]=="main","exact successful formal head")
        inventory=api.request(f"/actions/runs/{row['run_id']}/artifacts")
        found=[a for a in inventory['artifacts'] if a["id"]==row["artifact_id"]]
        require(len(found)==1,"exact formal artifact exists uniquely")
        info=found[0]
        require(info["workflow_run"]["id"]==row["run_id"] and not info["expired"] and info["digest"]=="sha256:"+row["zip_sha256"],"artifact exact nonexpired formal run and digest")
        data=api.request(f"/actions/artifacts/{row['artifact_id']}/zip",binary=True)
        folder=stage/role
        before=unpack(data,row,folder,archive)
        require(before=={f:sha((folder/f).read_bytes()) for f in FILES},"exact original stock export bytes")
        report[role]={"input":row,"stock_export_sha256":before}
    jdump(out/"verified-inputs.json",report)

def until(fn,seconds):
    stop=time.monotonic()+seconds
    while time.monotonic()<stop:
        result=fn()
        if result is not None and result is not False:return result
        time.sleep(.2)
    raise TimeoutError("expected browser state did not appear")
class Local(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*_):pass
    def end_headers(self):
        self.send_header("Cache-Control","no-store")
        super().end_headers()
def projection(focus,zoom,w,h):
    # Ortho KEEP_HEIGHT: known gameplay camera offset and screen pixel centre.
    import math
    off=(19.,25.,23.)
    def unit(v):
        n=math.sqrt(sum(x*x for x in v));return tuple(x/n for x in v)
    back=unit(off);right=unit((23.,0.,-19.))
    up=(back[1]*right[2],back[2]*right[0]-back[0]*right[2],-back[1]*right[0])
    def hit(x,y):
        p=[focus[i]+off[i]+zoom/h*((x-w/2)*right[i]+(h/2-y)*up[i]) for i in range(3)]
        return [p[i]+back[i]*(.110-p[1])/back[1] for i in range(3)]
    a,b,d=hit(.5,.5),hit(1.5,.5),hit(.5,1.5)
    return [a,[z-x for z,x in zip(b,a)],[z-x for z,x in zip(d,a)]]

def contains(outer,r):
    return len(r)==4 and all(outer[i]<=r[i] and r[i]+r[i+2]<=outer[i]+outer[i+2] for i in (0,1))

def browser(root,out,row,role,driver,chrome,web):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1",0));port=sock.getsockname()[1]
    opener=build_opener(ProxyHandler({}))
    address=f"http://127.0.0.1:{port}"
    prefix=""
    def call(method,path,data=None):
        try:
            request=Request(address+path,json.dumps(data).encode() if data is not None else None,{"content-type":"application/json"},method=method)
            with opener.open(request,timeout=30) as res:return json.load(res)["value"]
        except HTTPError as e:
            raise RuntimeError(f"ChromeDriver {e.code}: {e.read().decode(errors='replace')[:1600]}") from None
    def js(src,*args):return call("POST",prefix+"/execute/sync",{"script":src,"args":args})
    def cdp(cmd,params=None):return call("POST",prefix+"/goog/cdp/execute",{"cmd":cmd,"params":params or {}})
    def logs():return call("POST",prefix+"/log",{"type":"browser"})
    receipt={"role":role,"scope":"Stock exact engine and PCK, true Chrome WebGL2. Ordinary stock Survival touch route, no physical iPhone."}
    with (out/f"{role}-chromedriver.log").open("wb") as logfile:
      owned=subprocess.Popen([driver,f"--port={port}","--allowed-ips=127.0.0.1"],stdout=logfile,stderr=logfile)
      try:
        def ready():
            if owned.poll() is not None:raise RuntimeError("ChromeDriver exited before navigation")
            try:return call("GET","/status").get("ready")
            except OSError:return False
        until(ready,16)
        profile=root/f"{role}-fresh-chrome";profile.mkdir()
        options={"binary":chrome,"args":[
            "--headless","--disable-background-networking","--no-first-run",f"--user-data-dir={profile}",
            "--use-gl=angle","--use-angle=swiftshader","--force-device-scale-factor=1",
            "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1",
        ],"mobileEmulation":{"deviceMetrics":{"width":SIZE[0],"height":SIZE[1],"pixelRatio":1,"mobile":True,"touch":True}}}
        session=call("POST","/session",{"capabilities":{"alwaysMatch":{"browserName":"chrome",
            "goog:chromeOptions":options,"goog:loggingPrefs":{"browser":"ALL"},"pageLoadStrategy":"eager"}}})
        prefix="/session/"+session["sessionId"]
        receipt["browser"]=session["capabilities"]["browserVersion"]
        cli=cdp("Browser.getBrowserCommandLine")["arguments"]
        forbidden={"--no-sandbox","--disable-setuid-sandbox","--disable-gpu-sandbox","--enable-unsafe-swiftshader","--single-process"}
        require(not forbidden.intersection(s.partition("=")[0] for s in cli),"browser sandbox/GL safety was weakened")
        receipt["sandbox_preserved"]=True
        cdp("Network.enable")
        cdp("Network.setBlockedURLs",{"urls":["https://*"]})
        cdp("Page.addScriptToEvaluateOnNewDocument",{"source":(HERE/"gl-observe.js").read_text()})
        def observe():
            return js("""const ms=typeof window.valleyMenuSnapshot==='function';
                if(ms)window.valleyMenuSnapshot();
                const gs=typeof window.valleySnapshot==='function';
                if(gs)window.valleySnapshot();
                const c=document.querySelector('#canvas'), r=c?.getBoundingClientRect();
                return {menu:ms?window.valleyMenuState:null,state:gs?window.valleyState:null,
                    css:[innerWidth,innerHeight,devicePixelRatio],canvas:c?[c.width,c.height]:null,
                    rect:r?[r.x,r.y,r.width,r.height]:null,gl:window.vcGL||null};""")
        def tap(r):
            require(contains([0,0,*SIZE],r) and min(r[2:])>=44,"stock touch target not fully accessible")
            x,y=(r[i]+r[i+2]*.5 for i in (0,1))
            cdp("Input.dispatchTouchEvent",{"type":"touchStart","touchPoints":[{"x":x,"y":y,"id":1}]})
            cdp("Input.dispatchTouchEvent",{"type":"touchEnd","touchPoints":[]})
        def tap_menu(page,identity):
            def target():return settled_menu_target(observe(),page,identity)
            # A canonical first rect alone is not proof that the grid has
            # settled. Sample after two genuinely distinct Chrome rAF frames.
            for attempt in range(3):
                b=until(target,8)
                frames=call("POST",prefix+"/execute/async",{"script":"""const done=arguments[arguments.length-1];
                    requestAnimationFrame(a=>requestAnimationFrame(b=>done([a,b])));""","args":[]})
                require(type(frames) is list and len(frames)==2 and frames[1]>frames[0],"two distinct actual menu animation frames not observed")
                if target()==b:
                    tap(b["rect"]);return {"page":page,"layout_frames_ms":frames,**b}
            raise RuntimeError(f"stock menu would not remain settled: {page}/{identity}")
        def dims(o):
            return o["css"]==[568,320,1] and o["canvas"]==list(SIZE) and o["rect"]==[0,0,568,320]
        def world(o, north=False):
            if not o["state"] or not o["menu"]:return False
            s=o["state"];h=s["hud"];m=o["menu"]
            return dims(o) and m["match_exists"] and not m["visible"] and s["build"]==row["build"] and h.get("schema")==2 and h["viewport"]==list(SIZE) and (northerly_camera(h.get("camera")) if north else h.get("camera")=={"focus":list(OPENING_FOCUS),"zoom":22})
        def auth(s):
            return {k:s[k] for k in ("victory_mode","control_ticks","paused","game_over","outcome","selected","bank_milli","age","military_techs",
                       "population","capacity","delivered","built","trained","own_pending_commands","touch_mode","build_mode")}
        def opening_state(s):
            return s["bank_milli"]==INITIAL_BANK and s["victory_mode"]=="conquest" and s["age"]==2 and s["population"]==18 and s["capacity"]==25 and len(s["selected"])==12 and not s["game_over"] and not s["own_pending_commands"] and not s["touch_mode"] and not s["build_mode"] and s["built"]==s["trained"]==s["delivered"]==0
        def gl_ok(g):
            c=(g or {}).get("canvas") or {}
            return c.get("version","").startswith("WebGL 2.0") and c.get("glsl","").startswith("WebGL GLSL ES 3.00") and not g["errorCount"] and not g["contextLost"]
        def drew(g):
            return gl_ok(g) and min(g["maskCompiled"],g["maskLinked"],g["maskDrawn"])>0 and (min(g["seamCompiled"],g["seamLinked"],g["seamDrawn"])>0 if role=="candidate" else not max(g["seamCompiled"],g["seamLinked"],g["seamDrawn"]))
        def diagnostic(suffix):
            el=call("POST",prefix+"/element",{"using":"css selector","value":"#canvas"})
            eid=el["element-6066-11e4-a52e-4f735466cecf"]
            raw=base64.b64decode(call("GET",prefix+"/element/"+eid+"/screenshot"),validate=True)
            require(raw.startswith(b"\x89PNG\r\n\x1a\n"),"no original diagnostic PNG")
            (out/f"{role}-{suffix}.png").write_bytes(raw);return sha(raw)
        call("POST",prefix+"/url",{"url":f"{web}/{role}/index.html?qa=1"})
        def home():
            o=observe();m=o["menu"]
            return o if m and m["visible"] and m["page"]=="home" and gl_ok(o["gl"]) else None
        o=until(home,55)
        require(dims(o) and not o["menu"]["match_exists"] and not o["gl"]["maskDrawn"] and not o["gl"]["seamDrawn"],"menu-only must not count as game fog proof")
        receipt["stock_menu_only"]=True;receipt["menu_console"]=logs();receipt["route"]=[]
        for page,identity in (("home","StartMatchButton"),("battle_groups","BattleGroup3"),("battle_options","ChooseBattle_survival"),("setup","LaunchMatchButton")):
            receipt["route"].append(tap_menu(page,identity))
        def live():
            o=observe()
            s=o.get("state");menu=o.get("menu") or {}
            if s and menu.get("match_exists") and not menu.get("visible"):
                h=s.get("hud") or {}
                receipt["first_stock_match_observation"]={"camera":h.get("camera"),"tick":s.get("tick"),
                    "visible_objective_controls":[b["text"] for b in h.get("buttons",[]) if "定位目標" in b["text"]]}
                wrong=receipt["first_stock_match_observation"]
                require(not wrong["visible_objective_controls"] and (wrong["camera"] or {}).get("focus")!=[-4,0,6],
                        "stock game actually opened a different authored mission; not a Survival render")
                if world(o):return o
        first=until(live,30)
        f=first["state"]
        require(opening_state(f) and not f["paused"] and opening_clock(f),"not an early ordinary Survival battlefield")
        receipt["first_battlefield"]={"state":f,"gl":first["gl"]}
        # Freeze using the genuine stock Pause button at the initial camera,
        # before serial event acknowledgements can move the match to wave 1.
        pause=[b for b in f["hud"]["buttons"] if b["text"]=="暫停" and not b["disabled"]]
        require(len(pause)==1,"ordinary Pause touch target not unique")
        tap(pause[0]["rect"])
        def opening_frozen():
            o=observe()
            return o if world(o) and o["state"]["paused"] and drew(o["gl"]) else None
        frozen_opening=until(opening_frozen,10)
        initial=frozen_opening["state"]; frozen_auth=auth(initial)
        pre={**auth(f),"paused":True}
        require(opening_clock(initial) and initial["tick"]>=f["tick"] and opening_state(initial) and frozen_auth==pre,
                "stock pause outside frozen opening bound or with real public authority drift")
        receipt["opening_pause"]={"tick":initial["tick"],"camera":initial["hud"]["camera"],"pause_target":pause[0],
            "gl":frozen_opening["gl"]}
        def verify_paused_route(o):
            s=o.get("state"); menu=o.get("menu") or {}
            require(bool(s) and dims(o) and s["build"]==row["build"] and menu.get("match_exists") and not menu.get("visible")
                    and s["tick"]==initial["tick"] and auth(s)==frozen_auth and drew(o["gl"]),
                    "ordinary paused stock camera route changed clock, public authority or GL")
            return s

        # Real stock two-finger pan, not a gameplay bridge command. Godot
        # deliberately keeps two-finger world navigation available while paused.
        # Small matched moves stay within the live game's pinch slop.
        receipt["actual_two_finger_route"]={"starts":NORTH_FINGERS,"steps":NORTH_STEPS,"completed_swipes":0,"frozen_checks":[]}
        def pair(dx,dy):
            return [{"x":x+dx,"y":y+dy,"id":i+1} for i,(x,y) in enumerate(NORTH_FINGERS)]
        for repeat in range(NORTH_SWIPE_COUNT):
            cdp("Input.dispatchTouchEvent",{"type":"touchStart","touchPoints":pair(0,0)})
            for dx,dy in NORTH_STEPS:
                cdp("Input.dispatchTouchEvent",{"type":"touchMove","touchPoints":pair(dx,dy)})
            cdp("Input.dispatchTouchEvent",{"type":"touchEnd","touchPoints":[]})
            receipt["actual_two_finger_route"]["completed_swipes"]+=1
            held=verify_paused_route(observe())
            receipt["actual_two_finger_route"]["frozen_checks"].append({"tick":held["tick"],"camera":held["hud"]["camera"]})
        def aimed():
            o=observe()
            verify_paused_route(o)
            return o if world(o,north=True) else None
        e=until(aimed,8)
        aimed_state=e["state"]
        receipt["actual_two_finger_route"].update(public_camera=aimed_state["hud"]["camera"],tick=aimed_state["tick"])
        receipt["early_battlefield"]={"tick":initial["tick"],"time":initial["time"],"tick_delta":initial["tick"]-f["tick"],
            "camera":aimed_state["hud"]["camera"],"gl":e["gl"],"public_auth_diff":{k:[pre[k],frozen_auth[k]] for k in pre if pre[k]!=frozen_auth[k]}}
        receipt["first_battlefield_png_sha256"]=diagnostic("first-battlefield")
        top=[6,6,556,54];bottom=[6,223,556,91]
        settle_started=time.monotonic()
        def settled():
            o=observe()
            if not (world(o,north=True) and drew(o["gl"])):return None
            s=o["state"];h=s["hud"]
            require(s["tick"]==initial["tick"] and auth(s)==frozen_auth,"post-pause tick/selection/orders/economy changed")
            # Survival skips the persistent lesson, but the real Pause toast
            # lasts 30 presentation seconds. Keep the original strict masks:
            # wait for its actual Details button to leave the world lane.
            if len(h["buttons"])>=4 and all(contains(top,b["rect"]) or contains(bottom,b["rect"]) for b in h["buttons"]) and o["gl"]["maskDrawn"]>=e["gl"]["maskDrawn"]+4:
                return o
        # Pause toast is 30 simulation-display seconds at <=0.1/frame.
        # The prior two stock roles reached its actual boundary at ~120s.
        observed=until(settled,TERRAIN_SETTLE_TIMEOUT)
        receipt["settle"]={"wall_seconds":round(time.monotonic()-settle_started,3),
            "mask_draw_delta_after_pause":observed["gl"]["maskDrawn"]-e["gl"]["maskDrawn"]}
        sh=observed["state"]["hud"]
        require(contains(bottom,sh["action_scroll"]["rect"]) and sh["action_scroll"]["rect"][2]>0 and any(b["text"]=="繼續" and contains(top,b["rect"]) for b in sh["buttons"]),"paused stock HUD and bottom action strip must be visible")
        w={"camera":sh["camera"]["focus"],"zoom":sh["camera"]["zoom"],"size":list(SIZE),"map_half":40,
            "public_authority":frozen_auth,"public_hud":sh,"projection":projection(sh["camera"]["focus"],22,*SIZE),"top":top,"bottom":bottom,"minimap":[]}
        receipt["runtime"]={"w":w,"gl":observed["gl"],"tick":initial["tick"],"css":observed["css"],"rect":observed["rect"]}
        element=call("POST",prefix+"/element",{"using":"css selector","value":"#canvas"})
        eid=element["element-6066-11e4-a52e-4f735466cecf"]
        image=base64.b64decode(call("GET",prefix+"/element/"+eid+"/screenshot"),validate=True)
        require(image.startswith(b"\x89PNG\r\n\x1a\n"),"ChromeDriver did not emit original canvas PNG")
        (out/f"{role}.png").write_bytes(image)
        receipt["unmodified_canvas_png_sha256"]=sha(image)
        receipt["audit_console"]=logs()
        require(not any(ERROR.search(x.get("message","")) for k in ("menu_console","audit_console") for x in receipt[k]),
                "browser console reported a shader/GL/runtime error")
        final=observe()
        require(world(final,north=True) and drew(final["gl"]) and final["state"]["tick"]==initial["tick"] and final["state"]["hud"]==sh and auth(final["state"])==frozen_auth,"game state or GL changed during actual canvas screenshot")
        receipt["pass"]=True
      except Exception as e:
        receipt["error"]=str(e)
        if prefix:
            try:
                receipt["failure_console"]=logs()
                if "diagnostic" in locals():receipt["nonpassing_canvas_sha256"]=diagnostic("nonpassing-diagnostic")
                if "observe" in locals():receipt["nonpassing_last_state"]=observe()
            except Exception:pass
        raise
      finally:
        jdump(out/f"{role}-browser.json",receipt)
        if prefix:
            try:call("DELETE",prefix)
            except Exception:pass
        if owned.poll() is None:
            owned.terminate()
            try:owned.wait(timeout=5)
            except subprocess.TimeoutExpired:owned.kill();owned.wait()

def pixels(a,b,old,new,verify):
    require(all(old[k]==new[k] for k in ("camera","zoom","size","map_half","public_authority","public_hud","projection","top","bottom","minimap")),"matched camera, public observations and visible HUD A/B mismatch")
    require(northerly_camera({"focus":old["camera"],"zoom":old["zoom"]}) and old["size"]==list(SIZE),"actual actor-free native witness dimensions/camera")
    ar,ast=verify.png(a,list(SIZE));br,bst=verify.png(b,list(SIZE))
    v=old["projection"];half=old["map_half"];limits=("top","bottom","minimap")
    c={k:0 for k in ("inside","inside_changed_over2","outside","old_bright","new_bright","seam","old_bright_seam","new_bright_seam","inner_flank","inner_changed_over2")}
    for y,(x0,x1) in enumerate(zip(ar,br,strict=True)):
      for x in range(SIZE[0]):
        if any(verify.rect_has(old[key],x+.5,y+.5) for key in limits):continue
        m=max(abs(v[0][k]+x*v[1][k]+y*v[2][k]) for k in (0,2))
        ca=x0[x*ast:x*ast+3];cb=x1[x*bst:x*bst+3]
        delta=max(abs(i-j) for i,j in zip(ca,cb))
        ba,bb=verify.bright_grass(ca),verify.bright_grass(cb)
        if m<=half-.12:
            c["inside"]+=1;c["inside_changed_over2"]+=delta>2
        if m>half+.12:
            c["outside"]+=1;c["old_bright"]+=ba;c["new_bright"]+=bb
        if abs(m-half)<=.12:
            c["seam"]+=1;c["old_bright_seam"]+=ba;c["new_bright_seam"]+=bb
            if m<=half-.012:
                c["inner_flank"]+=1;c["inner_changed_over2"]+=delta>2
    return c
def satisfy(c):
    return (c["inside"]>=1000 and c["outside"]>=1000 and c["old_bright"]>=500 and
        c["inside_changed_over2"]<=c["inside"]*.001 and c["new_bright"]<=c["old_bright"]*.05 and
        c["seam"]>=300 and c["old_bright_seam"]>=100 and c["new_bright_seam"]==0 and
        c["inner_flank"]>=100 and c["inner_changed_over2"]==0)
def main():
    input_path=Path(sys.argv[1]).resolve()
    out=Path(sys.argv[2]).resolve();out.mkdir()
    pins=json.loads(input_path.read_text())
    require(pins["mode"]=="HOSTED_STOCK_ONLY","candidate formal archive pins pending")
    require(os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
            os.environ.get("GITHUB_REPOSITORY")=="penny323mo/valley-crown" and os.environ.get("GITHUB_REF")=="refs/heads/main",
            "fresh official hosted workflow only")
    for name in ("gl-observe.js",):
        require(sha((HERE/name).read_bytes())==pins["fixtures"][name],"exact frozen fixture identity: "+name)
    vis=ROOT/"ci/map-edge-veil-seam/verify-map-edge.py"
    require(sha(vis.read_bytes())==pins["fixtures"]["verify-map-edge.py"],"exact existing native PNG primitive verifier")
    verify=loader("verify_map_edge",vis)
    with tempfile.TemporaryDirectory(prefix="map-edge-stock-",dir=os.environ["RUNNER_TEMP"]) as d:
      temp=Path(d);stage=temp/"serve";stage.mkdir()
      prepare(pins,stage,out)
      os.environ.pop("GH_TOKEN",None)
      chrome=shutil.which("google-chrome")
      driver=shutil.which("chromedriver") or str(Path(os.environ.get("CHROMEWEBDRIVER","/nonexistent"))/"chromedriver")
      require(chrome and Path(driver).is_file(),"stock Chrome/ChromeDriver unavailable")
      with http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(Local,directory=str(stage))) as server:
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            url=f"http://127.0.0.1:{server.server_port}"
            role_errors={}
            for role in ROLES:
                try:browser(temp,out,pins[role],role,driver,chrome,url)
                except Exception as error:role_errors[role]=str(error)
        finally:server.shutdown()
    if role_errors:
        jdump(out/"nonpassing-roles.json",{"pass":False,"role_errors":role_errors})
        raise RuntimeError("one or both stock renderer roles did not meet proof conditions; see exact receipts")
    a,b=(json.loads((out/f"{r}-browser.json").read_text()) for r in ROLES)
    c=pixels(out/"baseline.png",out/"candidate.png",a["runtime"]["w"],b["runtime"]["w"],verify)
    result={"pass":satisfy(c),"scope":"Exact unmodified stock exports via ordinary touch menu with paused early Survival at the ordinary actor-free north-west camera, hosted Chrome WebGL2 and strict original canvas PNG; public observations only, not Safari/iPhone.",
        "pixels":c,"images":{q["role"]:q["unmodified_canvas_png_sha256"] for q in (a,b)}}
    jdump(out/"comparison.json",result);print(json.dumps(result))
    require(result["pass"] and len(set(result["images"].values()))==2,"measured Web west edge proof failed")
if __name__=="__main__":main()
