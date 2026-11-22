#!/usr/bin/env python3
"""Read-only Valley Crown v143 public-build QA; discard all Chromium state."""
import argparse
import contextlib
from concurrent.futures import ThreadPoolExecutor
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
from urllib.parse import urlsplit
from urllib.request import build_opener, ProxyHandler, Request, urlopen

ORIGIN = "https://penny323mo.github.io/valley-crown-play/"
BUILD = "vc-145cea227d83"
SOURCE = "aaaa8a372fbbf0e093db65b94855389307b9f541"
PACKAGE = ORIGIN + f"builds/{BUILD}/"
ENTRY = PACKAGE + "index.html?qa=1"
HASHES = {
    "index.html": "3a8be0771551ad77782433d125a149894bc8d8a28cc6bb31b393f9aa19882fb7",
    "index.js": "e3f56ee40e6f84371053db06692cfac15e2c8659547b11c6b2dfa1996dabd981",
    "index.pck": "abfbd9a9c60ad9b0a177fb12c3e65062b493bf8ea654c9d8a67b4e619a327d02",
    "index.wasm": "26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6",
}
POINTS = {
    (390, 844): {"scout": (318, 427), "goal": (263, 292), "pair": ((100, 340), (195, 340))},
    (844, 390): {"scout": (499, 198), "goal": (472, 122), "pair": ((300, 149), (395, 149))},
}
MENU = [
    ("home", "StartMatchButton"),
    ("battle_groups", "BattleGroup0"),
    ("battle_options", "ChooseBattle_standard"),
    ("setup", "LaunchMatchButton"),
]
LISTEN = """() => {
  window.__vcGestureAudit = {phase: '', events: [], samples: []};
  const a = window.__vcGestureAudit;
  const points = ts => Array.from(ts, x => [x.identifier, x.clientX, x.clientY]);
  for (const type of ['touchstart', 'touchmove', 'touchend', 'touchcancel']) {
    window.addEventListener(type, e => {
      if (a.phase && a.events.length < 2000)
        a.events.push({phase:a.phase,type, trusted:e.isTrusted,
          target:e.target.id, timeMs:performance.now(),
          active:points(e.touches),changed:points(e.changedTouches)});
    }, {capture:true,passive:true});
  }
  a.timer = window.setInterval(() => {
    if (!a.phase || a.samples.length >= 2000 || typeof window.valleySnapshot !== 'function') return;
    window.valleySnapshot();
    const s = window.valleyState;
    if (s && s.hud) a.samples.push({phase:a.phase,tick:s.tick,selected:s.selected,
      commands:s.own_pending_commands, detail:s.hud.selection_detail, mode:s.touch_mode,
      camera:s.hud.camera, paused:s.paused, gameOver:s.game_over});
  }, 65);
}"""
MENU_SNAPSHOT = """() => {
  if (typeof window.valleyMenuSnapshot !== 'function') return null;
  window.valleyMenuSnapshot(); return window.valleyMenuState;
}"""
WORLD_SNAPSHOT = """() => {
  if (typeof window.valleySnapshot !== 'function') return null;
  window.valleySnapshot(); return window.valleyState;
}"""


class ProbeError(RuntimeError):
    pass


def inside(p, bounds, inset=0):
    x, y = p
    l, t, r, b = bounds
    return l + inset <= x < r - inset and t + inset <= y < b - inset


