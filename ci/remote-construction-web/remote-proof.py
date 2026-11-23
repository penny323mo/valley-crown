#!/usr/bin/env python3
"""Proof of ordinary no-pan Practice placement through prior real worker movement and visible UI."""
import base64,functools,hashlib,http.server,json,os,pathlib,shutil,socket,struct,subprocess,sys,tempfile,threading,time
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
W,H=568,320
VIEW=[W,H,1,W,H,0,0,W,H]
BANK={"food":150000,"wood":200000,"stone":100000,"iron":0}
PAID={**BANK,"wood":150000}
HOME={"focus":[-25,0,24],"zoom":22}
MENU=(("home","StartMatchButton","開始戰役",[64,88,162,54]),
      ("battle_groups","BattleGroup0","經濟對戰",[46,100,108,54]),
      ("battle_options","ChooseBattle_practice","防守練習",[46,164,108,54]),
      ("setup","LaunchMatchButton","出征",[338,132,198,54]))
INITIAL=[212.327987670898,157.69514465332]
FIRST=[162.108825683594,167.403091430664]
BACK=[206.964782714844,191.203231811523]
GHOST=[110.914527893066,177.223815917969]
SITE=[110.914527893066,166.075317382812]
SELECT=[212,158]; OUT=[162,174]; RETURN=[207,198]; PLOT=[111,181]
HOUSE=[140,232,100,70]; CONFIRM=[16,254,120,48]; CANCEL=[206,254,110,48]; RECON=[324,254,112,48]
GL_JS=COMMON/"gl-observe.js"

def menu_target(o,page,identity,copy,rect):
    m=o.get("menu") or {}
    if not m.get("visible") or m.get("match_exists") or m.get("page")!=page or o.get("viewport")!=VIEW:return None
    found=[x for x in m["buttons"] if x["id"]==identity and x["text"]==copy and x["rect"]==rect]
    return found[0] if len(found)==1 else None

def button(s,text,rect,enabled=True):
    b=[b for b in s["hud"]["buttons"] if b["text"]==text and b["rect"]==rect and b["disabled"]==(not enabled)]
    return b[0] if len(b)==1 else None
def close(a,b):
    return isinstance(a,list) and len(a)==len(b) and all(abs(x-y)<.20 for x,y in zip(a,b))
def worker(s,pos):
    return any(a["id"]==1 and a["kind"]=="villager" and close(a["screen"],pos) for a in s["hud"]["own_targets"])
def rested(s,pos):
    return unchanged(s) and s["selected"]==[1] and not s["build_mode"] and worker(s,pos) and "待命" in s["hud"]["selection_detail"]
def unchanged(s):
    return s["hud"]["camera"]==HOME and not s["paused"] and not s["game_over"] and s["victory_mode"]=="conquest" and s["age"]==1 and s["population"]==6 and s["capacity"]==10 and not s["touch_mode"] and not s["own_pending_commands"] and not s["trained"] and not s["built"] and not s["delivered"] and s["bank_milli"]==BANK
def held(s,ok):
    p=s["hud"]["preview"] or {}
    return unchanged(s) and s["selected"]==[1] and s["build_mode"]=="house" and p.get("held") is True and p.get("placement_ok") is ok and close(p.get("screen"),GHOST) and button(s,"確認建造",CONFIRM,ok) is not None
def named(s,label):
    return any(b["text"]==label for b in s["hud"]["buttons"])
def armed(s):
    p=s["hud"]["preview"] or {}
    return unchanged(s) and s["selected"]==[1] and s["build_mode"]=="house" and p.get("held") is False and button(s,"確認建造",CONFIRM,False) is not None
def fogged(s,role):
    if not held(s,False) or not worker(s,BACK):return False
    detail=s["hud"]["selection_detail"]
    if role=="baseline":return not named(s,"前往查看") and detail=="不可建造：先派村民探索建築範圍"
    return button(s,"前往查看",RECON) is not None and detail=="已探索 · 查看不扣資源"
def revealed(s):
    return held(s,True) and worker(s,FIRST) and not named(s,"前往查看")
