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

        g=ordinary("breach",3)
        check("exact build active in authored campaign",g["build"]==expected and len(g["selected"])>=4 and not g["game_over"])
        before_return=None
        receipt["camera_tests"]={}
        for w,h in [(390,844),(844,390),(320,568)]:
            if w!=390:g=rotate(w,h,w>h)
            states=receipt["camera_tests"][f"{w}x{h}"]={}
            def action(q):
                return next((b for b in q["hud"]["buttons"] if "攻城突破" in b["text"] and not b["disabled"]),None)
            def hit_card(q):
                b=action(q)
                assert b and b["rect"][2]>150 and b["rect"][3]>=44
                x,y,rw,rh=b["rect"];touch([x+rw/2,y+rh/2])
            original=g["selected"];money=g["bank_milli"];zoom=g["hud"]["camera"]["zoom"]
            label=action(g)["text"]
            if mode=="candidate":
                check(f"{w}x{h} shows location as the first action",label.startswith("定位目標"))
            click_tick=g["tick"];hit_card(g)
            g=match(lambda q:q["hud"]["camera"]["focus"]==[0,0,-13] and q["tick"]>click_tick,10)
            check(f"{w}x{h} ordinary objective touch focuses the known front",g["selected"]==original and g["hud"]["camera"]["zoom"]==zoom)
            label=action(g)["text"]
            if mode=="candidate":
                check(f"{w}x{h} visibly offers return to current selection at objective",label.startswith("回到所選"))
            states["objective"]={"focus":g["hud"]["camera"]["focus"],"label":label,"zoom":zoom}
            png(f"{w}x{h}-objective-actual-battle")
            click_tick=g["tick"];hit_card(g)
            if mode=="candidate":
                g=match(lambda q:q["hud"]["camera"]["focus"]!=[0,0,-13] and q["tick"]>click_tick,8)
                check(f"{w}x{h} actual return uses selected troop position, not objective",g["hud"]["camera"]["focus"][2]>=0)
            else:
                g=match(lambda q:q["tick"]>click_tick+2,10)
                check(f"{w}x{h} old button cannot return and stays at objective",g["hud"]["camera"]["focus"]==[0,0,-13])
            check(f"{w}x{h} camera action leaves selection, zoom, economy and command state unchanged",g["selected"]==original and g["hud"]["camera"]["zoom"]==zoom and g["bank_milli"]==money and not g["touch_mode"] and not g["build_mode"] and g["own_pending_commands"]==0)
            states["second"]={"focus":g["hud"]["camera"]["focus"],"label":action(g)["text"],"selected":g["selected"]}
            png(f"{w}x{h}-second-actual-battle")
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