def plan_box(s, size):
    """Choose a one-finger rectangle around >=2 projected own units; no game mutations."""
    width, height = size
    hud = s["hud"]
    workers = [(r["id"], r["screen"]) for r in hud["own_targets"] if r["kind"] == "villager"]
    blocks = [tuple((x, y, x+w, y+h)) for x, y, w, h in
              [item["rect"] for item in hud["buttons"]] + [hud["action_scroll"]["rect"]]
              if w > 0 and h > 0]
    world = (12, max(60, height * .12), width - 12, min(height - 65, height * .87))
    worker_points = [p for _, p in workers]
    candidates = []
    for (_, a), (_, b) in itertools.combinations(workers, 2):
        for pad in (16, 23, 32):
            l = math.floor(min(a[0], b[0]) - pad)
            t = math.floor(min(a[1], b[1]) - pad)
            r = math.ceil(max(a[0], b[0]) + pad)
            btm = math.ceil(max(a[1], b[1]) + pad)
            bounds = l, t, r, btm
            ids = sorted(i for i, p in workers if inside(p, bounds, inset=5))
            if len(ids) < 2:
                continue
            for start, end in [((l, t), (r, btm)), ((l, btm), (r, t)),
                               ((r, t), (l, btm)), ((r, btm), (l, t))]:
                if not all(inside(p, world) and not any(inside(p, z, inset=-4) for z in blocks)
                           and all(math.dist(p, q) > 11 for q in worker_points)
                           for p in (start, end)):
                    continue
                candidates.append(((r-l)*(btm-t), -len(ids), start, end, bounds, ids))
    if not candidates:
        return None
    _, _, start, end, bounds, ids = min(candidates)
    outside = sorted(i for i, p in workers if not inside(p, bounds, inset=-5))
    return dict(start=start, end=end, bounds=bounds, in_box_worker_ids=ids,
                out_of_box_worker_ids=outside, projected_workers=workers)


def path_steps(start, end, jumps):
    return [tuple(round(a+(b-a)*i/jumps) for a, b in zip(start, end))
            for i in range(1, jumps+1)]


def camera_distance(a, b):
    return math.dist(a["focus"], b["focus"])


def browser_bin(cli):
    return cli or os.environ.get("CHROME_BIN") or shutil.which("google-chrome") or shutil.which("chromium")


def move(point, duration=0):
    return {"type":"pointerMove","x":point[0],"y":point[1],"origin":"viewport","duration":duration}


def press():
    return {"type":"pointerDown","button":0}


def release():
    return {"type":"pointerUp","button":0}


def actions_transaction(ticks):
    """One W3C request owns the entire balanced sequence for every pointer."""
    ids=sorted({i for t in ticks if isinstance(t,dict) for i in t})
    if not ids:
        raise ProbeError("No touch pointers in action transaction")
    rows={i:[] for i in ids}
    live=set()
    positioned=set()
    for tick in ticks:
        if isinstance(tick,int):
            tick={i:{"type":"pause","duration":tick} for i in ids}
        for i in ids:
            action=tick.get(i,{"type":"pause","duration":0})
            kind=action["type"]
            if kind=="pointerMove":
                positioned.add(i)
            elif kind=="pointerDown":
                if i in live or i not in positioned:
                    raise ProbeError("Unpositioned or repeated touch pointerDown")
                live.add(i)
            elif kind=="pointerUp":
                if i not in live:
                    raise ProbeError("pointerUp without matching in-request pointerDown")
                live.remove(i)
            elif kind!="pause":
                raise ProbeError("Unsupported touch action "+kind)
            rows[i].append(action)
    if live:
        raise ProbeError("Action transaction must release every started pointer")
    return {"actions":[{"type":"pointer","id":f"vc-finger-{i}",
                        "parameters":{"pointerType":"touch"},"actions":rows[i]} for i in ids]}


def tap_ticks(point):
    return [{0:move(point,80)},{0:press()},75,{0:release()}]


def pair_prefix(a,b):
    return [{0:move(a,80),1:move(b,80)},{0:press(),1:press()}]


def release_pattern(events):
    return [len(e["active"]) for e in events if e["type"]=="touchend"]


def trusted(events, target="canvas"):
    return bool(events) and all(e["trusted"] and e["target"]==target
                                and e["type"]!="touchcancel" for e in events)


