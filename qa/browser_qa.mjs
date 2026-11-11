// Construction scenario only. Importing this module never launches a browser.
// Replace the fixture in an isolated, reviewed copy of the existing guarded QA
// bundle; keep host_main and containment code/limits unchanged. Pins required.
import assert from 'node:assert/strict';
import {readFile, writeFile, rename} from 'node:fs/promises';
import {createNetworkDiagnostics} from './network_diagnostics.mjs';

export function validateManifest(manifest) {
  assert.equal(manifest.reviewed, true, 'Construction export pins not reviewed');
  assert.match(manifest.build, /^vc-[0-9a-f]{12}$/);
  assert.match(manifest.source_commit, /^[0-9a-f]{40}$/);
  assert.equal(manifest.profile, 'portrait');
  assert.equal(manifest.hud_schema, 1);
  assert.ok(manifest.files_sha256 && Object.keys(manifest.files_sha256).length >= 3);
  for (const required of ['index.html', 'index.pck', 'index.wasm']) assert.match(manifest.files_sha256[required], /^[0-9a-f]{64}$/);
  for (const [name, digest] of Object.entries(manifest.files_sha256)) {
    assert.ok(!name.startsWith('/') && !name.includes('\\') && name.split('/').every(part => part && part !== '.' && part !== '..'));
    assert.match(digest, /^[0-9a-f]{64}$/);
  }
  return manifest;
}

export function mapPoint(point, viewport, box) {
  assert.ok(Array.isArray(point) && point.length === 2 && point.every(Number.isFinite));
  assert.ok(Array.isArray(viewport) && viewport.length === 2 && viewport.every(v => Number.isFinite(v) && v > 0));
  assert.ok(box && box.width > 0 && box.height > 0);
  assert.ok(point[0] >= 0 && point[0] < viewport[0] && point[1] >= 0 && point[1] < viewport[1], 'Telemetry point outside viewport');
  return [box.x + point[0] * box.width / viewport[0], box.y + point[1] * box.height / viewport[1]];
}

export function validateCanvasGeometry(geometry, expectedBox=null) {
  assert.ok(geometry, 'Canvas DOM geometry missing');
  const {box,viewport,display,visibility,opacity}=geometry;
  assert.deepEqual(viewport,[390,844], 'CSS viewport differs from fixed portrait context');
  assert.ok(box && ['x','y','width','height'].every(key => Number.isFinite(box[key])), 'Nonfinite canvas bounds');
  assert.ok(box.width>0 && box.height>0 && box.x>=0 && box.y>=0 &&
    box.x+box.width<=viewport[0]+0.5 && box.y+box.height<=viewport[1]+0.5, 'Canvas not positive and fully onscreen');
  assert.ok(display!=='none' && visibility==='visible' && Number.isFinite(opacity) && opacity>0, 'Canvas CSS is not visible');
  if (expectedBox) assert.deepEqual(box,expectedBox,'Canvas DOM geometry changed; cached input mapping invalid');
  return box;
}

export function buttonByText(state, matcher) {
  assert.equal(state.hud?.schema, 1, 'Read-only public HUD telemetry missing');
  const matches = state.hud.buttons.filter(button => !button.disabled && matcher.test(button.text) &&
    Array.isArray(button.rect) && button.rect.length === 4 && button.rect.every(Number.isFinite) && button.rect[2] >= 12 && button.rect[3] >= 12);
  assert.ok(matches.length <= 1, 'Ambiguous visible button');
  return matches[0] ?? null;
}

export function selectedSite(state, id) {
  return state.hud.selected_own.find(item => item.id === id && item.category === 'building') ?? null;
}

export function assertStoppedProgress(before, after, siteId) {
  assert.equal(before.paused, false); assert.equal(after.paused, false);
  assert.ok(before.hud.selection_detail.includes('無施工村民'));
  assert.ok(after.hud.selection_detail.includes('無施工村民'));
  const a = selectedSite(before, siteId), b = selectedSite(after, siteId);
  assert.ok(a && b && !a.built && !b.built, 'Expected same unfinished selected site');
  assert.equal(a.progress, b.progress, 'Construction advanced with no builder');
  assert.ok(after.tick - before.tick >= 20, 'Need one real simulation second of stopped progress');
}

export function assertResumedProgress(stopped, active, siteId) {
  assert.equal(active.paused, false);
  assert.ok(active.hud.selection_detail.includes('建造中'), 'HUD never showed active construction');
  const before = selectedSite(stopped, siteId), after = selectedSite(active, siteId);
  assert.ok(before && after && !after.built, 'Need unfinished site during active witness');
  assert.ok(after.progress > before.progress, 'Resumed construction did not advance');
  assert.ok(active.tick > stopped.tick);
}

