#!/usr/bin/env python3
"""Disposable hosted Chromium browser proof. Ordinary canvas touches, inspection-only QA projection."""
import base64, functools, http.server, json, os, pathlib, shutil, socket, subprocess, sys, tempfile, threading, time
from urllib.request import Request, ProxyHandler, build_opener
from urllib.error import HTTPError

root=pathlib.Path(sys.argv[1]).resolve()
mode=sys.argv[2]
expected=sys.argv[3]
assert mode in ("baseline","candidate") and expected.startswith("vc-")
chrome=shutil.which("google-chrome")
driver=shutil.which("chromedriver") or str(pathlib.Path(os.environ["CHROMEWEBDRIVER"])/"chromedriver")
assert chrome and pathlib.Path(driver).is_file() and (root/"index.html").is_file()
class Local(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_): pass
server=http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(Local,directory=str(root)))
threading.Thread(target=server.serve_forever,daemon=True).start()
web=f"http://127.0.0.1:{server.server_port}"
with socket.socket() as s:
    s.bind(("127.0.0.1",0)); dport=s.getsockname()[1]
webdriver=f"http://127.0.0.1:{dport}"
opener=build_opener(ProxyHandler({}))
def request(method,path,data=None):
    headers={"content-type":"application/json"}
    try:
        with opener.open(Request(webdriver+path,json.dumps(data).encode() if data is not None else None,headers=headers,method=method),timeout=25) as r:
            return json.load(r)["value"]
    except HTTPError as e:
        body=e.read().decode(errors="replace")
        raise RuntimeError(f"WebDriver {e.code}: {body[:1900]}") from None
def wait_for(fn,sec):
    until=time.monotonic()+sec
    while time.monotonic()<until:
        if (result:=fn()): return result
        time.sleep(.22)
    raise RuntimeError("Expected browser state did not appear")
def check(name,cond):
    if not cond:raise AssertionError(name)
    receipt["checks"].append(name)
