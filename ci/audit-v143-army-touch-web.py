#!/usr/bin/env python3
"""Disposable hosted Chromium browser proof. Ordinary canvas touches, inspection-only QA projection."""
import base64, hashlib, functools, http.server, json, os, pathlib, shutil, socket, subprocess, sys, tempfile, threading, time
from urllib.request import Request, ProxyHandler, build_opener
from urllib.error import HTTPError

root=pathlib.Path(sys.argv[1]).resolve()
mode=sys.argv[2]
assert mode in ("baseline","candidate") and len(sys.argv) == 6
width,height=map(int,sys.argv[3].split("x"))
build=sys.argv[4]
out=pathlib.Path(sys.argv[5]).resolve()
out.mkdir(parents=True,exist_ok=True)
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
receipt={"mode":mode,"scope":"Ordinary touch menus, scout selection and same apparently open ground tap in exact stock Chrome build; no writable engine bridge and not a physical iPhone.","expected_build":build,"package_sha256":{f.name:hashlib.file_digest(f.open("rb"),"sha256").hexdigest() for f in root.glob("index.*") if f.is_file()},"checks":[],"webgl":False}
session=None
with (out/"chromedriver.log").open("wb") as logs, tempfile.TemporaryDirectory(prefix="v133-browser-") as profile:
    proc=subprocess.Popen([driver,f"--port={dport}","--allowed-ips=127.0.0.1"],stdout=logs,stderr=logs)
    try:
        def driver_ready():
            try:return request("GET","/status").get("ready")
            except OSError:return False
        wait_for(driver_ready,12)
        wanted={"browserName":"chrome","goog:loggingPrefs":{"browser":"ALL"},"goog:chromeOptions":{"binary":chrome,"args":["--headless","--disable-background-networking","--no-first-run",f"--user-data-dir={profile}","--use-gl=angle","--use-angle=swiftshader"],"mobileEmulation":{"deviceMetrics":{"width":width,"height":height,"pixelRatio":1}}}}
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
            last=None;streak=0
            def settled():
                nonlocal last,streak
                now=snapshot()
                if not now or not now["visible"]:return None
                items=now["buttons"]
                item=next((x for x in items if x["id"]==button),None)
                if item is None:return None
                x,y,w,h=item["rect"]
                tx,ty=x+w/2,y+h/2
                distinct=all(not (q["rect"][0]<=tx<q["rect"][0]+q["rect"][2] and q["rect"][1]<=ty<q["rect"][1]+q["rect"][3]) for q in items if q["id"]!=button)
                if not distinct or w<40 or h<40:return None
                mark=json.dumps((now["page"],items),sort_keys=True)
                streak=streak+1 if mark==last else 1
                last=mark
                return (now,item) if streak>=3 else None
            current,item=wait_for(settled,17)
            x,y,w,h=item["rect"]
            receipt.setdefault("ordinary_touch_route",[]).append({"page":current["page"],"button":button,"screen":[int(x+w/2),int(y+h/2)],"geometry":current["buttons"]})
            request("POST",prefix+"/actions",{"actions":[{"type":"pointer","id":"finger","parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":80,"x":int(x+w/2),"y":int(y+h/2),"origin":"viewport"},{"type":"pointerDown","button":0},{"type":"pause","duration":75},{"type":"pointerUp","button":0}]}]})
        def screenshot(name):
            (out/name).write_bytes(base64.b64decode(request("GET",prefix+"/screenshot")))
        def world():
            return js("if(typeof window.valleySnapshot!=='function')return null;window.valleySnapshot();return window.valleyState;")
        def touch(point):
            x,y=point
            request("POST",prefix+"/actions",{"actions":[{"type":"pointer","id":"field-finger","parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":60,"x":x,"y":y,"origin":"viewport"},{"type":"pointerDown","button":0},{"type":"pause","duration":70},{"type":"pointerUp","button":0}]}]})
        def matching(pred,seconds=18):
            def read():
                s=world();return s if s and s.get("hud",{}).get("viewport") and pred(s) else None
            return wait_for(read,seconds)
        url=web+"/index.html?qa=1"
        go(url);on("home")
        rc=js("let r=document.querySelector('#canvas').getBoundingClientRect();return {webgl:!!document.createElement('canvas').getContext('webgl2'), viewport:[innerWidth,innerHeight,r.width,r.height]}")
        receipt["webgl"]=rc["webgl"];receipt["viewport"]=rc["viewport"][:2]
        check("actual WebGL canvas at planned size",rc["webgl"] and rc["viewport"]==[width,height,width,height])
        tap("StartMatchButton");on("battle_groups")
        tap("BattleGroup0");on("battle_options")
        tap("ChooseBattle_standard");on("setup")
        tap("LaunchMatchButton")
        st=matching(lambda s:s["tick"]>=10)
        receipt["initial"]={"build":st["build"],"camera":st["hud"]["camera"],"tick":st["tick"]}
        zoom=22 if width>height else 30
        check("exact ordinary Classical launch and camera",st["build"]==build and st["population"]==6 and st["hud"]["camera"]=={"focus":[-25,0,24],"zoom":zoom} and st["hud"]["viewport"]==[width,height])
        scouts={(390,844):(318,427),(844,390):(499,198)}
        points={(390,844):(263,292),(844,390):(472,122)}
        touch(scouts[(width,height)])
        idle=matching(lambda s:s["selected"]==[6] and "待命" in s["hud"]["selection_detail"])
        check("actual direct touch selected only the scout",idle["selected"]==[6] )
        screenshot("selected-scout-before-tap.png")
        point=points[(width,height)]
        receipt["touch"]={"screen":point,"tick_before":idle["tick"],"status_before":idle["hud"]["selection_detail"],"camera":idle["hud"]["camera"]}
        touch(point)
        if mode=="candidate":
            moving=matching(lambda s:s["selected"]==[6] and "移動" in s["hud"]["selection_detail"],5)
            receipt["touch"]["moving_tick"]=moving["tick"]
            check("same open point starts ordinary moving state without command menu",moving["selected"]==[6] and moving["hud"]["camera"]==idle["hud"]["camera"] and not moving["touch_mode"])
            screenshot("scout-moving.png")
            finished=matching(lambda s:s["tick"]>moving["tick"] and s["selected"]==[6] and "待命" in s["hud"]["selection_detail"],14)
            check("scout naturally returns to idle after movement",finished["tick"]>moving["tick"])
        else:
            statuses=[]
            result_tick=idle["tick"]+60
            while True:
                s=matching(lambda s:s["selected"]==[6],5)
                statuses.append(s["hud"]["selection_detail"])
                if s["tick"]>=result_tick:break
                time.sleep(.15)
            receipt["touch"]["baseline_samples"]=statuses
            check("identical open point never starts movement in baseline",len(statuses)>=4 and all("待命" in x and "移動" not in x for x in statuses))
        screenshot("scout-after-tap.png")
        receipt["complete"]=True
    finally:
        (out/"browser-proof.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n")
        if session:
            try:(out/"browser-console.json").write_text(json.dumps(request("POST",prefix+"/log",{"type":"browser"}),indent=2)+"\n")
            except Exception:pass
            try:request("DELETE","/session/"+session)
            except Exception:pass
        proc.terminate()
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        server.shutdown()
print(json.dumps(receipt,ensure_ascii=False))
