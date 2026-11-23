#!/usr/bin/env python3
"""Exact stock Standard quiet return from a genuine natural AI attack. No clock or state injection."""
import re,base64,functools,hashlib,http.server,json,os,pathlib,shutil,socket,struct,subprocess,sys,tempfile,threading,time
from urllib.error import HTTPError
from urllib.request import Request,ProxyHandler,build_opener

HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parent.parent
COMMON=HERE.parent/"map-edge-webgl-stock"
sys.path.insert(0,str(COMMON))
import importlib.util
spec=importlib.util.spec_from_file_location("stock_helpers",COMMON/"stock-proof.py")
stock=importlib.util.module_from_spec(spec);spec.loader.exec_module(stock)
R=stock.require
W,H=480,270
VIEW=[W,H,1,W,H,0,0,W,H]
BANK={"food":150000,"wood":200000,"stone":100000,"iron":0}
HOME=[-25,0,24]
FIRST=[-20.2410564422607,0,22.2529811859131]
MENU=(("home","StartMatchButton","開始戰役",[24,38,162,54]),
      ("battle_groups","BattleGroup0","經濟對戰",[46,50,108,54]),
      ("battle_options","ChooseBattle_standard","標準戰役",[160,114,108,54]),
      ("setup","LaunchMatchButton","出征",[214,114,108,54]))
GL_JS=COMMON/"gl-observe.js"
ACK_WINDOW=(3692,3820)
WAIT_FIRST_NATURAL_ALERT=320
ACK_DWELL=400
AVAIL_CHECK_MAX=4700
RETURN_RECT=[348,126,56,46]
IDLE_MENU_RECT=[404,10,60,46]

def menu_target(o,page,identity,copy,rect):
    m=o.get("menu") or {}
    if not m.get("visible") or m.get("match_exists") or m.get("page")!=page or o.get("viewport")!=VIEW:return None
    found=[x for x in m["buttons"] if x["id"]==identity and x["text"]==copy and x["rect"]==rect]
    return found[0] if len(found)==1 else None
def buttons(s,text):
    return [b for b in s["hud"]["buttons"] if b["text"]==text]
def reachable(s,text,rect=None):
    found=[b for b in buttons(s,text) if not b["disabled"] and not b["in_action_scroll"]
           and (rect is None or b["rect"]==rect)
           and stock.contains([0,0,W,H],b["rect"]) and min(b["rect"][2:])>=44]
    return found[0] if len(found)==1 else None
def has_unread(s):
    return any(re.fullmatch(r"受襲[1-4]",b["text"]) for b in s["hud"]["buttons"])
def close(a,b,eps=.001):
    return isinstance(a,list) and len(a)==len(b) and all(abs(x-y)<=eps for x,y in zip(a,b))
def same_focus(s,p):
    return s["hud"]["camera"]["zoom"]==22 and close(s["hud"]["camera"]["focus"],p)
def hp(s):
    m=re.match(r"^生命 (\d+) / 1200(?:\s|$)",s["hud"]["selection_detail"])
    return int(m[1]) if m else None
def authority(s):
    return s["hud"]["camera"]["zoom"]==22 and s["selected"]==[0] and not s["paused"] and not s["game_over"] and s["victory_mode"]=="conquest" and s["age"]==1 and s["bank_milli"]==BANK and not s["build_mode"] and not s["touch_mode"] and not s["own_pending_commands"] and not s["trained"] and not s["built"] and not s["delivered"]
def world_to_screen(focus,zoom,target):
    # Same stock camera offset + orthographic KEEP_HEIGHT as game.gd. No
    # browser state input: only project already-known starting friendly site.
    from math import sqrt
    d=[x-y for x,y in zip(target,focus,strict=True)]
    off=[19,25,23]; upright=sqrt(19**2+23**2); total=sqrt(sum(q*q for q in off))
    right=[23/upright,0,-19/upright]
    back=[q/total for q in off]
    up=[back[1]*right[2],back[2]*right[0]-back[0]*right[2],-back[1]*right[0]]
    return [W/2+sum(d[i]*right[i] for i in range(3))*H/zoom,H/2-sum(d[i]*up[i] for i in range(3))*H/zoom]
