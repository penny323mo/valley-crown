// Fixed natural390 consolidated scenario only. Importing never launches a browser.
// Replace the fixture in an isolated, reviewed copy of the existing guarded QA
// bundle; keep host_main and containment code/limits unchanged. Pins required.
import assert from 'node:assert/strict';
import {readFile, writeFile, rename} from 'node:fs/promises';
import {createNetworkDiagnostics} from './network_diagnostics.mjs';
import {menuButton,assertMenu,assertCamera,assertSameCamera,assertPausedMatch,assertFrozenMatch,contextResource,cargo,assertDirectGather,projectedMovement,menuSwipePoints} from './public_observation_assertions.mjs';
import {assertPublicStreamCompletions} from './public_stream_cache_policy.mjs';

export const PREPARED_SCENARIO = 'natural390';
export const PREPARED_VIEWPORT = Object.freeze([390,844]);

export function validateManifest(manifest) {
  assert.equal(manifest.reviewed, true, 'Construction export pins not reviewed');
  assert.match(manifest.build, /^vc-[0-9a-f]{12}$/);
  assert.match(manifest.source_commit, /^[0-9a-f]{40}$/);
  assert.equal(manifest.profile, 'portrait');
  assert.equal(manifest.scenario, PREPARED_SCENARIO, 'Wrong prepared scenario');
  assert.deepEqual(manifest.viewport, PREPARED_VIEWPORT, 'Wrong prepared viewport');
  assert.equal(manifest.hud_schema, 2);
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
  assert.deepEqual(viewport,PREPARED_VIEWPORT, 'CSS viewport differs from fixed prepared context');
  assert.ok(box && ['x','y','width','height'].every(key => Number.isFinite(box[key])), 'Nonfinite canvas bounds');
  assert.ok(box.width>0 && box.height>0 && box.x>=0 && box.y>=0 &&
    box.x+box.width<=viewport[0]+0.5 && box.y+box.height<=viewport[1]+0.5, 'Canvas not positive and fully onscreen');
  assert.ok(display!=='none' && visibility==='visible' && Number.isFinite(opacity) && opacity>0, 'Canvas CSS is not visible');
  if (expectedBox) assert.deepEqual(box,expectedBox,'Canvas DOM geometry changed; cached input mapping invalid');
  return box;
}

export function buttonByText(state, matcher) {
  assert.equal(state.hud?.schema, 2, 'Read-only public HUD telemetry missing');
  const matches = state.hud.buttons.filter(button => !button.disabled && matcher.test(button.text) &&
    Array.isArray(button.rect) && button.rect.length === 4 && button.rect.every(Number.isFinite) && button.rect[2] >= 12 && button.rect[3] >= 12);
  assert.ok(matches.length <= 1, 'Ambiguous visible button');
  return matches[0] ?? null;
}

