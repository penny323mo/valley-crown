#!/usr/bin/env python3
"""Exact tiny-landscape topbar readout; ordinary stock touch on original Standard exports."""
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
W,H=480,270
VIEW=[W,H,1,W,H,0,0,W,H]
BANK={"food":150000,"wood":200000,"stone":100000,"iron":0}
HOME={"focus":[-25,0,24],"zoom":22}
WORKER={"focus":[-28.5,0,27.5],"zoom":22}
MENU=(("home","StartMatchButton","開始戰役",[24,38,162,54]),
      ("battle_groups","BattleGroup0","經濟對戰",[46,50,108,54]),
      ("battle_options","ChooseBattle_standard","標準戰役",[160,114,108,54]),
      ("setup","LaunchMatchButton","出征",[214,114,108,54]))
OLD_MENU=[465,10,15,46]; NEW_MENU=[404,10,60,46]
OLD_PAUSE=[395,10,60,46]; NEW_PAUSE=[338,10,60,46]
INLINE_IDLE=[286,10,46,46]; BASE_IDLE=[108,206,344,46]; PINNED_IDLE=[336,76,60,46]
DRAWER_CLOSE=[400,76,60,46]
GL_JS=COMMON/"gl-observe.js"

def menu_target(o,page,identity,copy,rect):
    m=o.get("menu") or {}
    if not m.get("visible") or m.get("match_exists") or m.get("page")!=page or o.get("viewport")!=VIEW:return None
    found=[x for x in m["buttons"] if x["id"]==identity and x["text"]==copy and x["rect"]==rect]
    return found[0] if len(found)==1 else None

def button(s,text,rect):
    found=[b for b in s["hud"]["buttons"] if b["text"]==text and b["rect"]==rect and not b["disabled"] and not b["in_action_scroll"]]
    return found[0] if len(found)==1 else None

def authority(s):
    return {k:s[k] for k in ("bank_milli","age","population","capacity","built","trained","delivered","own_pending_commands",
                             "build_mode","touch_mode","control_ticks","military_techs","victory_mode","game_over","outcome")}
def unchanged(s):
    return authority(s)=={"bank_milli":BANK,"age":1,"population":6,"capacity":10,"built":0,"trained":0,"delivered":0,
                          "own_pending_commands":0,"build_mode":"","touch_mode":False,"control_ticks":[0,0],
                          "military_techs":[],"victory_mode":"conquest","game_over":False,"outcome":""}