receipt={"mode":mode,"checks":[],"browser":"stock hosted Google Chrome, API-compatible driver; disposable profile; not iPhone","webgl":False}
session=None
with (root/"chromedriver.log").open("wb") as logs, tempfile.TemporaryDirectory(prefix="v133-browser-") as profile:
    proc=subprocess.Popen([driver,f"--port={dport}","--allowed-ips=127.0.0.1"],stdout=logs,stderr=logs)
    try:
        def driver_ready():
            try:return request("GET","/status").get("ready")
            except OSError:return False
        wait_for(driver_ready,12)
        wanted={"browserName":"chrome","goog:loggingPrefs":{"browser":"ALL"},"goog:chromeOptions":{"binary":chrome,"args":["--headless","--disable-background-networking","--no-first-run",f"--user-data-dir={profile}","--use-gl=angle","--use-angle=swiftshader"],"mobileEmulation":{"deviceMetrics":{"width":390,"height":844,"pixelRatio":1}}}}
        data=request("POST","/session",{"capabilities":{"alwaysMatch":wanted}})
        session=data["sessionId"]
        receipt["browser_version"]=data["capabilities"]["browserVersion"]
        prefix="/session/"+session
        def js(code,*args):return request("POST",prefix+"/execute/sync",{"script":code,"args":list(args)})
        def go(url):request("POST",prefix+"/url",{"url":url})
        def snapshot():
            return js("if(typeof window.valleyMenuSnapshot!=='function')return null;window.valleyMenuSnapshot();return window.valleyMenuState;")
        def on(page):
            def matches():
                s=snapshot();return s if s and s["visible"] and s["page"]==page else None
            return wait_for(matches,18)
        def tap(button):
            current=wait_for(snapshot,12)
            item=next((x for x in current["buttons"] if x["id"]==button),None)
            if item is None:raise RuntimeError(f"Missing button {button}, {current}")
            x,y,w,h=item["rect"]
            if w<40 or h<40:raise RuntimeError(f"Not visible at touch size: {button} {item}")
            request("POST",prefix+"/actions",{"actions":[{"type":"pointer","id":"finger","parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":80,"x":int(x+w/2),"y":int(y+h/2),"origin":"viewport"},{"type":"pointerDown","button":0},{"type":"pause","duration":75},{"type":"pointerUp","button":0}]}]})
        go(web+"/probe.html")
        rc=js("return {webgl:!!document.createElement('canvas').getContext('webgl2'),width:window.innerWidth,height:window.innerHeight}")
        receipt["webgl"]=rc["webgl"];receipt["viewport"]=[rc["width"],rc["height"]]
        check("actual browser WebGL2",rc["webgl"])
        url=web+"/index.html?qa=1"
        go(url)
        state=on("home")
        check("exact Web export opens native game-generated menu",not state["match_exists"])

        def world():
            return js("if(typeof window.valleySnapshot!=='function')return null;window.valleySnapshot();return window.valleyState;")
        def match(fn=lambda s:True,limit=25):
            def has():
                v=world();return v if v and v.get('hud',{}).get('viewport') and fn(v) else None
            return wait_for(has,limit)
        def mark(key,state):
            receipt.setdefault("observations",{})[key]={"tick":state["tick"],"selected":state["selected"],"hud":state["hud"]}
        def png(name):
            data=request("GET",prefix+"/screenshot")
            (root/(name+".png")).write_bytes(base64.b64decode(data))
        def touch(point):
            x,y=[int(i) for i in point]
            request("POST",prefix+"/actions",{"actions":[{"type":"pointer","id":"combat-tap","parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":60,"x":x,"y":y,"origin":"viewport"},{"type":"pointerDown","button":0},{"type":"pause","duration":70},{"type":"pointerUp","button":0}]}]})
        def move(start,end,wait=0,other=None):
            fingers=[]
            for i,pair in enumerate([(start,end)]+([other] if other else [])):
                a,b=pair
                fingers.append({"type":"pointer","id":"combat-move-"+str(i),"parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":60,"x":int(a[0]),"y":int(a[1]),"origin":"viewport"},{"type":"pointerDown","button":0},{"type":"pause","duration":wait},{"type":"pointerMove","duration":350,"x":int(b[0]),"y":int(b[1]),"origin":"viewport"},{"type":"pointerUp","button":0}]})
            request("POST",prefix+"/actions",{"actions":fingers})
        def viewport():
            return js("let r=document.querySelector('#canvas').getBoundingClientRect();return [innerWidth,innerHeight,r.width,r.height];")
        def assert_geometry(w,h):
            state=match(lambda s:s["hud"]["viewport"]==[w,h])
            check(f"{w}x{h} production canvas and viewport agree",viewport()==[w,h,w,h])
            return state
        def visible_worker(s):
            return next((x for x in s["hud"]["own_targets"] if x["kind"]=="villager"),None)
        def rotate(w,h,landscape):
            request("POST",prefix+"/goog/cdp/execute",{"cmd":"Emulation.setDeviceMetricsOverride","params":{"width":w,"height":h,"deviceScaleFactor":1,"mobile":True,"screenOrientation":{"type":"landscapePrimary" if landscape else "portraitPrimary","angle":90 if landscape else 0}}})
            return assert_geometry(w,h)

        def ordinary(option,group):
            on("home");tap("StartMatchButton");on("battle_groups");tap("BattleGroup"+str(group));on("battle_options")
            tap("ChooseBattle_"+option);on("setup");tap("LaunchMatchButton")
            return assert_geometry(390,844)

        g=ordinary("escort",3)
        check("exact Web opens Escort in ordinary flow",g["build"]==expected and not g["game_over"])
        def button(q,fn):
            return next((b for b in q["hud"]["buttons"] if fn(b["text"]) and not b["disabled"] and b["rect"][2]>=40 and b["rect"][3]>=40),None)
        def button_touch(b):
            assert b is not None
            x,y,w,h=b["rect"];touch([x+w/2,y+h/2])
        tgt=next(x for x in g["hud"]["own_targets"] if x["kind"]=="villager")
        touch(tgt["screen"]);g=match(lambda q:q["selected"]==[tgt["id"]],12)
        check("selected an actual world villager",[tgt["id"]]==g["selected"])
        button_touch(button(g,lambda s:"護送拓荒隊" in s))
        g=match(lambda q:q["hud"]["camera"]["focus"]==[-7,0,6],10)
        owned=list(g["selected"]);touch([195,422])
        g=match(lambda q:button(q,lambda s:"建立前哨" in s),85)
        check("normal move brought a real party villager to the outpost",g["selected"]==owned)
        warehouse=lambda state:button(state,lambda s:s.startswith("倉庫\n"))
        for _ in range(6):
            g=match()
            if warehouse(g):break
            x,y,w,h=g["hud"]["action_scroll"]["rect"]
            move([x+w*.86,y+h*.5],[x+w*.13,y+h*.5],40)
            time.sleep(.20)
        button_touch(warehouse(g))
        g=match(lambda q:q["build_mode"]=="storehouse",10)
        funds=g["bank_milli"]["wood"]
        # Camera view analytic projection for the immutable known public
        # half-cell (-1.5,6.5) beyond the eastern boundary center x=-3.
        import math
        zoom=g["hud"]["camera"]["zoom"]
        width,height=g["hud"]["viewport"]
        n=math.sqrt(19**2+25**2+23**2); norm=math.sqrt(19**2+23**2)
        x=width/2+height/zoom*(23*5.5-19*.5)/norm
        y=height/2+height/zoom*25*(19*5.5+23*.5)/(norm*n)
        touch([round(x),round(y)])
        g=match(lambda q:q["hud"].get("preview") and q["hud"]["preview"]["held"] and q["hud"]["preview"]["placement_ok"],10)
        check("valid outside preview does not spend wood",g["bank_milli"]["wood"]==funds)
        check("ordinary visible selection HUD shows outside scoring warning",g["hud"]["selection_detail"].startswith("前哨外，不計任務"))
        png("390x844-outside-actual-battle")
        button_touch(button(g,lambda s:s=="確認建造"))
        g=match(lambda q:q["bank_milli"]["wood"]==funds-80000 and not q["build_mode"],12)
        check("real confirm deducted exactly 80 wood and kept mission stage",button(g,lambda s:"倉庫 0/1" in s) is not None)
        g=match(lambda q:q["built"].get("storehouse")==1,75)
        check("outside warehouse genuinely completed but still not counted",button(g,lambda s:"倉庫 0/1" in s) is not None)
        png("390x844-outside-complete-actual-battle")
        receipt["complete"]=True
    finally:
        (root/"browser-proof.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n")
        if session:
            try:(root/"browser-console.json").write_text(json.dumps(request("POST","/session/"+session+"/log",{"type":"browser"}),indent=2)+"\n")
            except Exception:pass
            try:request("DELETE","/session/"+session)
            except Exception:pass
        proc.terminate()
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        server.shutdown()
print(json.dumps(receipt,ensure_ascii=False))