class ChromeDriver:
    """Stock hosted ChromeDriver, W3C Actions; CDP connection only for observation."""
    def __init__(self, executable, chrome, size, home, out):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1",0))
            self.port=listener.getsockname()[1]
        self.opener=build_opener(ProxyHandler({}))
        self.session=None
        self.proc=None
        self.logs=(out/"chromedriver.log").open("wb")
        try:
            self.proc=subprocess.Popen([executable,f"--port={self.port}","--allowed-ips=127.0.0.1"],
                 stdout=self.logs,stderr=self.logs,env={**os.environ,"HOME":home,
                    "XDG_CONFIG_HOME":home,"XDG_CACHE_HOME":home})
            deadline=time.monotonic()+15
            while True:
                try:
                    if self.request("GET","/status").get("ready"):
                        break
                except OSError:
                    pass
                if self.proc.poll() is not None or time.monotonic()>deadline:
                    raise ProbeError("ChromeDriver did not become ready")
                time.sleep(.12)
            width,height=size
            options={"binary":chrome,"args":["--headless","--no-first-run",
                "--disable-background-networking","--disable-dev-shm-usage","--use-gl=angle",
                "--use-angle=swiftshader","--enable-unsafe-swiftshader",
                "--user-data-dir="+str(Path(home)/"isolated-profile")],
                "mobileEmulation":{"deviceMetrics":{"width":width,"height":height,
                    "pixelRatio":1,"touch":True,"mobile":True}}}
            data=self.request("POST","/session",{"capabilities":{"alwaysMatch":{
                     "browserName":"chrome","goog:chromeOptions":options}}})
            self.session=data["sessionId"]
            self.cdp_url="http://"+data["capabilities"]["goog:chromeOptions"]["debuggerAddress"]
        except Exception:
            self.close()
            raise

    def request(self, method, path, data=None):
        req=Request(f"http://127.0.0.1:{self.port}"+path,
                    json.dumps(data).encode() if data is not None else None,
                    headers={"content-type":"application/json"},method=method)
        with self.opener.open(req,timeout=40) as response:
            return json.load(response)["value"]

    def execute(self, ticks):
        payload=actions_transaction(ticks)
        self.request("POST",f"/session/{self.session}/actions",payload)

    def close(self):
        if self.session:
            try: self.request("DELETE",f"/session/{self.session}")
            except Exception: pass
            self.session=None
        if self.proc is not None and self.proc.poll() is None:
            self.proc.terminate()
            try: self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
        self.logs.close()


