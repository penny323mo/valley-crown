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
        tap("StartMatchButton");on("battle_groups");tap("CampaignMenuButton")
        state=on("campaign")
        check("real touch opens campaign page without live battlefield",not state["match_exists"] and any(b["id"]=="CampaignChapterButton" and "1" in b["text"] for b in state["buttons"]))
        if mode=="progress":
            key="penny323mo.valley-crown.campaign-progress.v1"
            def raw():return js("return localStorage.getItem(arguments[0]);",key)
            def settle_campaign():
                on("home");tap("StartMatchButton");on("battle_groups");tap("CampaignMenuButton");return on("campaign")
            check("fresh browser did not invent progress from opening UI",raw() is None)
            known=json.dumps({"schema":1,"revision":1,"completed":1},separators=(",",":"))
            expression=(root/"production-storage-expression.js").read_text()
            # Controlled test write through the byte-identical shipped Web
            # storage expression, not a qualifying browser victory. No dwell:
            # this single callback writes, reads back, and replaces the document.
            response=js("const persist="+expression+";const result=persist(arguments[0],'write',null,arguments[1]);if(JSON.parse(result).ok)location.replace('/index.html?qa=1&immediate=1');return result;",key,known)
            check("exact synchronous Web backend wrote and read back controlled chapter 1",json.loads(response)=={"ok":True,"raw":known})
            wait_for(lambda:js("return new URLSearchParams(location.search).has('immediate')"),12)
            restored=settle_campaign()
            check("normal exact production menu after immediate reload offers only chapter 2",not restored["match_exists"] and restored.get("campaign_completed")==1 and restored.get("campaign_storage_available") is True and any(b["id"]=="CampaignChapterButton" and "2" in b["text"] for b in restored["buttons"]) and raw()==known)
            viewed=request("GET",prefix+"/screenshot")
            (root/"browser-restored-campaign.png").write_bytes(base64.b64decode(viewed))
            go(url)
            restored=settle_campaign()
            check("normal repeated reload retains completion on same profile",restored.get("campaign_completed")==1 and raw()==known)
            js("localStorage.setItem('english-quest.sibling-sentinel','preserve')")
            tap("RestartCampaignButton");on("setup");tap("BackButton");on("campaign")
            check("restart preview cancel does not write the browser",raw()==known)
            # Wrap the storage operation as an observer *only in this test
            # document*. The real button's shipped store performs the write
            # and readback. Reload on the following JS microtask, no sleep.
            js("""const key=arguments[0], write=Storage.prototype.setItem;
              Storage.prototype.setItem=function(k,v){
                write.call(this,k,v);
                if(this===window.localStorage&&k===key&&JSON.parse(v).completed===0){
                  queueMicrotask(()=>location.replace('/index.html?qa=1&reset=1'));
                }
              };""",key)
            tap("RestartCampaignButton");on("setup");tap("LaunchMatchButton")
            wait_for(lambda:js("return new URLSearchParams(location.search).has('reset')"),18)
            state=settle_campaign();reset=json.loads(raw())
            check("actual explicit reset launch persists before immediate reload",not state["match_exists"] and state.get("campaign_completed")==0 and reset=={"schema":1,"revision":2,"completed":0} and js("return localStorage.getItem('english-quest.sibling-sentinel')")=="preserve")
            blocked=request("POST",prefix+"/goog/cdp/execute",{"cmd":"Page.addScriptToEvaluateOnNewDocument","params":{"source":"Object.defineProperty(window,'localStorage',{get(){throw new Error('controlled storage denial')}});"}})
            go(url)
            state=settle_campaign()
            check("blocked browser still opens ordinary campaign session",not state["match_exists"] and state.get("campaign_storage_available") is False)
            request("POST",prefix+"/goog/cdp/execute",{"cmd":"Page.removeScriptToEvaluateOnNewDocument","params":{"identifier":blocked["identifier"]}})
            go(url);settle_campaign()
            check("denied browser run did not damage durable campaign record",json.loads(raw())==reset)
            receipt["scope"]="Exact production Web hash and ordinary touch menu. Immediate reload from separate controlled write through frozen production JS expression, and genuine user-triggered reset. No browser match victory, physical iPhone, or Safari claim."
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