export async function swipeActionStrip(cdp, from, to, delay) {
  const point = (x,y) => ({x,y,id:7,radiusX:3,radiusY:3,force:1});
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point(...from)]});
  // Two ordinary moves cross the drag threshold and traverse the same visible
  // strip. Keep150ms gesture duration without six CDP/browser round trips.
  for (const fraction of [0.5,1]) {
    await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[point(from[0]+(to[0]-from[0])*fraction,from[1])]});
    await delay(75);
  }
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
}

export async function runQA(browser, outputDirectory, origin, profile) {
  assert.equal(profile, 'portrait', 'Construction scenario must remain in one portrait context');
  assert.match(origin, /^http:\/\/127\.0\.0\.1:\d+$/);
  const manifest = validateManifest(JSON.parse(await readFile(new URL('./scenario-manifest.json', import.meta.url), 'utf8')));
  const started = Date.now();
  const evidence = {build: manifest.build, source_commit: manifest.source_commit, files_sha256: manifest.files_sha256,
    profile, scenario: 'natural-construction-stop-resume', basicSmokePassed: false, releaseQAPassed: false,
    phase: 'starting', checkpoints: [], errors: [], error_count: 0, error_limit: 64,
    input: 'Chrome emulated touchscreen taps and ordinary touch swipes; not a physical iPhone',
    observation: 'existing read-only valleySnapshot plus sanitized public HUD telemetry',
    not_run: ['real iPhone Safari', 'real Android Chrome', 'combat', 'complete house construction', 'audible audio',
      'optional paused-HUD screenshot omitted to preserve the fixed scenario budget']};
  const addError = error => {evidence.error_count++; if (evidence.errors.length < evidence.error_limit) evidence.errors.push(error);};
  const network = createNetworkDiagnostics(() => evidence.phase, addError);
  evidence.network = network.data;
  const persist = async () => {
    await writeFile(`${outputDirectory}/browser-evidence.json.tmp`, JSON.stringify(evidence, null, 2));
    await rename(`${outputDirectory}/browser-evidence.json.tmp`, `${outputDirectory}/browser-evidence.json`);
  };
  const checkpoint = async (phase, state = null) => {
    evidence.phase = phase; evidence.checkpoints.push({phase, elapsed_ms: Date.now() - started, state}); await persist();
  };
  const withinBudget = () => assert.ok(Date.now() - started < 70000, 'Scenario 70-second inner budget exhausted; external guard unchanged');
  let context, page;
  try {
    await checkpoint('starting');
    context = await browser.newContext({viewport: {width:390,height:844}, deviceScaleFactor:1, hasTouch:true, serviceWorkers:'block'});
    page = await context.newPage();
    page.setDefaultTimeout(5000);
    page.on('pageerror', error => addError({kind:'pageerror', text:String(error).slice(0,2000)}));
    page.on('console', message => {if (message.type() === 'error') addError({kind:'console',text:message.text().slice(0,2000)});});
    context.on('request', network.request);
    context.on('response', network.response);
    context.on('requestfinished', network.finished);
    context.on('requestfailed', network.failed);
    await page.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
    await page.goto(`${origin}/index.html?qa`, {waitUntil:'load',timeout:25000});
    await page.waitForFunction(() => typeof window.valleySnapshot === 'function', null, {timeout:20000});
    const delay = milliseconds => new Promise(resolve => setTimeout(resolve,milliseconds));
    // Fixed context viewport, no navigation or resize after load. Read the real
    // canvas box once and fail if observed game viewport changes thereafter.
    let canvasBox = null;
    let logicalViewport;
    evidence.snapshot_count = 0;
    evidence.snapshot_total_ms = 0;
    evidence.read_timings = [];
    evidence.input_timings = [];
    const recordInput = record => {evidence.last_input=record; if (evidence.input_timings.length < 32) evidence.input_timings.push(record);};
    const snapshot = async () => {
      withinBudget();
      const readStarted = Date.now();
      const pending = page.evaluate(() => {
        window.valleySnapshot();
        let geometry=null;
        const canvas=document.querySelector('canvas');
        if (canvas) {
          const rect=canvas.getBoundingClientRect(),style=getComputedStyle(canvas);
          geometry={box:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},viewport:[innerWidth,innerHeight],
            display:style.display,visibility:style.visibility,opacity:Number(style.opacity),position:style.position};
        }
        return {state:window.valleyState,geometry};
      });
      let observation;
      if (canvasBox===null) {
        let readTimer;
        try {
          observation=await Promise.race([pending,new Promise((_,reject) => {
            readTimer=setTimeout(() => reject(new Error('Canvas geometry/snapshot read exceeded5000ms')),5000);
          })]);
        } finally {clearTimeout(readTimer);}
        canvasBox=validateCanvasGeometry(observation.geometry);
        evidence.canvas_box=canvasBox; evidence.canvas_geometry=observation.geometry;
      } else {
        observation=await pending;
        validateCanvasGeometry(observation.geometry,canvasBox);
      }
      const state=observation.state;
      assert.equal(state.build, manifest.build); assert.equal(state.hud?.schema, manifest.hud_schema);
      if (logicalViewport) assert.deepEqual(state.hud.viewport,logicalViewport,'Viewport changed; cached input geometry invalid');
      else logicalViewport = [...state.hud.viewport];
      evidence.snapshot_count++;
      const duration = Date.now()-readStarted;
      evidence.snapshot_total_ms += duration;
      if (evidence.read_timings.length < 64) evidence.read_timings.push({elapsed_ms:Date.now()-started,duration_ms:duration,
        tick:state.tick,tick_delta:state.tick-(evidence.last_read?.state?.tick ?? state.tick),phase:evidence.phase});
      evidence.last_read = {elapsed_ms:Date.now()-started,duration_ms:duration,phase:evidence.phase,state,
        summary:{tick:state.tick,scroll_horizontal:state.hud.action_scroll?.scroll_horizontal,
          visible_buttons:state.hud.buttons.slice(0,16).map(button => String(button.text).slice(0,80)),
          read_duration_ms:duration,last_input:evidence.last_input ?? null}};
      await persist();
      withinBudget();
      return state;
    };
    const waitFor = async (condition, milliseconds, label) => {
      const until = Date.now() + milliseconds;
      do {
        const state = await snapshot();
        if (condition(state)) return state;
        await delay(160);
      } while (Date.now() < until);
      throw new Error('Timed out: ' + label);
    };
    const screenPoint = (state, point) => mapPoint(point, state.hud.viewport, canvasBox);
    const tap = async (state, point, label='visible-point') => {
      withinBudget(); const inputStarted=Date.now();
      await page.touchscreen.tap(...screenPoint(state, point));
      recordInput({kind:'tap',label:String(label).slice(0,64),elapsed_ms:Date.now()-started,duration_ms:Date.now()-inputStarted,before_tick:state.tick});
    };
    const tapButton = async (state, matcher) => {
      const button = buttonByText(state, matcher);
      assert.ok(button, 'Required visible enabled button absent: ' + matcher);
      await tap(state, [button.rect[0]+button.rect[2]/2, button.rect[1]+button.rect[3]/2],button.text);
    };
    const target = (state, id) => state.hud.own_targets.find(item => item.id === id);
    const tapOwn = async (state, id) => {
      const item = target(state, id);
      assert.ok(item, 'Own target no longer visibly tappable: ' + id);
      await tap(state, item.screen,'own-target:'+id);
    };
    const initial = await snapshot();
    await checkpoint('loaded-with-public-hud',initial);
    assert.equal(initial.paused, false);
    const worker = initial.hud.own_targets.find(item => item.kind === 'villager');
    assert.ok(worker, 'No current publicly visible tappable own villager');
    await tapOwn(initial, worker.id);
    const workerSelected = await waitFor(state => state.selected.length === 1 && state.selected[0] === worker.id, 3000, 'worker selected');
    await tapButton(workerSelected, /^民居(?:\n|$)/);
    const preview = await waitFor(state => state.build_mode === 'house' && state.hud.preview?.placement_ok, 4000, 'existing visible legal house preview');
    assert.ok(preview.hud.preview.screen, 'Visible ghost point missing');
    const woodBefore = preview.bank_milli.wood;
    await tap(preview, preview.hud.preview.screen);
    const held = await waitFor(state => state.hud.preview?.held && state.hud.preview?.placement_ok, 3000, 'ordinary plot tap held');
    await tapButton(held, /^確認建造$/);
    const placed = await waitFor(state => state.build_mode === '' && state.hud.own_targets.some(item => item.category === 'building' && item.kind === 'house' && !item.built), 5000, 'real house site placed');
    assert.equal(placed.bank_milli.wood, woodBefore - 50 * placed.economy_scale, 'One ordinary house payment required');
    const site = placed.hud.own_targets.find(item => item.category === 'building' && item.kind === 'house' && !item.built);
    assert.ok(site); await checkpoint('house-created-through-ui', {workerId:worker.id,siteId:site.id,state:placed});
    // Confirm normally preserves builder selection; do not force a world retap
    // when the newly placed site's pick halo temporarily covers that worker.
    let stripState = placed;
    if (!(placed.selected.length === 1 && placed.selected[0] === worker.id)) {
      await tapOwn(placed,worker.id);
      stripState = await waitFor(state => state.selected.length === 1 && state.selected[0] === worker.id, 3000, 'builder selected');
    }
    // Scroll the existing action strip through real browser touch input only.
    // No hidden button enumeration, direct scroll setter or game method call.
    const cdp = await context.newCDPSession(page);
    await checkpoint('finding-visible-stop',stripState);
    for (let swipe = 0; swipe < 6; swipe++) {
      const state = stripState;
      if (buttonByText(state, /^停止$/)) break;
      const rect = state.hud.action_scroll?.rect;
      assert.ok(rect?.length === 4 && rect[2] >= 48 && rect[3] >= 20, 'Visible action scroll region missing');
      const from = screenPoint(state, [rect[0]+rect[2]*0.85,rect[1]+rect[3]/2]);
      const to = screenPoint(state, [rect[0]+rect[2]*0.15,rect[1]+rect[3]/2]);
      withinBudget();
      const swipeStarted=Date.now();
      await swipeActionStrip(cdp,from,to,delay);
      const swipeFinished=Date.now();
      await delay(160);
      stripState = await snapshot();
      recordInput({kind:'swipe',swipe:swipe+1,elapsed_ms:Date.now()-started,input_ms:swipeFinished-swipeStarted,
        settle_read_ms:Date.now()-swipeFinished,before_tick:state.tick,after_tick:stripState.tick,
        scroll_before:state.hud.action_scroll.scroll_horizontal,scroll_after:stripState.hud.action_scroll.scroll_horizontal});
      await checkpoint('action-strip-swipe-observed',{swipe:swipe+1,state:stripState});
    }
    await tapButton(stripState, /^停止$/);
    await checkpoint('stop-tapped');
    // The stationary site is the same just-observed public target; selection is
    // confirmed by the subsequent actual HUD assertion, never assumed.
    await tapOwn(stripState, site.id);
    const stopped = await waitFor(state => state.own_pending_commands === 0 && state.hud.selection_detail.includes('無施工村民') && selectedSite(state,site.id), 5000, 'natural no-builder HUD');
    const stable = await waitFor(state => state.tick - stopped.tick >= 20, 6000, 'real simulation second while stopped');
    assertStoppedProgress(stopped, stable, site.id);
    await checkpoint('stopped-no-builder-progress-stable', {before:stopped,after:stable});
    await page.screenshot({path:`${outputDirectory}/portrait-construction-stopped.png`});
    const resumeState = await snapshot();
    const resumeWorker = resumeState.hud.own_targets.find(item => item.id === worker.id) ??
      resumeState.hud.own_targets.find(item => item.kind === 'villager');
    assert.ok(resumeWorker, 'No publicly visible tappable live villager to resume construction');
    await tapOwn(resumeState, resumeWorker.id);
    const resumeSelected = await waitFor(state => state.selected.length === 1 && state.selected[0] === resumeWorker.id, 3000, 'live villager reselected');
    evidence.resumeWorkerId = resumeWorker.id;
    await tapButton(resumeSelected, /^指令$/);
    const commandState = await waitFor(state => state.touch_mode === true, 3000, 'ordinary command mode');
    await tapOwn(commandState, site.id);
    const submitted = await waitFor(state => state.touch_mode === false, 3000, 'site command submitted');
    await tapOwn(submitted, site.id);
    await checkpoint('resume-command-submitted',submitted);
    const active = await waitFor(state => state.hud.selection_detail.includes('建造中') &&
      selectedSite(state,site.id)?.progress > selectedSite(stable,site.id).progress, 15000, 'natural resumed active construction');
    assertResumedProgress(stable, active, site.id);
    await checkpoint('resumed-active-progress-increased', active);
    await page.screenshot({path:`${outputDirectory}/portrait-construction-resumed.png`});
    assert.equal(evidence.error_count, 0, 'Browser errors recorded');
    await checkpoint('closing-context');
    await context.close(); context = null;
    assert.equal(evidence.error_count, 0, 'Browser errors during context close');
    evidence.basicSmokePassed = true;
    await checkpoint('completed');
  } catch (error) {
    evidence.basicSmokePassed = false;
    evidence.failure = String(error); evidence.failedDuringPhase = evidence.phase; evidence.phase = 'failed';
    await persist();
    if (page && !page.isClosed() && Date.now()-started < 68000) {
      try {
        await page.screenshot({path:`${outputDirectory}/portrait-construction-failure.png`,timeout:1500});
        evidence.failure_screenshot = 'written';
      } catch (captureError) {evidence.failure_screenshot = String(captureError).slice(0,500);}
    } else evidence.failure_screenshot = 'skipped: no remaining inner budget or page closed';
    throw error;
  } finally {
    if (context) {
      try {await context.close();}
      catch (error) {addError({kind:'context-close',text:String(error).slice(0,1000)});}
    }
    if (evidence.error_count) evidence.basicSmokePassed = false;
    await persist();
  }
  return evidence;
}
