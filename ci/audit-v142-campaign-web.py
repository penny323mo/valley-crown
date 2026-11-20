#!/usr/bin/env python3
"""Disposable hosted Chromium browser proof. Ordinary canvas touches, inspection-only QA projection."""
import base64, hashlib, functools, http.server, json, os, pathlib, shutil, socket, subprocess, sys, tempfile, threading, time
from urllib.request import Request, ProxyHandler, build_opener
from urllib.error import HTTPError

root=pathlib.Path(sys.argv[1]).resolve()
mode=sys.argv[2]
assert mode in ("baseline","candidate") and len(sys.argv) == 6
width,height=map(int,sys.argv[3].split("x"))
source=pathlib.Path(sys.argv[4]).resolve()
expression=source.read_bytes().decode()
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
peer=root/"peer"
peer_packages={f.name:hashlib.file_digest(f.open("rb"),"sha256").hexdigest() for f in peer.glob("index.*") if f.is_file()}
receipt={"peer_package_sha256":peer_packages,"mode":mode,"scope":"Same-origin Chrome tabs with controlled progression using exact shipped JS storage function; real menu taps, not an earned browser victory or physical iPhone.","expression_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),"package_sha256":{f.name:hashlib.file_digest(f.open("rb"),"sha256").hexdigest() for f in root.glob("index.*") if f.is_file()},"checks":[],"browser":"stock hosted Google Chrome, API-compatible driver; disposable profile; not iPhone","webgl":False}
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
        def tab():
            return request("GET",prefix+"/window")
        def select(handle):
            request("POST",prefix+"/window",{"handle":handle})
            check("distinct browser tab selected",tab()==handle)
        key="penny323mo.valley-crown.campaign-progress.v1"
        sentinel="english-quest.sibling-sentinel"
        url=web+"/index.html?qa=1"
        peer_url=web+"/peer/index.html?qa=1" if peer_packages else url
        first='{"completed":1,"revision":1,"schema":1}'
        next_record='{"completed":2,"revision":2,"schema":1}'
        def raw():return js("return localStorage.getItem(arguments[0]);",key)
        def controlled_write(old, new):
            response=js("const persist="+expression+";return persist(arguments[0],'write',arguments[1],arguments[2]);",key,old,new)
            check("byte-identical controlled storage expression accepted",json.loads(response)=={"ok":True,"raw":new})
        def campaign(completed):
            check("ordinary menu opens without live battlefield",not on("home")["match_exists"])
            tap("StartMatchButton");on("battle_groups");tap("CampaignMenuButton")
            s=on("campaign")
            check("campaign reports expected completion without live match",not s["match_exists"] and s["campaign_completed"]==completed and s["campaign_storage_available"] is True)
            return s
        def live():
            def matches():
                s=snapshot();return s if s and not s["visible"] and s["match_exists"] else None
            s=wait_for(matches,24)
            world=wait_for(lambda:js("if(typeof window.valleySnapshot!=='function')return null;window.valleySnapshot();return window.valleyState;"),24)
            check("live world projection confirms dimensions",world.get("hud",{}).get("viewport")==[width,height])
            receipt.setdefault("live_worlds",[]).append({"build":world["build"],"tick":world["tick"],"viewport":world["hud"]["viewport"]})
            return s
        go(peer_url);on("home")
        rc=js("return {webgl:!!document.createElement('canvas').getContext('webgl2'),width:window.innerWidth,height:window.innerHeight}")
        receipt["webgl"]=rc["webgl"];receipt["viewport"]=[rc["width"],rc["height"]]
        check("browser WebGL2 and designed viewport",rc["webgl"] and receipt["viewport"]==[width,height])
        canvas=js("let r=document.querySelector('#canvas').getBoundingClientRect();return [r.width,r.height];")
        check("exact game canvas at design dimensions",canvas==[width,height])
        check("disposable browser campaign slot empty",raw() is None)
        controlled_write(None,first)
        js("localStorage.setItem(arguments[0],'preserve')",sentinel)
        go(peer_url);campaign(1)
        a=tab()
        b=request("POST",prefix+"/window/new",{"type":"tab"})["handle"]
        check("two independent tabs exist",a!=b)
        select(b);go(url);campaign(1)
        tap("RestartCampaignButton");on("setup")
        screenshot("stale-restart-briefing.png")
        select(a);controlled_write(first,next_record)
        select(b)
        check("new shared 2/3 bytes reached stale tab while its briefing remains open",raw()==next_record and on("setup")["match_exists"] is False)
        tap("LaunchMatchButton")
        if mode=="baseline":
            state=live()
            check("baseline starts stale new match although shared 2/3 bytes are unchanged",state["match_exists"] and raw()==next_record)
            screenshot("baseline-stale-match-live.png")
        else:
            s=on("campaign")
            check("candidate remains in campaign with no match and preserves shared 2/3 bytes",not s["match_exists"] and s["campaign_completed"]==2 and raw()==next_record)
            check("chapter 3 visibly offered again",any(x["id"]=="CampaignChapterButton" and "3" in x["text"] for x in s["buttons"]))
            screenshot("candidate-refreshed-warning.png")
            receipt["warning_evidence"]="Native rendered candidate-refreshed-warning.png; QA menu snapshot does not expose prose. Inspect PNG for full visible warning."
            tap("ReplayCampaignButton");on("setup")
            check("explicit replay preview does not write progress",raw()==next_record)
            tap("LaunchMatchButton");live()
            check("explicit replay launch does not write progress",raw()==next_record)
            screenshot("candidate-explicit-replay-live.png")
            go(url);campaign(2)
            tap("RestartCampaignButton");on("setup")
            check("confirmed reset does not occur until launch",raw()==next_record)
            tap("BackButton");on("campaign")
            check("back from reset preserves progress",raw()==next_record)
            tap("RestartCampaignButton");on("setup");tap("LaunchMatchButton");live()
            reset=json.loads(raw())
            check("confirmed actual reset launch writes 0/3 revision 3",reset=={"schema":1,"revision":3,"completed":0})
            go(url);campaign(0)
            check("confirmed reset persists on normal reload",json.loads(raw())==reset)
        check("same-origin sibling sentinel was untouched",js("return localStorage.getItem(arguments[0]);",sentinel)=="preserve")
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