def opening(s,base):
    if not unchanged(s) or s["selected"]!=[0] or s["paused"] or s["hud"]["camera"]!=HOME:return False
    m=button(s,"閒置" if base else "選單",OLD_MENU if base else NEW_MENU)
    p=button(s,"暫停",OLD_PAUSE if base else NEW_PAUSE)
    d=button(s,"閒置",INLINE_IDLE)
    return bool(m and p and not button(s,"關閉",DRAWER_CLOSE) and (d is None if base else d is not None))

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
        def hit(label,b,allow_old_clipped=False):
            R(b is not None and stock.contains([0,0,W,H],b["rect"]) and (min(b["rect"][2:])>=44 or allow_old_clipped and b["rect"]==OLD_MENU),"required visible touch control missing")
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
        proof["phase"]="01 genuine 480×270 Standard picker"
        call("POST",prefix+"/url",{"url":f"{web}/{role}/index.html?qa=1"})
        stock.until(lambda:(lambda o: gl_ok(o["gl"]) and not o["gl"]["maskDrawn"] and menu_target(o,*MENU[0]))(observe()),60)
        proof["menu_console"]=logs()
        for route in MENU:
            b=stock.until(lambda:menu_target(observe(),*route),12)
            times=call("POST",prefix+"/execute/async",{"script":"const d=arguments[arguments.length-1];requestAnimationFrame(a=>requestAnimationFrame(b=>d([a,b])));","args":[]})
            R(len(times)==2 and times[1]>times[0] and menu_target(observe(),*route)==b,"exact visible ordinary menu button not settled")
            hit(route[1],b);proof["menu"].append({"button":b,"frames":times})
        base=role=="baseline"
        m,p=(OLD_MENU,OLD_PAUSE) if base else (NEW_MENU,NEW_PAUSE)
        proof["phase"]="02 exact real awake starting toolbar, clipped vs complete"
        start=sample(lambda s:opening(s,base),35)["s"]
        proof["frames"]["opening"]=start
        png("opening")
        def same(s,sel,focus,paused):
            return authority(s)==authority(start) and s["selected"]==sel and s["hud"]["camera"]==focus and s["paused"] is paused
        if base:
            proof["phase"]="03 old clipped control opens drawer, does not select a worker"
            hit("clipped old Menu",button(start,"閒置",m),True)
            opened=sample(lambda s:same(s,[0],HOME,False) and button(s,"收起",m) and button(s,"關閉",DRAWER_CLOSE) and button(s,"閒置村民 5 · 下一位",BASE_IDLE))["s"]
            proof["frames"]["menu_open"]=opened
            hit("drawer Idle worker",button(opened,"閒置村民 5 · 下一位",BASE_IDLE))
        else:
            proof["phase"]="03 genuine dedicated Idle is first battlefield input"
            hit("direct 46×46 Idle",button(start,"閒置",INLINE_IDLE))
        proof["phase"]="04 worker selected and focused, no public order/payment change"
        worker=sample(lambda s:same(s,[1],WORKER,False) and not button(s,"關閉",DRAWER_CLOSE) and button(s,"暫停",p))["s"]
        proof["frames"]["worker"]=worker
        proof["phase"]="05 actual Pause retains worker/authority with Resume shown"
        hit("Pause",button(worker,"暫停",p))
        q=sample(lambda s:same(s,[1],WORKER,True) and button(s,"繼續",p))["s"]
        proof["frames"]["paused"]=q
        if not base:
            proof["phase"]="06 real full-width Menu opens without advancing the paused match"
            hit("full 60px Menu",button(q,"選單",m))
            o=sample(lambda s:same(s,[1],WORKER,True) and s["tick"]==q["tick"] and button(s,"收起",m) and button(s,"關閉",DRAWER_CLOSE) and button(s,"閒置5",PINNED_IDLE))
            proof["frames"]["menu_open"]=o["s"]
        else:
            o=sample(lambda s:same(s,[1],WORKER,True) and s["tick"]==q["tick"] and button(s,"繼續",p))
        proof["phase"]="07 real renderer/console and actual paused state"
        proof["runtime_gl"]=o["gl"];proof["final_console"]=logs()
        R(not any(stock.ERROR.search(x.get("message","")) for k in ("menu_console","final_console") for x in proof[k]),"actual browser shader/runtime error")
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
    R(pins["mode"]=="BOUND_HOSTED_TOOLBAR" and os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and os.environ.get("GITHUB_REPOSITORY")=="penny323mo/valley-crown" and os.environ.get("GITHUB_REF")=="refs/heads/main","only bound official hosted run is allowed")
    R(stock.sha(GL_JS.read_bytes())==pins["fixtures"]["gl-observe.js"] and stock.sha((COMMON/"stock-proof.py").read_bytes())==pins["fixtures"]["stock-proof.py"],"exact reviewed helper/observer identity")
    with tempfile.TemporaryDirectory(prefix="short-toolbar-web-",dir=os.environ["RUNNER_TEMP"]) as d:
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
    result={"pass":not errors,"errors":errors,"scope":"Original exact stock Chrome WebGL2, 480×270 CSS/canvas; real Standard touch route and public readouts. No pixel equality, Safari/iPhone or deployment claim.","images":{**a["images"],**b["images"]}}
    stock.jdump(out/"comparison.json",result);print(json.dumps(result))
    R(not errors and a["browser"]==b["browser"],"one or both stock toolbar roles failed or differed in browser version")
if __name__=="__main__":main()