def off_camera(s,target):
    x,y=world_to_screen(s["hud"]["camera"]["focus"],s["hud"]["camera"]["zoom"],target)
    return x < -10 or y < -10 or x > W+10 or y > H+10

def browser(temp,out,row,role,driver,chrome,web):
    with socket.socket() as sock:sock.bind(("127.0.0.1",0));port=sock.getsockname()[1]
    url=f"http://127.0.0.1:{port}"
    opener=build_opener(ProxyHandler({}));prefix=""
    def call(method,path,data=None):
        try:
            req=Request(url+path,json.dumps(data).encode() if data is not None else None,{"content-type":"application/json"},method=method)
            with opener.open(req,timeout=30) as r:return json.load(r)["value"]
        except HTTPError as e:raise RuntimeError(f"WebDriver {e.code}: {e.read().decode(errors='replace')[:1300]}") from None
    def cdp(command,args):return call("POST",prefix+"/goog/cdp/execute",{"cmd":command,"params":args})
    def logs():return call("POST",prefix+"/log",{"type":"browser"})
    proof={"role":role,"expected":row,"menu":[],"images":{},"frames":{},"touches":[],"pass":False,"phase":"00 stock Chromium bootstrap"}
    with (out/(role+"-chromedriver.log")).open("wb") as log:
      proc=subprocess.Popen([driver,f"--port={port}","--allowed-ips=127.0.0.1"],stdout=log,stderr=log)
      try:
        def ready():
            if proc.poll() is not None:raise RuntimeError("ChromeDriver exited")
            try:return call("GET","/status").get("ready")
            except OSError:return False
        stock.until(ready,16)
        profile=temp/(role+"-fresh-chrome")
        profile.mkdir()
        options={"binary":chrome,"args":["--headless","--disable-background-networking","--no-first-run",
                f"--user-data-dir={profile}","--use-gl=angle","--use-angle=swiftshader","--force-device-scale-factor=1",
                "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1"],
                "mobileEmulation":{"deviceMetrics":{"width":W,"height":H,"pixelRatio":1,"mobile":True,"touch":True}}}
        session=call("POST","/session",{"capabilities":{"alwaysMatch":{"browserName":"chrome","goog:chromeOptions":options,
                "goog:loggingPrefs":{"browser":"ALL"},"pageLoadStrategy":"eager"}}})
        proof["browser"]=session["capabilities"]["browserVersion"];prefix="/session/"+session["sessionId"]
        args=cdp("Browser.getBrowserCommandLine",{})["arguments"]
        forbidden={"--no-sandbox","--disable-setuid-sandbox","--disable-gpu-sandbox","--enable-unsafe-swiftshader","--single-process"}
        R(not forbidden.intersection(s.partition("=")[0] for s in args),"stock Chrome sandbox altered")
        proof["sandbox_preserved"]=True
        cdp("Network.enable",{});cdp("Network.setBlockedURLs",{"urls":["https://*"]})
        cdp("Page.addScriptToEvaluateOnNewDocument",{"source":GL_JS.read_text()})
        def observe():
            return call("POST",prefix+"/execute/sync",{"script":"""const c=document.querySelector('#canvas'),r=c?.getBoundingClientRect();
              if(typeof valleyMenuSnapshot==='function')valleyMenuSnapshot();if(typeof valleySnapshot==='function')valleySnapshot();
              return {menu:window.valleyMenuState||null,s:window.valleyState||null,viewport:[innerWidth,innerHeight,devicePixelRatio,c?.width,c?.height,r?.x,r?.y,r?.width,r?.height],gl:window.vcGL||null};""","args":[]})
        def gl_ok(gl):
            c=(gl or {}).get("canvas") or {}
            return c.get("version","").startswith("WebGL 2.0") and c.get("glsl","").startswith("WebGL GLSL ES 3.00") and not gl["contextLost"] and not gl["errorCount"]
        def touch(at):
            x,y=at
            R(0<=x<W and 0<=y<H,"touch outside product")
            cdp("Input.dispatchTouchEvent",{"type":"touchStart","touchPoints":[{"x":x,"y":y,"id":1}]})
            cdp("Input.dispatchTouchEvent",{"type":"touchEnd","touchPoints":[]})
        def hit(label,b):
            R(b is not None and stock.contains([0,0,W,H],b["rect"]) and min(b["rect"][2:])>=44,"required visible touch control missing")
            x,y,w,h=b["rect"];point=[x+w/2,y+h/2]
            proof["touches"].append({"label":label,"point":point,"observed_rect":b["rect"],"text":b.get("text")})
            touch(point)
        def sample(fn,sec=14):
            def read():
                o=observe();s=o["s"];me=o["menu"] or {};g=o["gl"]
                return o if s and s["build"]==row["build"] and (s.get("hud") or {}).get("schema")==2 and s["hud"].get("viewport")==[W,H] and o["viewport"]==VIEW and me.get("match_exists") and not me.get("visible") and gl_ok(g) and min(g["maskCompiled"],g["maskLinked"],g["maskDrawn"])>0 and fn(s) else None
            return stock.until(read,sec)
        def png(name):
            el=call("POST",prefix+"/element",{"using":"css selector","value":"#canvas"})["element-6066-11e4-a52e-4f735466cecf"]
            raw=base64.b64decode(call("GET",prefix+"/element/"+el+"/screenshot"),validate=True)
            R(raw[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack(">II",raw[16:24])==(W,H),"not original landscape canvas PNG")
            path=role+"-"+name+".png";(out/path).write_bytes(raw);proof["images"][path]=hashlib.sha256(raw).hexdigest()
        proof["phase"]="01 exact real Standard menu"
        call("POST",prefix+"/url",{"url":f"{web}/{role}/index.html?qa=1"})
        stock.until(lambda:(lambda o:gl_ok(o["gl"]) and not o["gl"]["maskDrawn"] and menu_target(o,*MENU[0]))(observe()),60)
        proof["menu_console"]=logs()
        for route in MENU:
            b=stock.until(lambda:menu_target(observe(),*route),12)
            stamps=call("POST",prefix+"/execute/async",{"script":"const d=arguments[arguments.length-1];requestAnimationFrame(a=>requestAnimationFrame(b=>d([a,b])));","args":[]})
            R(len(stamps)==2 and stamps[1]>stamps[0] and menu_target(observe(),*route)==b,"exact picker button not settled")
            hit(route[1],b);proof["menu"].append({"button":b,"frames":stamps})
        proof["phase"]="02 deliberate regular two-finger pan, no order or camera injection"
        initial=sample(lambda s: authority(s) and same_focus(s,HOME) and hp(s)==1200,35)["s"]
        proof["frames"]["opening"]=initial
        def pan_to_leave(target,label):
            previous=sample(authority)["s"]
            R(not off_camera(previous,target),"ordinary pan must begin with site still in view")
            before=previous["hud"]["camera"]["focus"]
            # One genuine constant-separation swipe in the same clear y=145
            # terrain lane. 15 move samples avoid a large transient pinch
            # and remove 48 actual WebDriver round trips per departure.
            fingers=((390,145),(452,145))
            def pair(dx):
                return [{"x":x+dx,"y":y,"id":j+1} for j,(x,y) in enumerate(fingers)]
            cdp("Input.dispatchTouchEvent",{"type":"touchStart","touchPoints":pair(0)})
            for step in range(1,16):
                cdp("Input.dispatchTouchEvent",{"type":"touchMove","touchPoints":pair(-19*step)})
            cdp("Input.dispatchTouchEvent",{"type":"touchEnd","touchPoints":[]})
            previous=sample(lambda s:authority(s) and not close(s["hud"]["camera"]["focus"],before),8)["s"]
            R(off_camera(previous,target),"one genuine two-finger swipe did not move exact site fully offscreen")
            trace=[{"fingers":fingers,"both_delta":[-285,0],"move_samples":15,"received_camera":previous["hud"]["camera"],"tick":previous["tick"]}]
            proof["touches"].append({"label":label,"pans":trace})
            return previous
        proof["frames"]["pan_away_from_home"]=pan_to_leave(HOME,"ordinary two-finger pans away from home")
        proof["phase"]="03 first genuine natural unread alert, then real acknowledgement"
        u=sample(lambda s:authority(s) and ACK_WINDOW[0]<=s["tick"]<=ACK_WINDOW[1] and reachable(s,"受襲1",[344,10,54,46]),WAIT_FIRST_NATURAL_ALERT)["s"]
        proof["frames"]["first_unread"]=u
        hit("original stock unread fight",reachable(u,"受襲1",[344,10,54,46]))
        ack=sample(lambda s:authority(s) and same_focus(s,FIRST) and not has_unread(s) and reachable(s,"選單",IDLE_MENU_RECT),20)["s"]
        proof["frames"]["acknowledged"]=ack
        R(ack["tick"]<=ACK_WINDOW[1] and hp(ack) is not None,"no early ordinary first acknowledgement")
        proof["phase"]="04 same battle offscreen, damage continues naturally with no repeated unread"
        away=pan_to_leave(FIRST,"ordinary two-finger pans away after acknowledgement")
        proof["frames"]["pan_away_after_ack"]=away
        R(away["tick"]<AVAIL_CHECK_MAX,"offscreen swipe settled past the unchanged live Keep test window")
        last=[]
        def joined(s):
            life=hp(s)
            if not authority(s) or close(s["hud"]["camera"]["focus"],FIRST) or not off_camera(s,HOME) or not off_camera(s,FIRST) or life is None:return False
            R(not has_unread(s),"unexpected new unread during matched acknowledged battle")
            if not last or s["tick"]!=last[-1]["tick"]:last.append({"tick":s["tick"],"keep_hp":life})
            return s["tick"]>=ack["tick"]+ACK_DWELL and s["tick"]<=AVAIL_CHECK_MAX and 0<life<1155 and any(x["tick"]>=s["tick"]-140 and x["keep_hp"]>life for x in last)
        near=sample(joined,95)["s"]
        proof["frames"]["post_ack_active_keep_damage"]=near
        proof["hp_samples"]=last
        proof["phase"]="05 ordinary Menu shows old absence vs real pinned 56×46 Quiet"
        hit("original stock Menu",reachable(near,"選單",IDLE_MENU_RECT))
        def in_drawer(s):
            return authority(s) and close(s["hud"]["camera"]["focus"],near["hud"]["camera"]["focus"]) and not has_unread(s) and reachable(s,"收起",IDLE_MENU_RECT)
        s=sample(lambda s:in_drawer(s) and (not buttons(s,"回看") if role=="baseline" else reachable(s,"回看",RETURN_RECT)),18)["s"]
        proof["frames"]["quiet_menu"]=s
        png("matched-after-real-damage")
        x=sample(lambda s:in_drawer(s) and (not buttons(s,"回看") if role=="baseline" else reachable(s,"回看",RETURN_RECT)),10)
        if role=="candidate":
            proof["phase"]="06 real candidate-only Quiet makes current own hit site and visible combat reachable"
            hit("one explicit Quiet return",reachable(x["s"],"回看",RETURN_RECT))
            def returned(s):
                targets=[v for v in s["hud"]["context_targets"] if v["team"]==1 and v["category"]=="unit"]
                life=hp(s)
                return authority(s) and not has_unread(s) and not buttons(s,"回看") and same_focus(s,HOME) and reachable(s,"選單",IDLE_MENU_RECT) and targets and life is not None and 0<life<=hp(near)
            x=sample(returned,22)
            proof["frames"]["returned_to_own_hit"]=x["s"]
            png("one-touch-return")
        proof["phase"]="07 actual Chrome WebGL2 and no runtime errors, not physical iPhone"
        proof["runtime_gl"]=x["gl"];proof["final_console"]=logs()
        R(not any(stock.ERROR.search(a.get("message","")) for k in ("menu_console","final_console") for a in proof[k]),"browser runtime/GL error")
        proof["pass"]=True;proof["phase"]="PASS"
      except Exception as ex:
        proof["error"]=f"{proof['phase']}: {ex}"
        if prefix:
            try:
                proof["last"]=observe();png("nonpassing-diagnostic")
            except Exception:pass
        raise
      finally:
        stock.jdump(out/(role+"-browser.json"),proof)
        if prefix:
            try:call("DELETE",prefix)
            except Exception:pass
        if proc.poll() is None:
            proc.terminate()
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:proc.kill();proc.wait()

def stage_exact_role(pins,stage,out,role):
    r=pins[role]
    archive=stock.loader("quiet_archive",ROOT/"scripts/web_release_archive.py")
    R(stock.digest_fields(r),"exact immutable formal candidate pins missing")
    api=archive.GitHub("penny323mo/valley-crown")
    run=api.request(f"/actions/runs/{r['run_id']}")
    R(run["status"]=="completed" and run["conclusion"]=="success" and run["head_sha"]==r["formal_commit"] and run["head_branch"]=="main","exact successful formal head")
    rows=api.request(f"/actions/runs/{r['run_id']}/artifacts")
    found=[x for x in rows["artifacts"] if x["id"]==r["artifact_id"]]
    R(len(found)==1 and found[0]["workflow_run"]["id"]==r["run_id"] and not found[0]["expired"] and found[0]["digest"]=="sha256:"+r["zip_sha256"],"exact artifact appears, unexpired, immutable digest")
    data=api.request(f"/actions/artifacts/{r['artifact_id']}/zip",binary=True)
    hashes=stock.unpack(data,r,stage/role,archive)
    R(hashes=={f:stock.sha((stage/role/f).read_bytes()) for f in stock.FILES},"exact original game export")
    stock.jdump(out/"verified-inputs.json",{role:{"input":r,"stock_export_sha256":hashes}})

def main():
    pins=json.loads(pathlib.Path(sys.argv[1]).read_text());out=pathlib.Path(sys.argv[2]);role=sys.argv[3];out.mkdir()
    R(role in ("baseline","candidate") and pins["mode"]=="BOUND_HOSTED_QUIET_RETURN" and os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and os.environ.get("GITHUB_REPOSITORY")=="penny323mo/valley-crown" and os.environ.get("GITHUB_REF")=="refs/heads/main","only bound official hosted run is allowed")
    R(stock.sha(GL_JS.read_bytes())==pins["fixtures"]["gl-observe.js"] and stock.sha((COMMON/"stock-proof.py").read_bytes())==pins["fixtures"]["stock-proof.py"],"exact reviewed helper/observer identity")
    with tempfile.TemporaryDirectory(prefix="quiet-return-web-",dir=os.environ["RUNNER_TEMP"]) as d:
        temp=pathlib.Path(d);stage=temp/"serve";stage.mkdir()
        stage_exact_role(pins,stage,out,role)
        os.environ.pop("GH_TOKEN",None)
        chrome=shutil.which("google-chrome")
        driver=shutil.which("chromedriver") or str(pathlib.Path(os.environ.get("CHROMEWEBDRIVER","/nonexistent"))/"chromedriver")
        R(chrome and pathlib.Path(driver).is_file(),"stock Chrome and matching driver required")
        with http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(stock.Local,directory=str(stage))) as server:
            threading.Thread(target=server.serve_forever,daemon=True).start()
            try:browser(temp,out,pins[role],role,driver,chrome,f"http://127.0.0.1:{server.server_port}")
            finally:server.shutdown()
if __name__=="__main__":main()
