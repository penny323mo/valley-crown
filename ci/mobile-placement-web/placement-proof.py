#!/usr/bin/env python3
"""Read-only public QA projection; all placement actions use ordinary stock touch."""
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
BANK={"food":150000,"wood":200000,"stone":100000,"iron":0}
PAID={**BANK,"wood":120000}
MENU=(("home","StartMatchButton","開始戰役",[64,88,162,54]),
      ("battle_groups","BattleGroup3","劇本挑戰",[160,164,126,54]),
      ("battle_options","ChooseBattle_escort","護送拓荒隊",[46,164,126,54]),
      ("setup","LaunchMatchButton","出征",[338,74,198,54]))
FOCUS={"focus":[-7,0,6],"zoom":22}
BUILDER=3
MOVE=[286,173]
PLOT=[274,161]
GHOST=(272.786041259766,154.049987792969)
SITE=(272.786041259766,142.901504516602)
CONFIRM="確認建造"
WAREHOUSE="倉庫\n木 80"
BLOCKING_DETAILS=[500,119,54,46]
GL_JS=COMMON/"gl-observe.js"

def close(actual,expected):
    return isinstance(actual,list) and len(actual)==len(expected) and all(abs(a-b)<.18 for a,b in zip(actual,expected))

def button(s,text,enabled=None,prefix=False):
    found=[b for b in s["hud"]["buttons"] if ((b["text"].startswith(text) if prefix else b["text"]==text))
           and (enabled is None or b["disabled"] == (not enabled)) and min(b["rect"][2:])>=44
           and stock.contains([0,0,W,H],b["rect"])]
    return found[0] if len(found)==1 else None

def menu_target(o,page,identity,copy,rect):
    m=o.get("menu") or {}
    if not m.get("visible") or m.get("match_exists") or m.get("page")!=page or o.get("viewport")!=[W,H,1,W,H,0,0,W,H]:return None
    b=[x for x in m["buttons"] if x["id"]==identity and x["text"]==copy and x["rect"]==rect]
    return b[0] if len(b)==1 else None

def fields(s):
    return {k:s[k] for k in ("selected","bank_milli","built","trained","delivered","own_pending_commands","paused","game_over")}
def plot_unpaid(s):
    return fields(s)=={"selected":[BUILDER],"bank_milli":BANK,"built":0,"trained":0,"delivered":0,
                      "own_pending_commands":0,"paused":False,"game_over":False}
def before_ok(s):
    p=s["hud"]["preview"] or {}
    return s["build_mode"]=="storehouse" and plot_unpaid(s) and not p.get("held",True) and button(s,CONFIRM,False) is not None
def after_ok(s,base):
    p=s["hud"]["preview"] or {}
    if s["build_mode"]!="storehouse" or not plot_unpaid(s):return False
    if base:
        return not p.get("held",True) and button(s,CONFIRM,False) is not None and has_banner(s)
    return p.get("held") is True and p.get("placement_ok") is True and close(p.get("screen"),GHOST) and button(s,CONFIRM,True) is not None and s["hud"]["selection_detail"]=="前哨內 · 按確認" and not has_banner(s)
def has_banner(s):
    return any(b["text"]=="詳情" and not b["in_action_scroll"] and b["rect"]==BLOCKING_DETAILS for b in s["hud"]["buttons"])