class Probe:
    def __init__(self, browser, width, height, out, receipt, driver):
        self.out = out
        self.r = receipt
        self.size = (width, height)
        self.driver = driver
        # One blank context/page is created for this owned ChromeDriver only.
        self.ctx = browser.contexts[0]
        self.page = self.ctx.pages[0]
        self.cdp = self.ctx.new_cdp_session(self.page)
        self.cdp.send("Network.setBypassServiceWorker",{"bypass":True})
        self.asset_responses = {}
        self.page.on("response", self.response)
        self.page.on("pageerror", lambda e: self.r["page_errors"].append(str(e)))
        self.page.on("requestfailed", lambda q: self.r["failed_requests"].append(
            {"url": q.url, "reason": q.failure}))
        self.page.on("console", lambda msg: self.r["console"].append(
            {"type": msg.type, "text": msg.text[:700]})
                     if msg.type in ("warning", "error") and len(self.r["console"]) < 150 else None)

    def response(self, response):
        u = urlsplit(response.url)
        page = urlsplit(PACKAGE)
        if (u.scheme, u.netloc) == (page.scheme, page.netloc) and u.path.startswith(page.path):
            name = u.path.removeprefix(page.path)
            if name in HASHES:
                self.asset_responses[name] = response

    def check(self, label, passed, observed=None):
        self.r["checks"].append({"name": label, "pass": bool(passed), "observed": observed})
        print(f"{'PASS' if passed else 'FAIL'} {label}", flush=True)
        if not passed:
            raise ProbeError(label)

    def wait(self, predicate, label, seconds=18):
        start = time.monotonic()
        while time.monotonic()-start < seconds:
            result = predicate()
            if result:
                return result
            self.page.wait_for_timeout(110)
        raise ProbeError(f"Expected state not observed: {label} ({seconds}s)")

    def menu(self):
        return self.page.evaluate(MENU_SNAPSHOT)

    def world(self):
        return self.page.evaluate(WORLD_SNAPSHOT)

    def state(self, s):
        if not s:
            return None
        return {k:s.get(k) for k in ("build","tick","selected","own_pending_commands",
                                     "population","touch_mode","paused","game_over")} | {
            "camera": s["hud"].get("camera"), "detail": s["hud"].get("selection_detail")}

    def screenshot(self, name):
        self.page.screenshot(path=str(self.out / (name+".png")), timeout=15000)
        self.r["screenshots"].append(name+".png")

    def phase(self, phase):
        self.r["phase"] = phase
        self.page.evaluate("phase => { window.__vcGestureAudit.phase = phase; }", phase)

    def traces(self):
        return self.page.evaluate("""() => {
          const a=window.__vcGestureAudit;
          return a ? {events:a.events,samples:a.samples} : {events:[],samples:[]};
        }""")

    def require_input(self, label, condition, observed=None):
        if not condition:
            self.r["input_limitation"]=label
        self.check(label,condition,observed)

    def tap(self, point):
        phase=self.r["phase"]
        previous=len(self.phases(phase)["events"])
        self.driver.execute(tap_ticks(point))
        self.page.wait_for_timeout(150)
        events=self.phases(phase)["events"][previous:]
        self.require_input("trusted canvas tap delivered both press and release",
            trusted(events) and [e["type"] for e in events]==["touchstart","touchend"]
            and [len(e["active"]) for e in events]==[1,0],events)

    def preflight(self):
        # Plain transient DOM, before loading the game. Proves transport on this
        # Chrome/ChromeDriver pair and cannot be counted as gameplay.
        self.page.set_content("""<meta name="viewport" content="width=device-width,initial-scale=1">
            <style>html,body{margin:0;touch-action:none}canvas{width:100vw;height:100vh;display:block;touch-action:none}</style>
            <canvas id="canvas"></canvas>""")
        self.page.evaluate(LISTEN)
        self.phase("fixture-tap")
        self.tap((60,80))
        self.phase("fixture-pair")
        a,b=(54,95),(120,95)
        self.driver.execute(pair_prefix(a,b)+[80,{0:move((64,105),120),1:move((130,105),120)},
          90,{1:release()},95,{0:move((86,120),100)},90,{0:release()}])
        self.page.wait_for_timeout(125)
        e=self.phases("fixture-pair")["events"]
        self.r["input_preflight"]=self.traces()["events"]
        with_two=any(row["type"]=="touchmove" and len(row["active"])==2 for row in e)
        lift=next((row for row in e if row["type"]=="touchend" and len(row["active"])==1),None)
        retained=bool(lift and any(row["type"]=="touchmove" and len(row["active"])==1
                    and row["active"][0][0]==lift["active"][0][0]
                    and row["timeMs"]>lift["timeMs"] for row in e))
        self.require_input("plain DOM preflight received trusted pair, partial lift and retained-finger drag",
                           trusted(e) and with_two and release_pattern(e)==[1,0] and retained,e)

    def during(self, ticks, phase, checkpoints):
        """Playwright stays on this thread; worker only sends raw W3C HTTP."""
        results=[]
        with ThreadPoolExecutor(max_workers=1) as pool:
            future=pool.submit(self.driver.execute,ticks)
            previous=-1
            for positions, screenshot in checkpoints:
                def held():
                    events=self.phases(phase)["events"]
                    if not events:
                        return None
                    event=events[-1]
                    active=[p[1:] for p in event["active"]]
                    distance=lambda a,b: math.dist(a,b)
                    if (event["timeMs"]>previous and len(active)==len(positions)
                        and all(any(distance(p,q)<=2 for q in active) for p in positions)):
                        return event
                    if future.done():
                        future.result()
                        raise ProbeError(f"{phase}: action completed before observable held checkpoint")
                    return None
                event=self.wait(held,phase+" held positions "+str(positions),seconds=10)
                previous=event["timeMs"]
                self.page.wait_for_timeout(95)  # allow engine input processing while held
                state=self.world()
                if screenshot:
                    self.screenshot(screenshot)
                    # Don't label a post-release frame as held.
                    last=self.phases(phase)["events"][-1]
                    self.check("recorded "+screenshot+" while intended contacts held",
                               last["active"]==event["active"],last)
                results.append(state)
            future.result(timeout=40)
        self.page.wait_for_timeout(160)
        return results

    def box(self, plan):
        ticks=[{0:move(plan["start"],80)},{0:press()},250]
        ticks += [{0:move(point,30)} for point in path_steps(plan["start"],plan["end"],9)]
        ticks += [2100,{0:release()}]
        self.during(ticks,"box",[([plan["end"]],"02-box-held")])

    def phases(self, *names):
        rows = self.traces()
        return {k:[x for x in vs if x["phase"] in names] for k,vs in rows.items()}

    def choose(self, expected, button):
        last = None
        repeat = 0
        def stable():
            nonlocal last, repeat
            now = self.menu()
            if not now or not now.get("visible") or now.get("page") != expected:
                return None
            item = next((x for x in now["buttons"] if x["id"] == button), None)
            if item is None:
                return None
            x,y,w,h = item["rect"]
            point = round(x+w/2),round(y+h/2)
            if min(w,h)<40 or any(
                inside(point,(ox,oy,ox+ow,oy+oh)) for x in now["buttons"]
                if x["id"]!=button for ox,oy,ow,oh in [x["rect"]]
            ):
                return None
            key = json.dumps(now["buttons"])
            repeat = repeat + 1 if last == key else 1
            last = key
            return point if repeat>=3 else None
        point = self.wait(stable, expected+"/"+button)
        self.r["menu_route"].append({"page":expected,"button":button,"point":point})
        self.tap(point)

    def quiet(self, phases, ids, *, scout=False):
        rows = self.phases(*phases)["samples"]
        good = (len(rows) >= 5 and all(row["commands"] == 0 and not row["mode"]
                    and not row["paused"] and not row["gameOver"] for row in rows))
        if ids is not None:
            good = good and all(row["selected"] == ids for row in rows)
        if scout:
            good = good and all("待命" in row["detail"] and "移動" not in row["detail"] for row in rows)
        return good, {"samples":len(rows), "command_max":max((r["commands"] for r in rows),default=None),
                      "hud_labels":sorted({r["detail"] for r in rows}),
                      "tick_range":[rows[0]["tick"],rows[-1]["tick"]] if rows else []}

    def run(self):
        self.preflight()
        meta = self.ctx.request.get(ORIGIN+"release.json", timeout=30000)
        advertised = meta.json()
        self.check("current public release matches the frozen build and source",
                   meta.ok and advertised["build"]==BUILD and advertised["source_commit"]==SOURCE
                   and all(advertised["files_sha256"].get(k)==v for k,v in HASHES.items()),
                   {"status":meta.status,"build":advertised.get("build"),"source":advertised.get("source_commit")})
        response = self.page.goto(ENTRY, wait_until="domcontentloaded", timeout=45000)
        self.check("versioned public entry preserves the QA query without redirect",
                   response is not None and response.ok and self.page.url==ENTRY,
                   {"status":response.status if response else None,"url":self.page.url})
        self.wait(lambda: (s:=self.menu()) and s.get("visible") and s.get("page")=="home",
                  "real Web menu", seconds=125)
        self.r["asset_sha256"] = {}
        self.r["asset_hash_methods"] = {}
        for name in HASHES:
            asset=self.asset_responses.get(name)
            if asset is None or not asset.ok:
                continue
            try:
                digest=hashlib.sha256(asset.body()).hexdigest()
                method="browser response body"
            except Exception as exc:
                # Some Chrome versions evict large streaming responses from CDP's
                # resource buffers. Verify a separate HTTP fetch of the exact URL
                # and report explicitly that this was not the browser-held body.
                with urlopen(asset.url, timeout=45) as again:
                    if again.status != 200 or again.geturl() != asset.url:
                        raise ProbeError("Re-fetch failed for runtime response: "+asset.url)
                    digest=hashlib.file_digest(again,"sha256").hexdigest()
                method="separate GET of observed browser response URL: "+str(exc)[:250]
            self.r["asset_sha256"][name]=digest
            self.r["asset_hash_methods"][name]=method
        self.check("four observed runtime asset URLs match the published release hashes",
                   self.r["asset_sha256"]==HASHES, self.r["asset_sha256"])
        geom = self.page.evaluate("""() => {
          const c=document.querySelector('#canvas').getBoundingClientRect();
          return {size:[innerWidth,innerHeight,c.width,c.height],x:c.left,y:c.top,
             webgl:!!document.createElement('canvas').getContext('webgl2')};
        }""")
        self.check("touch coordinates map directly to a real WebGL canvas",
                   geom["size"]==list(self.size)*2 and geom["x"]==geom["y"]==0 and geom["webgl"],geom)
        self.page.evaluate(LISTEN)
        self.phase("menu")
        for page, button in MENU:
            self.choose(page, button)
        initial = self.wait(lambda: (s:=self.world()) and s.get("hud",{}).get("viewport")
                            and s["tick"]>=10 and s, "ordinary Classical battle", seconds=55)
        self.r["initial"] = self.state(initial)
        width,height = self.size
        initial_camera = {"focus":[-25,0,24],"zoom":22 if width>height else 30}
        self.check("runtime build ID, viewport, Classical population and camera are exact",
                   initial["build"]==BUILD and initial["population"]==6
                   and initial["hud"]["viewport"]==list(self.size)
                   and initial["hud"]["camera"]==initial_camera,self.state(initial))
        self.screenshot("01-initial")

        # One-finger group-box proof via the projected visible own-worker positions.
        self.phase("box")
        plan = self.wait(lambda: (s:=self.world()) and plan_box(s,self.size),
                         "two owned villagers inside an unoccluded drag candidate")
        self.r["box_plan"] = plan
        self.box(plan)
        box_result = self.world()
        self.r["box_result"] = self.state(box_result)
        trace = self.phases("box")["events"]
        self.require_input("trusted one-contact canvas drag and release arrived",
                   trusted(trace) and all(len(x["active"])<=1 for x in trace)
                   and trace[0]["type"]=="touchstart"
                   and sum(x["type"]=="touchmove" for x in trace)>=2
                   and next(x["timeMs"] for x in trace if x["type"]=="touchmove")-trace[0]["timeMs"]>=225
                   and trace[-1]["type"]=="touchend" and not trace[-1]["active"],trace)
        got = set(box_result["selected"])
        self.check("release selects at least two intended workers and excludes seen outside workers",
                   set(plan["in_box_worker_ids"]) <= got
                   and not got.intersection(plan["out_of_box_worker_ids"]), sorted(got))
        quiet, qt = self.quiet(("box",), None)
        self.check("single-finger box did not pan or show a pending command",
                   box_result["hud"]["camera"]==initial_camera and quiet,qt)
        self.screenshot("03-box-selected")

        # Scout starts idle; its HUD status makes a stray move observable.
        self.phase("scout-select")
        point = POINTS[self.size]["scout"]
        self.tap(point)
        before = self.wait(lambda: (s:=self.world()) and s["selected"]==[6] and
                           "待命" in s["hud"]["selection_detail"] and s, "sole idle Scout 6")
        self.r["scout_before"] = self.state(before)
        self.screenshot("04-scout-before-pan")
        first, second = POINTS[self.size]["pair"]
        offsets = path_steps((0,0),(42,28),14)
        camera0 = before["hud"]["camera"]
        self.phase("pan")
        def pair_at(dx,dy):
            return ((first[0]+dx,first[1]+dy),(second[0]+dx,second[1]+dy))
        def pair_move(dx,dy):
            a,b=pair_at(dx,dy)
            return {0:move(a,35),1:move(b,35)}
        # Start, pan, 2→1, residual drag, and release stay in ONE action request.
        ticks=pair_prefix(first,second)+[70]
        ticks.extend(pair_move(dx,dy) for dx,dy in offsets)
        ticks.append(2100)
        ticks.extend(pair_move(dx,dy) for dx,dy in reversed([(0,0)]+offsets[:-1]))
        ticks.extend([1300,{1:release()},125])
        remaining_positions=[(first[0]+dx,first[1]+dy)
                             for dx,dy in [(5,4),(11,8),(18,12),(25,18),(34,20)]]
        ticks.extend({0:move(point,40)} for point in remaining_positions)
        ticks.extend([2100,{0:release()}])
        peak,returned,_=self.during(ticks,"pan",[
            (pair_at(*offsets[-1]),"05-two-finger-pan-apex"),
            ((first,second),None),
            ([remaining_positions[-1]],"06-one-finger-held-after-pan")])
        self.r["pan_peak"] = self.state(peak)
        rows = [e for e in self.phases("pan")["events"] if len(e["active"])==2]
        spans = [math.dist(e["active"][0][1:],e["active"][1][1:]) for e in rows]
        self.require_input("trusted two-contact canvas moves carried the equal start/end span",
                   len(rows)>=4 and trusted(rows)
                   and {p[0] for p in rows[0]["active"]}=={p[0] for p in rows[-1]["active"]}
                   and abs(spans[0]-spans[-1])<=.5,{"paired":len(rows),"spans":spans})
        self.check("pan moved camera focus without pinch zoom and kept sole selection",
                   camera_distance(camera0,peak["hud"]["camera"])>=.5
                   and abs(camera0["zoom"]-peak["hud"]["camera"]["zoom"])<.1
                   and peak["selected"]==[6],self.state(peak))
        self.check("return stroke restores the exact-scout fixture camera",
                   camera_distance(camera0,returned["hud"]["camera"])<.12
                   and abs(camera0["zoom"]-returned["hud"]["camera"]["zoom"])<.1,self.state(returned))
        wait_from = self.world()
        released = self.wait(lambda: (s:=self.world()) and s["tick"]>=wait_from["tick"]+45 and s,
                             "45 post-release simulation ticks",15)
        trace = self.phases("pan")["events"]
        remaining = next((e for e in trace if e["type"]=="touchend" and len(e["active"])==1
                          and len(e["changed"])==1),None)
        self.require_input("trusted 2-to-1 partial release, retained-finger drag and final release arrived",
                   remaining is not None and trusted(trace) and release_pattern(trace)==[1,0]
                   and any(e["type"]=="touchmove" and len(e["active"])==1
                           and e["active"][0][0]==remaining["active"][0][0]
                           and e["timeMs"]>remaining["timeMs"] for e in trace)
                   and trace[-1]["type"]=="touchend" and not trace[-1]["active"],trace)
        quiet, qt = self.quiet(("pan",),[6],scout=True)
        self.check("pan and 2-to-1 aftermath kept Scout 6 idle, with no observed own command",
                   quiet and released["selected"]==[6] and "待命" in released["hud"]["selection_detail"]
                   and camera_distance(returned["hud"]["camera"],released["hud"]["camera"])<.05
                   and released["hud"]["camera"]["zoom"]==returned["hud"]["camera"]["zoom"],qt)
        self.screenshot("07-all-fingers-released")

        # A second 2→1 case leaves the remaining finger stationary on the exact
        # known movement point. This catches stray taps that a long drag could mask.
        self.phase("stationary-release")
        goal = POINTS[self.size]["goal"]
        other = (goal[0]-65,goal[1])
        self.driver.execute(pair_prefix(goal,other)+[100,{1:release()},130,{0:release()}])
        base = self.world()
        stationary = self.wait(lambda: (s:=self.world()) and s["tick"]>=base["tick"]+45 and s,
                               "stationary release did not stall play",15)
        sr = self.phases("stationary-release")["events"]
        qa, qdetails = self.quiet(("stationary-release",),[6],scout=True)
        self.require_input("stationary partial lift reached canvas as trusted 2→1→0",
                           release_pattern(sr)==[1,0] and trusted(sr),sr)
        self.check("stationary 2-to-1 release at the known ground goal did not dispatch the scout",
                   qa and stationary["selected"]==[6]
                   and camera_distance(camera0,stationary["hud"]["camera"])<.12, {"touch":sr,"samples":qdetails})
        self.screenshot("08-stationary-release")

        # Positive control is the same authored open-ground tap as the stock v143 audit.
        self.phase("fresh-tap")
        self.tap(goal)
        def moving():
            samples = self.phases("fresh-tap")["samples"]
            return next((s for s in samples if s["selected"]==[6] and "移動" in s["detail"]),None)
        moved = self.wait(moving,"fresh one-finger ground tap initiates movement",12)
        self.check("fresh tap truly moves the same scout, with no camera movement or command mode",
                   self.world()["selected"]==[6] and not moved["mode"]
                   and camera_distance(camera0,moved["camera"])<.12
                   and abs(camera0["zoom"]-moved["camera"]["zoom"])<.1,moved)
        self.screenshot("09-fresh-tap")
        idle = self.wait(lambda: (s:=self.world()) and s["tick"]>moved["tick"]
                         and s["selected"]==[6] and "待命" in s["hud"]["selection_detail"] and s,
                         "same scout naturally returns to idle",16)
        self.r["scout_after_fresh_tap"] = self.state(idle)
        self.screenshot("10-scout-idle-after-fresh-tap")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size",choices=["390x844","844x390"],required=True)
    parser.add_argument("--out",type=Path,required=True,help="new evidence directory")
    parser.add_argument("--chrome",help="path to GitHub-hosted Chrome or Chromium executable")
    parser.add_argument("--driver",help="path to ChromeDriver for W3C Actions (default: PATH/CHROMEWEBDRIVER)")
    parser.add_argument("--input",choices=["webdriver"],default="webdriver",
                        help="complete W3C multi-pointer transaction per gesture")
    args=parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=False)
    r = {"status":"STARTED","url":ENTRY,"build":BUILD,"source":SOURCE,"size":args.size,
         "checks":[],"screenshots":[],"menu_route":[],"page_errors":[],"failed_requests":[],
         "console":[],"input_backend":args.input,
         "scope":"Fresh software-rendered Chromium, trusted browser touch; not physical iPhone/Safari."}
    rc=1
    try:
        from playwright.sync_api import sync_playwright
        chrome=browser_bin(args.chrome)
        if not chrome:
            raise ProbeError("No browser executable; pass --chrome or set CHROME_BIN")
        with tempfile.TemporaryDirectory(prefix="vc-v143-profile-") as browser_home, sync_playwright() as p, contextlib.ExitStack() as cleanup:
            size=tuple(map(int,args.size.split("x")))
            wd=args.driver or shutil.which("chromedriver")
            if not wd and os.environ.get("CHROMEWEBDRIVER"):
                wd=str(Path(os.environ["CHROMEWEBDRIVER"])/"chromedriver")
            if not wd or not Path(wd).is_file():
                raise ProbeError("No ChromeDriver; use --driver with a version matching Chrome")
            driver=ChromeDriver(wd,chrome,size,browser_home,args.out)
            cleanup.callback(driver.close)
            browser=p.chromium.connect_over_cdp(driver.cdp_url,timeout=20000)
            cleanup.callback(browser.close)
            r["browser_version"]=browser.version
            print(f"Started isolated Chromium {browser.version}, input={args.input}",flush=True)
            probe=Probe(browser,*size,args.out,r,driver)
            try:
                probe.run()
                r["status"]="PASS"
                rc=0
            except Exception:
                try: probe.screenshot("99-failure-frame")
                except Exception: pass
                raise
            finally:
                try:
                    (args.out/"touch-events-and-hud.json").write_text(
                        json.dumps(probe.traces(),ensure_ascii=False,indent=2)+"\n")
                except Exception as exc:
                    r["trace_error"]=str(exc)[:1000]
                    r["status"]="FAIL"
                    rc=1
    except Exception as exc:
        r["status"]="BLOCKED" if not r.get("browser_version") or r.get("input_limitation") else "FAIL"
        r["exception"]=f"{type(exc).__name__}: {exc}"[:2200]
        print(f'{r["status"]}: {r["exception"]}',flush=True)
    finally:
        (args.out/"receipt.json").write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")
    return rc

if __name__ == "__main__":
    raise SystemExit(main())
