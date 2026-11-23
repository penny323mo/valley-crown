#!/usr/bin/env python3
"""One exact stock exported Survival camera A/B. Fresh hosted Chrome only."""
import base64
import functools
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, ProxyHandler, build_opener

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
SIZE=(568,320)
FILES=tuple("index."+p for p in (
    "apple-touch-icon.png","audio.position.worklet.js","audio.worklet.js","html","icon.png","js","pck","png","wasm"))
ROLES=("baseline","candidate")
ERROR=re.compile(
    r"shader error|shader compilation (?:failed|error)|failed to (?:compile|link)|(?:compile|link)(?:ing)? [^\n]{0,30}shader.*(?:failed|error)|"
    r"gl_invalid_(?:enum|value|operation|framebuffer_operation)|context lost|wasm.*(?:trap|unreachable)|"
    r"runtimeerror|syntaxerror|parse error",
    re.I)
def require(flag,label):
    if not flag:raise RuntimeError(label)
def sha(body):return hashlib.sha256(body).hexdigest()
def jdump(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n")
def loader(name,script):
    spec=importlib.util.spec_from_file_location(name,script)
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
def digest_fields(row):
    return all(isinstance(row[k],str) and re.fullmatch("[0-9a-f]{64}",row[k]) for k in ("metadata_sha256","zip_sha256","shader_source_sha")) and all(
        re.fullmatch("[0-9a-f]{40}",row[k]) for k in ("formal_commit","source_commit","game_tree")) and all(
        type(row[k]) is int and row[k]>0 for k in ("run_id","artifact_id"))
def unpack(raw,row,folder,archive):
    entries=archive.verified_members(raw,row)
    meta=json.loads(entries["candidate-metadata.json"])
    require(all(meta[k]==row[k] for k in ("source_commit","game_tree","build")),"archive exact product source provenance")
    require(meta["export_run"].endswith("/"+str(row["run_id"])),"archive exact formal run")
    hashes=meta["export_files_sha256"]
    require(set(hashes)==set(FILES),"stock Web release inventory")
    folder.mkdir()
    for name in FILES:
        a,b=(entries[f"artifacts/{c}/{name}"] for c in ("clean-a","clean-b"))
        require(a==b and sha(a)==hashes[name],"stock clean exports match: "+name)
        (folder/name).write_bytes(a)
    return hashes
def local_wrapper(folder,role,row):
    source=(folder/"index.html").read_text()
    m=re.search(r"const GODOT_CONFIG = (\{[^\n]*\});",source)
    require(m,"stock launcher config not found")
    config=json.loads(m.group(1))
    require(config.get("executable")=="index" and config.get("canvasResizePolicy")==2 and "const GODOT_THREADS_ENABLED = false;" in source,"stock launcher runtime config")
    args=json.dumps(["--script","/edge-audit.gd","--",role,row["build"]])
    wrap="""<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<meta charset="utf-8"><link rel="icon" href="index.icon.png">
<title>Stock exact Web edge witness</title>
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}
canvas{display:block;width:100vw;height:100vh}</style>
</head><body><canvas id="canvas"></canvas><script src="index.js"></script><script>
(async()=>{
 try {
   const engine=new Engine(CONFIG);
   const response=await fetch("edge-audit.gd",{cache:"no-store"});
   if(!response.ok)throw Error("audit fetch "+response.status);
   await engine.preloadFile(await response.arrayBuffer(),"/edge-audit.gd");
   await engine.startGame({args:ARGS});
 } catch(e){window.vcEdgeFailure=String(e);console.error(e);}
})();
</script></body></html>"""
    (folder/"audit.html").write_text(wrap.replace("CONFIG",m.group(1),1).replace("ARGS",args,1))
    shutil.copyfile(HERE/"edge-audit.gd",folder/"edge-audit.gd")
def prepare(pins,stage,out):
    archive=loader("archive",ROOT/"scripts/web_release_archive.py")
    require(all(digest_fields(pins[r]) for r in ROLES),"unbound exact product artifact pins")
    api=archive.GitHub("penny323mo/valley-crown")
    report={}
    for role in ROLES:
        row=pins[role]
        run=api.request(f"/actions/runs/{row['run_id']}")
        require(run["status"]=="completed" and run["conclusion"]=="success" and run["head_sha"]==row["formal_commit"] and run["head_branch"]=="main","exact successful formal head")
        inventory=api.request(f"/actions/runs/{row['run_id']}/artifacts")
        found=[a for a in inventory['artifacts'] if a["id"]==row["artifact_id"]]
        require(len(found)==1,"exact formal artifact exists uniquely")
        info=found[0]
        require(info["workflow_run"]["id"]==row["run_id"] and not info["expired"] and info["digest"]=="sha256:"+row["zip_sha256"],"artifact exact nonexpired formal run and digest")
        data=api.request(f"/actions/artifacts/{row['artifact_id']}/zip",binary=True)
        folder=stage/role
        before=unpack(data,row,folder,archive)
        local_wrapper(folder,role,row)
        require(before=={f:sha((folder/f).read_bytes()) for f in FILES},"original exports unchanged by external audit setup")
        report[role]={"input":row,"stock_export_sha256":before}
    jdump(out/"verified-inputs.json",report)

def until(fn,seconds):
    stop=time.monotonic()+seconds
    while time.monotonic()<stop:
        result=fn()
        if result is not None and result is not False:return result
        time.sleep(.2)
    raise TimeoutError("expected browser state did not appear")
class Local(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*_):pass
    def end_headers(self):
        self.send_header("Cache-Control","no-store")
        super().end_headers()
def browser(root,out,row,role,driver,chrome,web):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1",0));port=sock.getsockname()[1]
    opener=build_opener(ProxyHandler({}))
    address=f"http://127.0.0.1:{port}"
    prefix=""
    def call(method,path,data=None):
        try:
            request=Request(address+path,json.dumps(data).encode() if data is not None else None,{"content-type":"application/json"},method=method)
            with opener.open(request,timeout=30) as res:return json.load(res)["value"]
        except HTTPError as e:
            raise RuntimeError(f"ChromeDriver {e.code}: {e.read().decode(errors='replace')[:1600]}") from None
    def js(src,*args):return call("POST",prefix+"/execute/sync",{"script":src,"args":args})
    def cdp(cmd,params=None):return call("POST",prefix+"/goog/cdp/execute",{"cmd":cmd,"params":params or {}})
    def navigate(file):return call("POST",prefix+"/url",{"url":f"{web}/{role}/{file}?qa=1"})
    def logs():return call("POST",prefix+"/log",{"type":"browser"})
    receipt={"role":role,"scope":"Stock exact engine and PCK, true Chrome WebGL2. External auditable camera-only fixture, no physical iPhone."}
    with (out/f"{role}-chromedriver.log").open("wb") as logfile:
      owned=subprocess.Popen([driver,f"--port={port}","--allowed-ips=127.0.0.1"],stdout=logfile,stderr=logfile)
      try:
        def ready():
            if owned.poll() is not None:raise RuntimeError("ChromeDriver exited before navigation")
            try:return call("GET","/status").get("ready")
            except OSError:return False
        until(ready,16)
        profile=root/f"{role}-fresh-chrome";profile.mkdir()
        options={"binary":chrome,"args":[
            "--headless","--disable-background-networking","--no-first-run",f"--user-data-dir={profile}",
            "--use-gl=angle","--use-angle=swiftshader","--force-device-scale-factor=1",
        ],"mobileEmulation":{"deviceMetrics":{"width":SIZE[0],"height":SIZE[1],"pixelRatio":1,"mobile":True,"touch":True}}}
        session=call("POST","/session",{"capabilities":{"alwaysMatch":{"browserName":"chrome",
            "goog:chromeOptions":options,"goog:loggingPrefs":{"browser":"ALL"},"pageLoadStrategy":"eager"}}})
        prefix="/session/"+session["sessionId"]
        receipt["browser"]=session["capabilities"]["browserVersion"]
        cli=cdp("Browser.getBrowserCommandLine")["arguments"]
        forbidden={"--no-sandbox","--disable-setuid-sandbox","--disable-gpu-sandbox","--enable-unsafe-swiftshader","--single-process"}
        require(not forbidden.intersection(s.partition("=")[0] for s in cli),"browser sandbox/GL safety was weakened")
        receipt["sandbox_preserved"]=True
        cdp("Network.enable")
        cdp("Network.setBlockedURLs",{"urls":["https://*"]})
        cdp("Page.addScriptToEvaluateOnNewDocument",{"source":(HERE/"gl-observe.js").read_text()})
        navigate("index.html")
        def stock_menu():
            observed=js("""if(typeof window.valleyMenuSnapshot!=='function')return null;
                    window.valleyMenuSnapshot();return {menu:window.valleyMenuState,gl:window.vcGL};""")
            if observed and observed["menu"] and observed["menu"]["visible"] and observed["menu"]["page"]=="home":
                return observed
        landed=until(stock_menu,75)
        require(not landed["menu"]["match_exists"] and landed["gl"]["canvas"]["version"].startswith("WebGL 2.0")
                and not landed["gl"]["errorCount"] and not landed["gl"]["contextLost"],"untouched stock launch/WebGL2 menu")
        receipt["stock_menu"]=True
        receipt["menu_console"]=logs()
        navigate("audit.html")
        def witness():
            result=js("""return {w:window.vcEdgeWitness||null,err:window.vcEdgeFailure||null,
                   css:[window.innerWidth,window.innerHeight,window.devicePixelRatio],
                   canvas:[document.getElementById('canvas').width,document.getElementById('canvas').height],
                   rect:(()=>{const r=document.getElementById('canvas').getBoundingClientRect();return [r.x,r.y,r.width,r.height];})(),
                   gl:window.vcGL};""")
            if result["err"]:raise RuntimeError(result["err"])
            if result["w"] is not None:return result
        observed=until(witness,95)
        receipt["runtime"]=observed
        require(observed["css"]==[568,320,1] and observed["canvas"]==list(SIZE) and observed["rect"]==[0,0,568,320],"pixel-exact 568x320 game canvas")
        g=observed["gl"];w=observed["w"]
        require(w["role"]==role and w["build"]==row["build"] and w["engine"]["hash"]=="7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3"
                and w["renderer"]=="gl_compatibility" and w["shader_source_sha"]==row["shader_source_sha"] and w["failed"]==0 and len(w["checks"])>=5 and w["frame_post_draws"]>=4,"exact Godot Compatibility scene")
        require(g["canvas"]["version"].startswith("WebGL 2.0") and g["canvas"]["glsl"].startswith("WebGL GLSL ES 3.00") and
                not g["errorCount"] and not g["contextLost"] and min(g["maskCompiled"],g["maskLinked"],g["maskDrawn"])>0,
                "real game canvas mask shader must compile, link and draw on WebGL2")
        if role=="candidate":
            require(min(g["seamCompiled"],g["seamLinked"],g["seamDrawn"])>0,"candidate seam shader really compiled, linked, and was used by a native WebGL draw")
        else:
            require(max(g["seamCompiled"],g["seamLinked"],g["seamDrawn"])==0,"baseline unexpected candidate seam shader")
        element=call("POST",prefix+"/element",{"using":"css selector","value":"#canvas"})
        eid=element["element-6066-11e4-a52e-4f735466cecf"]
        image=base64.b64decode(call("GET",prefix+"/element/"+eid+"/screenshot"),validate=True)
        require(image.startswith(b"\x89PNG\r\n\x1a\n"),"ChromeDriver did not emit original canvas PNG")
        (out/f"{role}.png").write_bytes(image)
        receipt["unmodified_canvas_png_sha256"]=sha(image)
        receipt["audit_console"]=logs()
        require(not any(ERROR.search(x.get("message","")) for k in ("menu_console","audit_console") for x in receipt[k]),
                "browser console reported a shader/GL/runtime error")
        final=js("return window.vcGL;")
        require(not final["errorCount"] and not final["contextLost"],"GL failure during original canvas screenshot")
        receipt["pass"]=True
      except Exception as e:
        receipt["error"]=str(e)
        if prefix:
            try:receipt["failure_console"]=logs()
            except Exception:pass
        raise
      finally:
        jdump(out/f"{role}-browser.json",receipt)
        if prefix:
            try:call("DELETE",prefix)
            except Exception:pass
        if owned.poll() is None:
            owned.terminate()
            try:owned.wait(timeout=5)
            except subprocess.TimeoutExpired:owned.kill();owned.wait()

def pixels(a,b,old,new,verify):
    require(all(old[k]==new[k] for k in ("camera","zoom","size","map_half","authority_sha","input_grid","hud",
                "visibility_sha","projection","top","bottom","minimap")),"camera/authority/HUD/picks/visibility A/B mismatch")
    require(old["camera"]==[-25,0,11] and old["zoom"]==22 and old["size"]==list(SIZE),"original native witness dimensions/camera")
    ar,ast=verify.png(a,list(SIZE));br,bst=verify.png(b,list(SIZE))
    v=old["projection"];half=old["map_half"];limits=("top","bottom","minimap")
    c={k:0 for k in ("inside","inside_changed_over2","outside","old_bright","new_bright","seam","old_bright_seam","new_bright_seam","inner_flank","inner_changed_over2")}
    for y,(x0,x1) in enumerate(zip(ar,br,strict=True)):
      for x in range(SIZE[0]):
        if any(verify.rect_has(old[key],x+.5,y+.5) for key in limits):continue
        m=max(abs(v[0][k]+x*v[1][k]+y*v[2][k]) for k in (0,2))
        ca=x0[x*ast:x*ast+3];cb=x1[x*bst:x*bst+3]
        delta=max(abs(i-j) for i,j in zip(ca,cb))
        ba,bb=verify.bright_grass(ca),verify.bright_grass(cb)
        if m<=half-.12:
            c["inside"]+=1;c["inside_changed_over2"]+=delta>2
        if m>half+.12:
            c["outside"]+=1;c["old_bright"]+=ba;c["new_bright"]+=bb
        if abs(m-half)<=.12:
            c["seam"]+=1;c["old_bright_seam"]+=ba;c["new_bright_seam"]+=bb
            if m<=half-.012:
                c["inner_flank"]+=1;c["inner_changed_over2"]+=delta>2
    return c
def satisfy(c):
    return (c["inside"]>=1000 and c["outside"]>=1000 and c["old_bright"]>=500 and
        c["inside_changed_over2"]<=c["inside"]*.001 and c["new_bright"]<=c["old_bright"]*.05 and
        c["seam"]>=300 and c["old_bright_seam"]>=100 and c["new_bright_seam"]==0 and
        c["inner_flank"]>=100 and c["inner_changed_over2"]==0)
def main():
    input_path=Path(sys.argv[1]).resolve()
    out=Path(sys.argv[2]).resolve();out.mkdir()
    pins=json.loads(input_path.read_text())
    require(pins["mode"]=="HOSTED_EXACT_ONLY","candidate formal archive pins pending")
    require(os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
            os.environ.get("GITHUB_REPOSITORY")=="penny323mo/valley-crown" and os.environ.get("GITHUB_REF")=="refs/heads/main",
            "fresh official hosted workflow only")
    for name in ("edge-audit.gd","gl-observe.js"):
        require(sha((HERE/name).read_bytes())==pins["fixtures"][name],"exact frozen fixture identity: "+name)
    vis=ROOT/"ci/map-edge-veil-seam/verify-map-edge.py"
    require(sha(vis.read_bytes())==pins["fixtures"]["verify-map-edge.py"],"exact existing native PNG primitive verifier")
    verify=loader("verify_map_edge",vis)
    with tempfile.TemporaryDirectory(prefix="map-edge-web-",dir=os.environ["RUNNER_TEMP"]) as d:
      temp=Path(d);stage=temp/"serve";stage.mkdir()
      prepare(pins,stage,out)
      os.environ.pop("GH_TOKEN",None)
      chrome=shutil.which("google-chrome")
      driver=shutil.which("chromedriver") or str(Path(os.environ.get("CHROMEWEBDRIVER","/nonexistent"))/"chromedriver")
      require(chrome and Path(driver).is_file(),"stock Chrome/ChromeDriver unavailable")
      with http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(Local,directory=str(stage))) as server:
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            url=f"http://127.0.0.1:{server.server_port}"
            for role in ROLES:browser(temp,out,pins[role],role,driver,chrome,url)
        finally:server.shutdown()
    a,b=(json.loads((out/f"{r}-browser.json").read_text()) for r in ROLES)
    c=pixels(out/"baseline.png",out/"candidate.png",a["runtime"]["w"],b["runtime"]["w"],verify)
    result={"pass":satisfy(c),"scope":"Exact game Web exports, hosted Chrome WebGL2, stationary one-camera A/B and original canvas PNG; no Safari, broader Web performance or physical iPhone acceptance.",
        "pixels":c,"images":{q["role"]:q["unmodified_canvas_png_sha256"] for q in (a,b)}}
    jdump(out/"comparison.json",result);print(json.dumps(result))
    require(result["pass"] and len(set(result["images"].values()))==2,"measured Web west edge proof failed")
if __name__=="__main__":main()