def placed(s,unpaid_sites):
    sites=[x for x in s["hud"]["own_targets"] if x.get("category")=="building" and x.get("kind")=="storehouse"]
    same=[a for a in sites if a.get("id") not in unpaid_sites and not a.get("built") and close(a.get("screen"),SITE)]
    return s["bank_milli"]==PAID and not s["build_mode"] and s["built"]==0 and s["selected"]==[BUILDER] and not s["own_pending_commands"] and len(same)==1 and len(sites)==len(unpaid_sites)+1

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
    proof={"role":role,"expected":row,"menu":[],"images":{},"pass":False}
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
        def center(b):
            R(b is not None and stock.contains([0,0,W,H],b["rect"]) and min(b["rect"][2:])>=44,"visible control missing")
            x,y,w,h=b["rect"];return [x+w/2,y+h/2]
        def swipe(s):
            # True one-finger scrolling in the existing action strip, DOM pristine.
            x,y,w,h=s["hud"]["action_scroll"]["rect"]
            R(w>=150 and h>=44 and stock.contains([0,0,W,H],[x,y,w,h]),"actual HUD strip missing")
            a,b=int(x+w*.84),int(x+w*.17);y=int(y+h*.5)
            call("POST",prefix+"/actions",{"actions":[{"type":"pointer","id":"warehouse-strip","parameters":{"pointerType":"touch"},
                "actions":[{"type":"pointerMove","duration":60,"x":a,"y":y,"origin":"viewport"},{"type":"pointerDown","button":0},
                           {"type":"pause","duration":40},{"type":"pointerMove","duration":350,"x":b,"y":y,"origin":"viewport"},{"type":"pointerUp","button":0}]}]})
            proof.setdefault("hud_scroll",[]).append([[a,y],[b,y]])
        def sample(fn,sec=14):
            def read():
                o=observe();s=o["s"];me=o["menu"] or {};g=o["gl"]
                return o if s and s["build"]==row["build"] and (s.get("hud") or {}).get("schema")==2 and s["hud"].get("viewport")==[W,H] and o["viewport"]==[W,H,1,W,H,0,0,W,H] and me.get("match_exists") and not me.get("visible") and gl_ok(g) and min(g["maskCompiled"],g["maskLinked"],g["maskDrawn"])>0 and fn(s) else None
            return stock.until(read,sec)
        def png(name):
            el=call("POST",prefix+"/element",{"using":"css selector","value":"#canvas"})["element-6066-11e4-a52e-4f735466cecf"]
            raw=base64.b64decode(call("GET",prefix+"/element/"+el+"/screenshot"),validate=True)
            R(raw[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack(">II",raw[16:24])==(W,H),"not original landscape canvas PNG")
            path=role+"-"+name+".png";(out/path).write_bytes(raw);proof["images"][path]=hashlib.sha256(raw).hexdigest()
        call("POST",prefix+"/url",{"url":f"{web}/{role}/index.html?qa=1"})
        stock.until(lambda:(lambda o: gl_ok(o["gl"]) and not o["gl"]["maskDrawn"] and menu_target(o,*MENU[0]))(observe()),60)
        proof["menu_console"]=logs()
        for route in MENU:
            o=stock.until(lambda:menu_target(observe(),*route),12)
            ticks=call("POST",prefix+"/execute/async",{"script":"const d=arguments[arguments.length-1];requestAnimationFrame(a=>requestAnimationFrame(b=>d([a,b])));","args":[]})
            R(len(ticks)==2 and ticks[1]>ticks[0] and menu_target(observe(),*route)==o,"menu control not settled in two distinct display frames")
            touch(center(o));proof["menu"].append({"page":route[0],"button":o,"frames":ticks})
        def opening(s):
            return s["bank_milli"]==BANK and not s["selected"] and not s["game_over"] and not s["paused"] and button(s,"定位目標 · 護送拓荒隊",True,True) and any(x.get("id")==BUILDER and x["kind"]=="villager" and close(x["screen"],(241.484375,173.165237426758)) for x in s["hud"]["own_targets"])
        start=sample(opening,38)
        worker=next(x for x in start["s"]["hud"]["own_targets"] if x["id"]==BUILDER)
        proof["worker"]=worker;touch([round(x) for x in worker["screen"]])
        selected=sample(lambda s:s["selected"]==[BUILDER] and button(s,"定位目標 · 護送拓荒隊",True,True))["s"]
        touch(center(button(selected,"定位目標 · 護送拓荒隊",True,True)))
        focused=sample(lambda s:s["hud"]["camera"]==FOCUS and plot_unpaid(s))["s"]
        proof["move"]=MOVE;touch(MOVE)
        def arrived(s):
            return s["hud"]["camera"]==FOCUS and plot_unpaid(s) and any("建立前哨" in b["text"] and "倉庫 0/1" in b["text"] for b in s["hud"]["buttons"])
        a=sample(arrived,100)["s"]
        proof["arrived"]={"tick":a["tick"],"authority":fields(a),"camera":a["hud"]["camera"]}
        for _ in range(3):
            option=button(a,WAREHOUSE,True)
            if option:break
            swipe(a);a=sample(arrived)["s"]
        option=button(a,WAREHOUSE,True)
        touch(center(option))
        base=role=="baseline"
        before=sample(lambda s:s["hud"]["camera"]==FOCUS and before_ok(s) and has_banner(s)==base)["s"]
        proof["before_tap"]=before
        R(not any(x.get("kind")=="storehouse" for x in before["hud"]["own_targets"]),"warehouse already exists before the test")
        proof["plot_tap"]=PLOT;touch(PLOT)
        accepted=sample(lambda s:s["hud"]["camera"]==FOCUS and s["tick"]>before["tick"] and after_ok(s,base))["s"]
        R(accepted["tick"]>before["tick"] and fields(accepted)==fields(before),"touch did not traverse an actual state or changed authority")
        proof["after_tap"]=accepted;png("after-identical-tap")
        if not base:
            check=sample(lambda s:s["hud"]["camera"]==FOCUS and after_ok(s,False))["s"]
            R(fields(check)==fields(before),"capture changed placement authority")
            proof["confirm_tap"]=center(button(check,CONFIRM,True));touch(proof["confirm_tap"])
            result=sample(lambda s:s["hud"]["camera"]==FOCUS and placed(s,set()),22)
            proof["explicit_result"]=result["s"];png("after-explicit-confirm")
        else:
            result=sample(lambda s:s["hud"]["camera"]==FOCUS and after_ok(s,True))
            R(fields(result["s"])==fields(before),"baseline charged or changed after rejected touch")
        proof["runtime_gl"]=result["gl"];proof["final_console"]=logs()
        R(not any(stock.ERROR.search(x.get("message","")) for k in ("menu_console","final_console") for x in proof[k]),"product console reported runtime/WebGL error")
        proof["pass"]=True
      except Exception as ex:
        proof["error"]=str(ex)
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
    R(pins["mode"]=="BOUND_HOSTED_PLACEMENT" and os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and os.environ.get("GITHUB_REPOSITORY")=="penny323mo/valley-crown" and os.environ.get("GITHUB_REF")=="refs/heads/main","only bound official hosted run is allowed")
    R(stock.sha(GL_JS.read_bytes())==pins["fixtures"]["gl-observe.js"] and stock.sha((COMMON/"stock-proof.py").read_bytes())==pins["fixtures"]["stock-proof.py"],"exact reviewed helper/observer identity")
    with tempfile.TemporaryDirectory(prefix="placement-web-",dir=os.environ["RUNNER_TEMP"]) as d:
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
    A,B=(json.loads((out/(k+"-browser.json")).read_bytes()) for k in ("baseline","candidate"))
    if not errors:
        R(A["browser"]==B["browser"] and A["plot_tap"]==B["plot_tap"]==PLOT and A["worker"]==B["worker"]
          and A["arrived"]["camera"]==B["arrived"]["camera"]==FOCUS and fields(A["before_tap"])==fields(B["before_tap"]) and A["before_tap"]["hud"]["preview"]==B["before_tap"]["hud"]["preview"],
          "exact stock comparable baseline and candidate observations differ")
    result={"pass":not errors,"errors":errors,"scope":"Hosted stock Chromium/WebGL2 568x320; fresh ordinary Escort scenario; no save/campaign state injection, physical iPhone or Safari.",
            "baseline_build":pins["baseline"]["build"],"candidate_build":pins["candidate"]["build"],"images":{**A["images"],**B["images"]}}
    stock.jdump(out/"comparison.json",result);print(json.dumps(result))
    R(not errors,"stock placement failed in one or both exact arms")
if __name__=="__main__":main()
