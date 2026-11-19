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

        g=ordinary("depot",3)
        def objective(st):
            return next((b for b in st["hud"]["buttons"] if "前線補給線" in b["text"] and b["rect"][2]>=120 and b["rect"][3]>=44 and not b["disabled"]),None)
        def touch_button(b):
            assert b
            x,y,w,h=b["rect"];touch([x+w/2,y+h/2])
        def zero(st):
            item=objective(st)
            return item and "0/120" in item["text"] and "0/80" in item["text"]
        check("new standalone mission opened exact approved build in real menu",g["build"]==expected and objective(g))
        check("real starting supplies cannot count toward forward goal",g["bank_milli"]["food"]>0 and g["bank_milli"]["wood"]>0 and zero(g))
        worker=visible_worker(g)
        assert worker is not None
        touch(worker["screen"]);g=match(lambda q:q["selected"]==[worker["id"]],12)
        check("ordinary world tap selects exactly one villager",g["selected"]==[worker["id"]])
        berry=next((o for o in g["hud"]["context_targets"] if o["kind"]=="berry"),None)
        assert berry is not None
        bank=g["bank_milli"]["food"]
        touch(berry["screen"])
        g=match(lambda q:q["bank_milli"]["food"]>=bank+10000,110)
        check("actual ordinary home gather banks food without advancing forward score",g["bank_milli"]["food"]==bank+10000 and zero(g))
        png("390x844-home-delivery-actual-battle")
        touch_button(objective(g))
        g=match(lambda q:q["hud"]["camera"]["focus"]==[-11,0,15],10)
        check("mission action frames forward zone without changing orders or score",g["selected"]==[worker["id"]] and zero(g) and objective(g)["text"].startswith("回到所選"))
        touch_button(objective(g))
        g=match(lambda q:q["hud"]["camera"]["focus"]!=[-11,0,15],10)
        check("actual return action reframes same selected worker",g["selected"]==[worker["id"]])
        g=rotate(844,390,True)
        check("landscape retains new mission HUD score and action",zero(g) and g["selected"]==[worker["id"]])
        png("844x390-live-mission-actual-battle")
        # Lay and operate the actual west-side warehouse with ordinary inputs.
        g=rotate(390,844,False)
        old_worker=worker["id"]
        worker=next((r for r in g["hud"]["own_targets"] if r["kind"]=="villager" and r["id"]!=old_worker),None)
        assert worker, "need a second real visible idle worker to avoid any home cargo handoff"
        touch(worker["screen"]);g=match(lambda q:q["selected"]==[worker["id"]],10)
        touch_button(objective(g))
        g=match(lambda q:q["hud"]["camera"]["focus"]==[-11,0,15],10)
        import math
        def project(q,bx,bz,y=0):
            cx,cy,cz=q["hud"]["camera"]["focus"]
            w,h=q["hud"]["viewport"];scale=h/q["hud"]["camera"]["zoom"]
            n=math.sqrt(19**2+25**2+23**2);norm=math.sqrt(19**2+23**2)
            dx,dz,dy=bx-cx,bz-cz,y-cy
            return [w*.5+scale*(23*dx-19*dz)/norm,h*.5+scale*(25*(19*dx+23*dz)/(norm*n)-norm*dy/n)]
        def nearest(point,opts):
            if not opts:return None
            return min(opts,key=lambda x:math.dist(point,x["screen"]))
        def visible_button(q,pattern):
            return next((b for b in q["hud"]["buttons"] if pattern(b["text"]) and b["rect"][2]>=40 and b["rect"][3]>=44 and not b["disabled"]),None)
        def saw_worker(q):
            return next((r for r in q["hud"]["own_targets"] if r["kind"]=="villager" and r["id"]==worker["id"]),None)
        def get_back(q,ret):
            t=saw_worker(q)
            return t if t and math.dist(t["screen"],ret)<26 else None
        destination=(-15.5,17.5)
        click=project(g,*destination)
        touch(click)
        g=match(lambda q:get_back(q,project(q,*destination,y=.6)),130)
        receipt["forward_start"]={"tick":g["tick"],"hud":g["hud"]["camera"],"worker":saw_worker(g)}
        check("ordinary touch move reveals west forward clearing",zero(g) and g["selected"]==[worker["id"]])
        warehouse=lambda q:visible_button(q,lambda t:t.startswith("倉庫\n"))
        for _ in range(6):
            g=match()
            if warehouse(g):break
            x,y,w,h=g["hud"]["action_scroll"]["rect"]
            move([x+w*.88,y+h*.5],[x+w*.13,y+h*.5],40)
            time.sleep(.20)
        touch_button(warehouse(g))
        g=match(lambda q:q["build_mode"]=="storehouse",12)
        before_bank=g["bank_milli"]["wood"];prev_builds=g["built"]
        chosen=None
        receipt["physical_preview_attempts"]=[]
        for bx,bz in [(-14,17),(-15,17),(-14,18),(-15,18),(-13,16),(-12,15),(-14,16)]:
            xy=project(g,bx+.5,bz+.5)
            if not (8<xy[0]<382 and 220<xy[1]<670):continue
            touch([round(k) for k in xy]);time.sleep(.60);g=match()
            trial=g["hud"].get("preview") or {}
            receipt["physical_preview_attempts"].append({"center":[bx,bz],"preview":trial,"detail":g["hud"]["selection_detail"]})
            if trial.get("held") and trial["placement_ok"] and g["hud"]["selection_detail"].startswith("補給區內"):
                chosen=(bx,bz);break
        if chosen is None:
            png("390x844-site-unavailable-actual-battle")
            raise RuntimeError("No normal eligible paid warehouse location reached")
        check("actual legal warehouse preview marks zone eligibility and spends zero",g["bank_milli"]["wood"]==before_bank and zero(g))
        touch_button(visible_button(g,lambda t:t=="確認建造"))
        g=match(lambda q:q["bank_milli"]["wood"]==before_bank-80000 and not q["build_mode"],15)
        check("real confirmed warehouse debit is exactly 80 and does not itself score",zero(g))
        def own_site(q):
            return next((o for o in q["hud"]["own_targets"] if o["kind"]=="storehouse" and not o["built"]),None)
        g=match(lambda q:own_site(q),20)
        receipt["built_site_id"]=own_site(g)["id"];receipt["site_center"]=chosen
        g=match(lambda q:q["built"]==prev_builds+1,120)
        check("matching paid warehouse completion changes action to delivery, not score",zero(g) and "交付" in objective(g)["text"])
        # Use the independently won western strategy's actual close farm, not
        # the first run's long approach around the tree from this particular worker.
        g=match(saw_worker,22)
        touch(saw_worker(g)["screen"]);g=match(lambda q:q["selected"]==[worker["id"]],10)
        farm_button=lambda q:visible_button(q,lambda t:t.startswith("農田\n"))
        for _ in range(12):
            g=match()
            if farm_button(g):break
            x,y,w,h=g["hud"]["action_scroll"]["rect"]
            if _<6:move([x+w*.13,y+h*.5],[x+w*.88,y+h*.5],40)
            else:move([x+w*.88,y+h*.5],[x+w*.13,y+h*.5],40)
            time.sleep(.18)
        touch_button(farm_button(g))
        g=match(lambda q:q["build_mode"]=="farm",12)
        prev_builds=g["built"];wood0=g["bank_milli"]["wood"]
        farm=None
        receipt["farm_preview_attempts"]=[]
        for fx,fz in [(-13.5,19.5),(-13.5,20.5),(-13.5,21.5),(-15.5,21.5),(-15.5,20.5)]:
            xy=project(g,fx,fz)
            touch([round(k) for k in xy]);time.sleep(.5);g=match()
            trial=g["hud"].get("preview") or {}
            receipt["farm_preview_attempts"].append({"site":[fx,fz],"screen":xy,"preview":trial})
            if trial.get("held") and trial["placement_ok"]:
                farm=(fx,fz);break
        assert farm,"No normal farm placement by the built forward warehouse"
        touch_button(visible_button(g,lambda t:t=="確認建造"))
        g=match(lambda q:q["bank_milli"]["wood"]==wood0-60000 and not q["build_mode"],15)
        farm_site=lambda q:next((o for o in q["hud"]["own_targets"] if o["kind"]=="farm" and not o["built"]),None)
        g=match(farm_site,20)
        receipt["farm_id"]=farm_site(g)["id"]
        g=match(lambda q:q["built"]==prev_builds+1 and saw_worker(q),120)
        check("real paid adjacent farm completes without credit",zero(g))
        touch(saw_worker(g)["screen"]);g=match(lambda q:q["selected"]==[worker["id"]],10)
        farm_tap=project(g,*farm,y=.25)
        receipt["farm_tap"]=farm_tap
        touch(farm_tap)
        g=match(lambda q:"10/80" in objective(q)["text"] and "0/120" in objective(q)["text"],130)
        check("real working farm crop delivered at same front warehouse increases mission food by 10",g["bank_milli"]["food"]>bank+10000)
        receipt["first_forward_delivery"]={"tick":g["tick"],"bank_food":g["bank_milli"]["food"],"score":objective(g)["text"],"site":receipt["built_site_id"]}
        bx,bz=chosen
        touch(project(g,bx,bz,y=.8))
        g=match(lambda q:any(z["id"]==receipt["built_site_id"] and z["built"] for z in q["hud"]["selected_own"]),10)
        check("ordinary selection identifies same now-built forward warehouse",g["selected"]==[receipt["built_site_id"]] and "10/80" in objective(g)["text"])
        png("390x844-forward-delivery-actual-battle")
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