// All rectangles are the existing telemetry's clipped, publicly visible rects.
// A 90 px clipped width proves the full fixed-width first build target fits.
function fullButton(state, matcher, width, inActionScroll) {
  const button = buttonByText(state, matcher);
  assert.ok(button, 'Required visible enabled button absent: ' + matcher);
  assert.equal(button.in_action_scroll, inActionScroll, 'Wrong pinned/scroll placement: ' + matcher);
  assert.ok(button.rect[2] >= width && button.rect[3] >= 46, 'Full touch target clipped: ' + matcher);
  const [x,y,w,h] = button.rect, viewport = state.hud.viewport;
  assert.ok(x >= 0 && y >= 0 && x+w <= viewport[0] && y+h <= viewport[1], 'Button outside public viewport');
  return button;
}
function separateButtons(a,b) {
  const [x,y,w,h]=a.rect,[u,v,p,q]=b.rect;
  assert.ok(x+w<=u || u+p<=x || y+h<=v || v+q<=y, 'Toolbar touch targets overlap');
}
function assertToolbar(state, targeting) {
  assert.equal(state.paused, false); assert.equal(state.game_over, false);
  assert.deepEqual(state.hud.viewport, PREPARED_VIEWPORT, 'Logical viewport differs from prepared fixture');
  assert.equal(state.touch_mode, targeting);
  assert.equal(state.build_mode, '');
  assert.equal(state.hud.action_scroll.scroll_horizontal, 0, 'No swipe needed');
  const command = fullButton(state, targeting ? /^指令中$/ : /^指令$/,54,false);
  const slot = fullButton(state, targeting ? /^取消$/ : /^停止$/,54,false);
  const house = fullButton(state, /^民居(?:\n|$)/,90,true);
  const inactive = buttonByText(state,targeting ? /^停止$/ : /^取消$/);
  assert.ok(!inactive || (targeting && inactive.in_action_scroll === true), 'Third pinned control crowds the toolbar');
  separateButtons(command,slot); separateButtons(command,house); separateButtons(slot,house);
  return {command,house,...(targeting ? {cancel:slot} : {stop:slot})};
}
export function assertPinnedStop(state) {return assertToolbar(state,false);}
export function assertCommandToolbar(state) {return assertToolbar(state,true);}

