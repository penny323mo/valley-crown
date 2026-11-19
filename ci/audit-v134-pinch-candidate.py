#!/usr/bin/env python3
"""Disposable hosted Chromium browser proof. Ordinary canvas touches, inspection-only QA projection."""
import base64, functools, http.server, json, os, pathlib, shutil, socket, subprocess, sys, tempfile, threading, time
from urllib.request import Request, ProxyHandler, build_opener
from urllib.error import HTTPError

root=pathlib.Path(sys.argv[1]).resolve()
mode=sys.argv[2]
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

        # Navigate by ordinary touch to a new real battle using authored practice defaults.
        tap("StartMatchButton");on("battle_groups");tap("BattleGroup0");on("battle_options")
        tap("ChooseBattle_practice");on("setup");tap("LaunchMatchButton")
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
        js("""window.qaPairSamples=[];
          for(const kind of ['touchstart','touchmove','touchend','touchcancel']){
            addEventListener(kind,e=>{
              if(window.qaPairSamples.length>=600)return;
              window.qaPairSamples.push([kind,Array.from(e.touches,t=>[t.identifier,t.clientX,t.clientY]),Array.from(e.changedTouches,t=>[t.identifier,t.clientX,t.clientY])]);
            },{capture:true,passive:true});
          }""")
        def arrived_pair(name):
            rows=js("let q=window.qaPairSamples;window.qaPairSamples=[];return q;")
            doubles=[active for kind,active,changed in rows if kind in ('touchstart','touchmove') and len(active)==2]
            check(name+" native browser events carried two live touches",len(doubles)>=2)
            first,last=doubles[0],doubles[-1]
            span=lambda z:sum((x-y)**2 for x,y in zip(z[0][1:],z[1][1:]))**0.5
            a,b=span(first),span(last)
            check(name+" browser parallel input really kept final span",abs(a-b)<=0.5 and {z[0] for z in first}=={z[0] for z in last})
            receipt.setdefault("pairs",{})[name]={"start":first,"end":last,"span":[a,b],"samples":len(doubles)}
        state=assert_geometry(390,844);mark("portrait-open",state)
        check("ordinary practice simulation starts",state["build"]=="vc-ea0e9d130c01" and state["tick"]>=0 and not state["game_over"])
        worker=visible_worker(state)
        check("portrait has visibly tappable worker",bool(worker))
        touch(worker["screen"])
        state=match(lambda s:worker["id"] in s["selected"],6);mark("portrait-selected",state)
        check("direct tap selects exact visible worker",state["selected"]==[worker["id"]])
        points=state["hud"]["ground_points"]
        check("portrait has empty ground with visible ray",bool(points))
        old=worker["screen"]
        goal=max(points,key=lambda t:(t[0]-old[0])**2+(t[1]-old[1])**2)
        touch(goal)
        def moved(s):
            target=next((x for x in s["hud"]["own_targets"] if x["id"]==worker["id"]),None)
            return target and sum((a-b)**2 for a,b in zip(target["screen"],old))>64
        state=match(moved,8);mark("portrait-moved",state)
        check("single ground tap moves selected worker without mode",state["selected"]==[worker["id"]] and not state["touch_mode"])
        focus=state["hud"]["camera"]["focus"]
        portrait_initial_zoom=state["hud"]["camera"]["zoom"]
        js("window.qaPairSamples=[]")
        move((115,370),(164,420),other=((235,370),(284,420)))
        arrived_pair("portrait")
        state=match(lambda s:s["hud"]["camera"]["focus"]!=focus,6);mark("portrait-panned",state)
        check("two concurrent touches pan and retain selection",state["selected"]==[worker["id"]])
        z=state["hud"]["camera"]["zoom"]
        receipt["portrait_zoom"]=[portrait_initial_zoom,z]
        check("portrait baseline reproduces drift or candidate retains parallel scale", abs(z-portrait_initial_zoom)<0.1)
        png("portrait-actual-battle")
        state=rotate(844,390,True);mark("landscape-open",state)
        w=visible_worker(state)
        check("landscape has visibly tappable worker",bool(w))
        touch(w["screen"])
        state=match(lambda s:w["id"] in s["selected"],6)
        check("ordinary battle touch still selects after rotate",state["selected"]==[w["id"]])
        focus=state["hud"]["camera"]["focus"]
        landscape_initial_zoom=state["hud"]["camera"]["zoom"]
        js("window.qaPairSamples=[]")
        move((275,165),(310,185),other=((495,165),(530,185)))
        arrived_pair("landscape")
        state=match(lambda s:s["hud"]["camera"]["focus"]!=focus,6);mark("landscape-panned",state)
        check("two-touch panning retains selection after rotate",state["selected"]==[w["id"]])
        z=state["hud"]["camera"]["zoom"]
        receipt["landscape_zoom"]=[landscape_initial_zoom,z]
        check("landscape baseline reproduces drift or candidate retains parallel scale",abs(z-landscape_initial_zoom)<0.1)
        png("landscape-actual-battle")
        state=rotate(390,844,False);mark("portrait-restored",state)
        check("portrait rotation round trip keeps live running battle",state["tick"]>0 and not state["game_over"])
        before=state["hud"]["camera"]["zoom"]
        # Hold both browser pointers through a moderate deliberate spread and
        # return them to the original span in one continuous gesture.
        from math import hypot
        def cdpf(cmd,params):
            return request("POST",prefix+"/goog/cdp/execute",{"cmd":cmd,"params":params})
        def fingers(event,pair=()):
            cdpf("Input.dispatchTouchEvent",{"type":event,"touchPoints":[{"x":x,"y":y,"id":i} for i,(x,y) in enumerate(pair)]})
        a=((143,350),(243,350));b=((121,372),(267,372))
        fingers("touchStart",a);fingers("touchMove",b)
        spread=match(lambda s:s["hud"]["camera"]["zoom"]<before-1,6)
        check("real deliberate spread with translated centroid zooms and pans",spread["hud"]["camera"]["focus"]!=state["hud"]["camera"]["focus"])
        fingers("touchMove",a)
        returned=match(lambda s:abs(s["hud"]["camera"]["zoom"]-before)<0.1,6)
        receipt["deliberate_zoom"]=[before,spread["hud"]["camera"]["zoom"],returned["hud"]["camera"]["zoom"]]
        fingers("touchEnd")
        check("return to original pair span restores zoom before release",abs(returned["hud"]["camera"]["zoom"]-before)<0.1)
        fingers("touchStart",a);fingers("touchMove",((164,373),(224,373)))
        squeeze=match(lambda s:s["hud"]["camera"]["zoom"]>before+1,6)
        check("real deliberate squeeze zooms out",squeeze["hud"]["camera"]["zoom"]<=46)
        fingers("touchMove",a)
        second=match(lambda s:abs(s["hud"]["camera"]["zoom"]-before)<0.1,6)
        check("returning from squeeze retains original zoom",abs(second["hud"]["camera"]["zoom"]-before)<0.1)
        fingers("touchEnd")
        check("release after deliberate pinch keeps live battle and selection",world()["selected"]==state["selected"] and not world()["game_over"])
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
