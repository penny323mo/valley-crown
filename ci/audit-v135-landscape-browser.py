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

        tap("StartMatchButton");on("battle_groups");tap("CampaignMenuButton");on("campaign")
        (root/"campaign-menu-actual-battle.png").write_bytes(base64.b64decode(request("GET",prefix+"/screenshot")))
        tap("CampaignChapterButton");on("setup")
        check("fresh campaign briefing has real launch without starting match",not on("setup")["match_exists"])
        tap("BackButton");on("campaign");tap("CampaignBackButton");on("battle_groups")

        # Navigate by ordinary touch to a new real battle using authored practice defaults.
        tap("BattleGroup0");on("battle_options")
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
        receipt["build"]=expected
        measurement={}
        receipt["measurements"]=measurement
        def button(s,label,min_width=40,permit_disabled=False):
            label_ok=(lambda t:t==label) if isinstance(label,str) else label
            candidates=[b for b in s["hud"]["buttons"] if label_ok(b["text"]) and b["rect"][2]>=min_width and b["rect"][3]>=40 and (permit_disabled or not b["disabled"])]
            return min(candidates,key=lambda b:b["rect"][1]) if candidates else None
        def hit(b):
            if b is None:raise RuntimeError("ordinary target not visible")
            x,y,w,h=b["rect"];touch([x+w/2,y+h/2])
        def wait_button(label):
            return match(lambda s:button(s,label) is not None,6)
        def log_case(key,value):
            measurement.setdefault(key,{}).update(value)
        state=assert_geometry(390,844)
        check("exact expected Web build is running",state["build"]==expected and not state["game_over"])
        # Authored opening toast lasts nine seconds. Let that presentation
        # expire before comparing the persistent guided HUD across sizes.
        state=match(lambda s:s["tick"]>=190,23)
        trained=state["trained"]
        worker=visible_worker(state)
        check("ordinary opening worker visibly selectable",bool(worker))
        workerid=worker["id"]
        geometry=[]
        for width,height in [(390,844),(844,390),(640,360),(390,844)]:
            key=f"{width}x{height}"
            repeat=any(x[0]==key for x in geometry)
            tag=key+("-return" if repeat else "")
            if geometry:state=rotate(width,height,width>height)
            rc=next((w for w in state["hud"]["own_targets"] if w["id"]==workerid),None)
            check(tag+" same worker remains visible",bool(rc))
            if state["selected"]!=[workerid]:touch(rc["screen"])
            state=match(lambda s:s["selected"]==[workerid] and button(s,"跳過") is not None,18)
            check(tag+" viewport ownership and worker selection retained",state["hud"]["viewport"]==[width,height] and state["selected"]==[workerid])
            guide=button(state,"詳情")
            house=button(state,lambda t:t.startswith("民居") and "木 50" in t)
            strip=state["hud"]["action_scroll"]["rect"]
            check(tag+" guidance details and priced House are visible touch targets",guide is not None and house is not None)
            def inside(rect,outer):
                x,y,w,h=rect; ox,oy,ow,oh=outer
                return x>=ox-0.5 and y>=oy-0.5 and x+w<=ox+ow+0.5 and y+h<=oy+oh+0.5
            check(tag+" House remains inside visible action strip",house["in_action_scroll"] and inside(house["rect"],strip) and house["rect"][2]>=80 and house["rect"][3]>=44)
            log_case(tag,{"worker_id":workerid,"guidance_details":guide["rect"],"house":house["rect"],"house_clone":house["text"],"action_scroll":strip,"world_screen_probes":state["hud"]["ground_points"],"camera":state["hud"]["camera"]})
            geometry.append((key,strip))
            png(tag+"-worker-actual-battle")
            if width>height:
                hit(guide)
                state=wait_button("關閉")
                png(tag+"-details-actual-battle")
                hit(button(state,"關閉"))
                state=wait_button(lambda t:t.startswith("民居") and "木 50" in t)
                select_before=state["selected"]
                check(tag+" ordinary guidance details open and close without dropping worker",select_before==[workerid])
                hit(button(state,"指定"));state=match(lambda s:s["touch_mode"],7)
                cancel=button(state,"取消")
                check(tag+" compact command exposes real dedicated Cancel",cancel is not None)
                hit(cancel)
                state=match(lambda s:not s["touch_mode"],7)
                check(tag+" explicit command-mode Cancel preserves worker",state["selected"]==select_before)
                log_case(tag,{"general_command_cancel":True})
                house=button(state,lambda t:t.startswith("民居") and "木 50" in t)
                wood=state["bank_milli"]["wood"]
                hit(house);state=match(lambda s:s["build_mode"]=="house",6)
                cancel=button(state,"取消建造")
                check(tag+" construction mode exposes Cancel at touch size",cancel is not None)
                hit(cancel);state=match(lambda s:not s["build_mode"],6)
                check(tag+" construction Cancel preserves worker and pays nothing",state["selected"]==select_before and state["bank_milli"]["wood"]==wood)
                hit(button(state,lambda t:t.startswith("民居") and "木 50" in t));state=match(lambda s:s["build_mode"]=="house",6)
                attempts=[];found=None
                # Stable order: documented empty-world probes then central
                # viewport lane samples; normal rendered game validates each.
                points=state["hud"]["ground_points"]+[[x,y] for y in range(120,height-120,13) for x in range(width//2-115,width//2+116,20)]
                for x,y in points[:63]:
                    prior_state=world()
                    if any(b["rect"][0]<=x<=b["rect"][0]+b["rect"][2] and b["rect"][1]<=y<=b["rect"][1]+b["rect"][3] for b in prior_state["hud"]["buttons"]):continue
                    prior=prior_state["tick"]
                    touch([x,y])
                    state=match(lambda s:s["tick"]>prior,5)
                    if state["build_mode"]!="house":
                        raise RuntimeError(tag+" battlefield tap unexpectedly left construction mode")
                    b=button(state,"確認建造")
                    p=state["hud"]["preview"]
                    attempts.append([x,y,bool(p and p["placement_ok"]),bool(b)])
                    if b and p and p["placement_ok"] and p["held"]:
                        found=b;break
                log_case(tag,{"placement_attempts":attempts})
                check(tag+" real empty-plot touch opens legal placement preview",found is not None)
                png(tag+"-placement-actual-battle")
                before=world()["bank_milli"]["wood"];hit(found)
                state=match(lambda s:s["bank_milli"]["wood"]<=before-50000,8)
                check(tag+" normal HUD confirm debits exactly 50 wood once",before-state["bank_milli"]["wood"]==50000)
                log_case(tag,{"paid_house_wood":[before,state["bank_milli"]["wood"]]})
                png(tag+"-paid-actual-battle")
                if width==640:
                    # Published navigation already provides explicit castle
                    # selection, so no new QA bridge is needed for production.
                    menu=button(state,lambda t:t in ("選單","閒置","受襲"))
                    hit(menu);state=wait_button("主堡")
                    hit(button(state,"主堡"))
                    state=wait_button(lambda t:t.startswith("訓練村民"))
                    train=button(state,lambda t:t.startswith("訓練村民"))
                    prior_food=state["bank_milli"]["food"]
                    hit(train)
                    state=match(lambda s:s["bank_milli"]["food"]<=prior_food-50000,8)
                    check(tag+" landscape Town Center queue charges 50 food exactly",prior_food-state["bank_milli"]["food"]==50000)
                    log_case(tag,{"landscape_training_food":[prior_food,state["bank_milli"]["food"]]})
                    png(tag+"-production-actual-battle")
        state=world()
        check("landscape round trip leaves game and selection active",not state["game_over"] and not state["paused"] and state["selected"]==[workerid])
        js("""window.v135TouchPairs=[];
          for(const kind of ['touchstart','touchmove'])addEventListener(kind,e=>{
            if(e.touches.length===2&&window.v135TouchPairs.length<300)window.v135TouchPairs.push(Array.from(e.touches,t=>[t.identifier,t.clientX,t.clientY]));
          },{capture:true,passive:true});""")
        focus=state["hud"]["camera"]["focus"];z=state["hud"]["camera"]["zoom"];prior=state["tick"]
        move((115,370),(164,420),other=((235,370),(284,420)))
        state=match(lambda s:s["tick"]>prior and s["hud"]["camera"]["focus"]!=focus,7)
        pairs=js("return window.v135TouchPairs")
        check("browser receives one pair with ordered movement",len(pairs)>=2 and {a[0] for a in pairs[0]}=={a[0] for a in pairs[-1]})
        import math
        spans=[math.dist(rows[0][1:],rows[1][1:]) for rows in (pairs[0],pairs[-1])]
        check("equal-span stock browser pan keeps scale and worker",abs(spans[0]-spans[1])<=0.5 and abs(state["hud"]["camera"]["zoom"]-z)<0.1 and state["selected"]==[workerid])
        log_case("390x844-return",{"pair_span":spans,"zoom_before_after":[z,state["hud"]["camera"]["zoom"]]})
        state=match(lambda s:s["trained"]>trained,35)
        check("the paid landscape queue actually produced one villager",state["trained"]==trained+1)
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