// No hidden order/state access. These observations can detect a queued command,
// visible applied Stop/movement, or economy change, not every transient command.
export function assertUnchangedEconomy(before, after) {
  for (const state of [before,after]) {
    assert.equal(state.paused,false); assert.equal(state.game_over,false);
    assert.equal(state.own_pending_commands,0,'Unexpected pending own command');
    assert.ok(state.bank_milli && ['food','wood'].every(k => Number.isSafeInteger(state.bank_milli[k]) && state.bank_milli[k]>=0));
    for (const key of ['economy_scale','population','capacity','delivered','built','trained']) {
      assert.ok(Number.isFinite(state[key]),'Missing public economy field: '+key);
    }
  }
  assert.deepEqual(after.bank_milli,before.bank_milli,'Unexpected bank change');
  for (const key of ['economy_scale','population','capacity','delivered','built','trained']) {
    assert.equal(after[key],before[key],'Unexpected economy/counter change: '+key);
  }
}
export function assertNoUnintendedOrder(before, after, workerId, targeting=false) {
  assertUnchangedEconomy(before,after);
  assertSameCamera(before,after);
  assert.deepEqual(before.selected,[workerId]); assert.deepEqual(after.selected,[workerId]);
  assert.equal(before.touch_mode,false); assert.equal(before.build_mode,'');
  assert.equal(after.touch_mode,targeting); assert.equal(after.build_mode,'');
  assert.ok(Number.isInteger(before.tick) && Number.isInteger(after.tick) && after.tick>=before.tick);
  const a=before.hud.own_targets.find(item => item.id===workerId && item.kind==='villager');
  const b=after.hud.own_targets.find(item => item.id===workerId && item.kind==='villager');
  assert.ok(a && b,'Selected idle worker no longer publicly tappable');
  assert.ok([a,b].every(item => Array.isArray(item.screen) && item.screen.length===2 && item.screen.every(Number.isFinite)));
  assert.deepEqual(b.screen,a.screen,'Selected idle worker moved unexpectedly');
  assert.match(before.hud.selection_detail,/待命/,'Short scenario must start from natural idle worker');
  assert.match(before.hud.selection_detail,/守備/,'Baseline must distinguish applied Stop from ordinary selection');
  assert.ok(!before.hud.selection_detail.includes('停止'));
  if (!targeting) assert.equal(after.hud.selection_detail,before.hud.selection_detail,'Worker visible order/status changed');
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

export async function runQA(browser, outputDirectory, origin, profile) {
  assert.equal(profile, 'portrait', 'Construction scenario must remain in one portrait context');
  assert.match(origin, /^http:\/\/127\.0\.0\.1:\d+$/);
  const manifest = validateManifest(JSON.parse(await readFile(new URL('./scenario-manifest.json', import.meta.url), 'utf8')));
  const started = Date.now();
  const evidence = {build: manifest.build, source_commit: manifest.source_commit, files_sha256: manifest.files_sha256,
    profile, scenario: PREPARED_SCENARIO, viewport: [...PREPARED_VIEWPORT], swipe_count: 0, toolbar_swipes: 0, menu_swipes: 0, basicSmokePassed: false, releaseQAPassed: false,
    phase: 'starting', checkpoints: [], errors: [], error_count: 0, error_limit: 64,
    input: 'Chrome emulated touchscreen; zero toolbar swipes; short320 permits one public menu swipe; not a physical iPhone',
    observation: 'read-only valleyMenuSnapshot and valleySnapshot plus public HUD schema2; no authority or setters',
    not_run: ['real iPhone Safari', 'real Android Chrome', 'combat', 'complete house construction', 'audible audio',
      'physical touch ergonomics, multi-touch cancellation, OS interruption, browser history and audible audio',
      'complete command ledger: public telemetry exposes pending count/status, not cumulative submission history']};
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
    context = await browser.newContext({viewport: {width:PREPARED_VIEWPORT[0],height:PREPARED_VIEWPORT[1]}, deviceScaleFactor:1, hasTouch:true, serviceWorkers:'block'});
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
    await page.waitForFunction(() => typeof window.valleyMenuSnapshot === 'function', null, {timeout:20000});
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
    const observe = async () => {
      withinBudget();
      const readStarted = Date.now();
      const pending = page.evaluate(() => {
        window.valleyMenuSnapshot();
        const game_bridge=typeof window.valleySnapshot==='function';
        if(game_bridge)window.valleySnapshot();
        let geometry=null;
        const canvas=document.querySelector('canvas');
        if (canvas) {
          const rect=canvas.getBoundingClientRect(),style=getComputedStyle(canvas);
          geometry={box:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},viewport:[innerWidth,innerHeight],
            display:style.display,visibility:style.visibility,opacity:Number(style.opacity),position:style.position};
        }
        return {state:game_bridge?window.valleyState:null,menu:{...window.valleyMenuState,game_bridge},geometry};
      });
      let observation,readTimer;
      try {
        observation=await Promise.race([pending,new Promise((_,reject)=>{
          readTimer=setTimeout(()=>reject(new Error('Canvas geometry/snapshot read exceeded5000ms')),5000);
        })]);
      } finally {clearTimeout(readTimer);}
      validateCanvasGeometry(observation.geometry,canvasBox);
      if(canvasBox===null) {
        canvasBox=observation.geometry.box;
        evidence.canvas_box=canvasBox;evidence.canvas_geometry=observation.geometry;
      }
      evidence.last_menu=observation.menu;
      if(!observation.state) {await persist();withinBudget();return observation;}
      const state=observation.state;
      assert.equal(state.build, manifest.build); assert.equal(state.hud?.schema, manifest.hud_schema);
      assert.deepEqual(state.hud.viewport,PREPARED_VIEWPORT,'Logical viewport differs from exact prepared dimensions');
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
      return observation;
    };
    const snapshot=async()=>{
      const observation=await observe();assert.ok(observation.state,'Game bridge absent before ordinary Start');return observation.state;
    };
    const menuSnapshot=async()=> (await observe()).menu;
    const waitForMenu=async(condition,milliseconds,label)=>{
      const until=Date.now()+milliseconds;
      do {const menu=await menuSnapshot();if(condition(menu))return menu;await delay(160);}while(Date.now()<until);
      throw new Error('Timed out: '+label);
    };
    const tapMenu=async(menu,id)=>{
      const button=menuButton(menu,id,PREPARED_VIEWPORT),r=button.rect;
      withinBudget();const inputStarted=Date.now();
      await page.touchscreen.tap(...mapPoint([r[0]+r[2]/2,r[1]+r[3]/2],PREPARED_VIEWPORT,canvasBox));
      recordInput({kind:'tap',label:id,elapsed_ms:Date.now()-started,duration_ms:Date.now()-inputStarted});
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
    const home=await menuSnapshot();assertMenu(home);
    await checkpoint('ordinary-entry-home',home);
    await page.screenshot({path:`${outputDirectory}/${PREPARED_SCENARIO}-main-menu.png`});
    await tapMenu(home,'StartMatchButton');
    await page.waitForFunction(()=>typeof window.valleySnapshot==='function',null,{timeout:20000});
    const menuHidden=await waitForMenu(m=>!m.visible&&m.match_exists,3000,'Start created one match and hid menu');
    assertMenu(menuHidden,{visible:false,match_exists:true,game_bridge:true});
    const initial = await snapshot();
    assertCamera(initial.hud.camera);
    await page.screenshot({path:`${outputDirectory}/${PREPARED_SCENARIO}-opening-terrain.png`});
    evidence.opening_view={tick:initial.tick,camera:initial.hud.camera,viewport:initial.hud.viewport,
      comparison:'Comparable untouched opening view only. Old vc-cf764648c52f lacks camera telemetry; no exact same-camera/same-tick claim.'};
    await checkpoint('loaded-with-public-hud',initial);
    assert.equal(initial.paused, false);
    const worker = initial.hud.own_targets.find(item => item.kind === 'villager');
    assert.ok(worker, 'No current publicly visible tappable own villager');
    await tapOwn(initial, worker.id);
    const workerSelected = await waitFor(state => state.selected.length === 1 && state.selected[0] === worker.id, 3000, 'worker selected');
    assertPinnedStop(workerSelected);
    await checkpoint('selected-worker-stop-and-build-visible',workerSelected);
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
    assertPinnedStop(stripState);
    await checkpoint('stop-visible-without-scroll',stripState);
    await page.screenshot({path:`${outputDirectory}/portrait-stop-ready.png`});
    await tapButton(stripState, /^停止$/);
    await checkpoint('stop-tapped');
    // The stationary site is the same just-observed public target; selection is
    // confirmed by the subsequent actual HUD assertion, never assumed.
    await tapOwn(stripState, site.id);
    const stopped = await waitFor(state => state.own_pending_commands === 0 && state.hud.selection_detail.includes('無施工村民') && selectedSite(state,site.id), 5000, 'natural no-builder HUD');
    const stable = await waitFor(state => state.tick - stopped.tick >= 20, 6000, 'real simulation second while stopped');
    assertStoppedProgress(stopped, stable, site.id);
    assertUnchangedEconomy(stripState,stopped);
    assertUnchangedEconomy(stopped,stable);
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
    assertCommandToolbar(commandState);
    assertUnchangedEconomy(resumeSelected,commandState);
    await tapOwn(commandState, site.id);
    const submitted = await waitFor(state => state.touch_mode === false, 3000, 'site command submitted');
    await tapOwn(submitted, site.id);
    await checkpoint('resume-command-submitted',submitted);
    const active = await waitFor(state => state.hud.selection_detail.includes('建造中') &&
      selectedSite(state,site.id)?.progress > selectedSite(stable,site.id).progress, 15000, 'natural resumed active construction');
    assertResumedProgress(stable, active, site.id);
    assertUnchangedEconomy(stable,active);
    await checkpoint('resumed-active-progress-increased', active);
    await page.screenshot({path:`${outputDirectory}/portrait-construction-resumed.png`});
    assert.equal(evidence.error_count, 0, 'Browser errors recorded');
    await checkpoint('closing-context');
    await context.close(); context = null;
    assert.equal(evidence.error_count, 0, 'Browser errors during context close');
    assertPublicStreamCompletions(evidence.network.records,origin);
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