def paid(s):
    q=[a for a in s["hud"]["own_targets"] if a["kind"]=="house" and a["category"]=="building"]
    return s["hud"]["camera"]==HOME and s["selected"]==[1] and not s["build_mode"] and s["bank_milli"]==PAID and not s["built"] and not s["own_pending_commands"] and not s["paused"] and not s["game_over"] and len(q)==1 and not q[0]["built"] and close(q[0]["screen"],SITE)

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
        def ground(label,p):
            proof["touches"].append({"label":label,"point":p})
            touch(p)
        proof["phase"]="01 exact real Practice menu"
        call("POST",prefix+"/url",{"url":f"{web}/{role}/index.html?qa=1"})
        stock.until(lambda:(lambda o:gl_ok(o["gl"]) and not o["gl"]["maskDrawn"] and menu_target(o,*MENU[0]))(observe()),60)
        proof["menu_console"]=logs()
        for route in MENU:
            b=stock.until(lambda:menu_target(observe(),*route),12)
            stamps=call("POST",prefix+"/execute/async",{"script":"const d=arguments[arguments.length-1];requestAnimationFrame(a=>requestAnimationFrame(b=>d([a,b])));","args":[]})
            R(len(stamps)==2 and stamps[1]>stamps[0] and menu_target(observe(),*route)==b,"exact picker button not settled")
            hit(route[1],b);proof["menu"].append({"button":b,"frames":stamps})
        proof["phase"]="02 actual original villager selection, no order/payment"
        proof["frames"]["opening"]=sample(lambda s:unchanged(s) and s["selected"]==[0] and worker(s,INITIAL),35)["s"]
        ground("actual owned villager",SELECT)
        proof["frames"]["selected"]=sample(lambda s:rested(s,INITIAL) and button(s,"民居\n木 50",HOUSE))["s"]
        proof["phase"]="03 ordinary ground MOVE out to reveal the site"
        ground("real Move out",OUT)
        reached=sample(lambda s:rested(s,FIRST) and button(s,"民居\n木 50",HOUSE),28)["s"]
        proof["frames"]["first_arrival"]=reached
        proof["phase"]="04 actual first-view legal preview, then cancel unpaid"
        hit("House before withdrawal",button(reached,"民居\n木 50",HOUSE))
        sample(armed)
        ground("hold exact original site in sight",PLOT)
        first=sample(lambda s:held(s,True) and worker(s,FIRST))["s"]
        proof["frames"]["first_visible_preview"]=first
        hit("Cancel first unpaid preview",button(first,"取消建造",CANCEL))
        sample(lambda s:rested(s,FIRST))
        proof["phase"]="05 same villager withdraws by ordinary Move, no camera changes"
        ground("real Move back",RETURN)
        withdrawn=sample(lambda s:rested(s,BACK) and button(s,"民居\n木 50",HOUSE),28)["s"]
        proof["frames"]["withdrawn"]=withdrawn
        proof["phase"]="06 identical already explored but now fogged site"
        hit("House after withdrawal",button(withdrawn,"民居\n木 50",HOUSE));sample(armed)
        ground("hold exact same site back in fog",PLOT)
        base=role=="baseline"
        fog=lambda s:fogged(s,role)
        x=sample(fog)
        proof["frames"]["remembered_held"]=x["s"]
        png("same-held-fog")
        if not base:
            proof["phase"]="07 one genuine Recon touch, no automatic build or manual re-tap"
            hit("actual one-tap Recon",button(x["s"],"前往查看",RECON))
            show=sample(revealed,36)["s"]
            proof["frames"]["same_site_visible_again"]=show
            R([t["label"] for t in proof["touches"][-2:]]==
              ["hold exact same site back in fog","actual one-tap Recon"] and
              len([t for t in proof["touches"] if t["point"]==PLOT])==2 and
              show["tick"]>proof["frames"]["remembered_held"]["tick"],"unexpected world retap/missing real travel")
            png("held-revealed-without-retap")
            proof["phase"]="08 only actual separate Confirm spends 50 and starts House"
            hit("separate explicit Confirm",button(show,"確認建造",CONFIRM))
            x=sample(paid,25)
            proof["frames"]["paid_house"]=x["s"]
        else:
            x=sample(fog)
        proof["phase"]="09 actual Chrome WebGL2 renderer and console"
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

def main():
    pins=json.loads(pathlib.Path(sys.argv[1]).read_text());out=pathlib.Path(sys.argv[2]);out.mkdir()
    R(pins["mode"]=="BOUND_HOSTED_REMOTE_CONSTRUCTION" and os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and os.environ.get("GITHUB_REPOSITORY")=="penny323mo/valley-crown" and os.environ.get("GITHUB_REF")=="refs/heads/main","only bound official hosted run is allowed")
    R(stock.sha(GL_JS.read_bytes())==pins["fixtures"]["gl-observe.js"] and stock.sha((COMMON/"stock-proof.py").read_bytes())==pins["fixtures"]["stock-proof.py"],"exact reviewed helper/observer identity")
    with tempfile.TemporaryDirectory(prefix="remote-construction-web-",dir=os.environ["RUNNER_TEMP"]) as d:
      temp=pathlib.Path(d);stage=temp/"serve";stage.mkdir()
      stock.prepare(pins,stage,out)
      os.environ.pop("GH_TOKEN",None)
      chrome=shutil.which("google-chrome")
      driver=shutil.which("chromedriver") or str(pathlib.Path(os.environ.get("CHROMEWEBDRIVER","/nonexistent"))/"chromedriver")
      R(chrome and pathlib.Path(driver).is_file(),"stock Chrome and matching driver required")
      errors={}
      with http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(stock.Local,directory=str(stage))) as server:
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
          for arm in ("baseline","candidate"):
            try:browser(temp,out,pins[arm],arm,driver,chrome,f"http://127.0.0.1:{server.server_port}")
            except Exception as error:errors[arm]=str(error)
        finally:server.shutdown()
    a,b=(json.loads((out/(k+"-browser.json")).read_bytes()) for k in ("baseline","candidate"))
    same_browser=bool(a.get("browser")) and a.get("browser")==b.get("browser")
    result={"pass":not errors and same_browser,"browser_version_exact_match":same_browser,"errors":errors,"scope":"Original stock Chromium 568x320, ordinary Practice no-pan movement, no fog injection, native QA is read only. No Safari/iPhone or deployment claim.","images":{**a["images"],**b["images"]}}
    stock.jdump(out/"comparison.json",result);print(json.dumps(result))
    R(result["pass"],"one or both exact stock recon arms failed or browser versions differ")
if __name__=="__main__":main()
