// Inert on import. Bounded military HUD scenario; ordinary touch, read-only bridge.
import assert from 'node:assert/strict';
import {readFile,writeFile,rename} from 'node:fs/promises';
import {createNetworkDiagnostics} from './network_diagnostics.mjs';
import {menuButton,assertMenu,assertCamera,assertPausedMatch,assertFrozenMatch,menuSwipePoints} from './public_observation_assertions.mjs';
import {assertPublicStreamCompletions} from './public_stream_cache_policy.mjs';
export const PREPARED_SCENARIO = 'military390-producer';
export const PREPARED_VIEWPORT = Object.freeze([390, 844]);
export const RESIZED_VIEWPORT = Object.freeze([844, 390]);
export const PREPARED_PROFILE = 'portrait';
export const TOUCH = true;
export const COVERAGE_SCOPE = 'producer-direct';
export const PALETTE_TOUCH_MOVE_STEPS = 2;
export const HELP_SCROLL_GESTURES = 6;
export const HELP_FINAL_PARAGRAPH = '開始戰役後，教學：採集、建造與出兵。';

export function validateManifest(manifest) {
  assert.equal(manifest.reviewed,true,'Menu export pins not reviewed');
  assert.match(manifest.build,/^vc-[0-9a-f]{12}$/);
  assert.match(manifest.source_commit,/^[0-9a-f]{40}$/);
  assert.equal(manifest.profile,PREPARED_PROFILE);
  assert.equal(manifest.scenario,PREPARED_SCENARIO);
  assert.deepEqual(manifest.viewport,PREPARED_VIEWPORT);
  assert.deepEqual(manifest.resized_viewport,RESIZED_VIEWPORT);
  assert.equal(manifest.hud_schema,2);
  assert.ok(manifest.files_sha256 && Object.keys(manifest.files_sha256).length>=3);
  for(const name of ['index.html','index.pck','index.wasm'])assert.match(manifest.files_sha256[name],/^[0-9a-f]{64}$/);
  for(const [name,digest] of Object.entries(manifest.files_sha256)) {
    assert.ok(!name.startsWith('/') && !name.includes('\\') && name.split('/').every(p=>p&&p!=='.'&&p!=='..'));
    assert.match(digest,/^[0-9a-f]{64}$/);
  }
  return manifest;
}
export function mapPoint(point,viewport,box) {
  assert.ok(Array.isArray(point)&&point.length===2&&point.every(Number.isFinite));
  assert.ok(Array.isArray(viewport)&&viewport.length===2&&viewport.every(v=>Number.isFinite(v)&&v>0));
  assert.ok(box&&box.width>0&&box.height>0);
  assert.ok(point[0]>=0&&point[0]<viewport[0]&&point[1]>=0&&point[1]<viewport[1],'Telemetry point outside viewport');
  return [box.x+point[0]*box.width/viewport[0],box.y+point[1]*box.height/viewport[1]];
}
export function validateCanvasGeometry(geometry,viewport,expectedBox=null) {
  assert.ok([PREPARED_VIEWPORT,RESIZED_VIEWPORT].some(v=>JSON.stringify(v)===JSON.stringify(viewport)),'Unapproved viewport');
  assert.ok(geometry,'Canvas DOM geometry missing');
  const {box,display,visibility,opacity}=geometry;
  assert.deepEqual(geometry.viewport,viewport,'CSS viewport differs from approved context');
  assert.ok(box&&['x','y','width','height'].every(k=>Number.isFinite(box[k])));
  assert.ok(box.width>0&&box.height>0&&box.x>=0&&box.y>=0&&box.x+box.width<=viewport[0]+0.5&&box.y+box.height<=viewport[1]+0.5,'Canvas not fully onscreen');
  assert.ok(display!=='none'&&visibility==='visible'&&Number.isFinite(opacity)&&opacity>0,'Canvas not visible');
  if(expectedBox)assert.deepEqual(box,expectedBox,'Unexpected canvas change; stale mapping forbidden');
  return box;
}
export function assertMenuControls(menu,viewport,expectedIds) {
  assert.deepEqual(menu.buttons.map(b=>b.id),expectedIds,'Wrong public menu button order/count');
  const rects=expectedIds.map(id=>menuButton(menu,id,viewport).rect);
  for(const r of rects)assert.ok(r[3]>=54,'54px menu target clipped');
  for(let i=1;i<rects.length;i++)assert.ok(rects[i][1]>=rects[i-1][1]+rects[i-1][3]+9.5,'Menu targets overlap or gap collapsed');
}
// Only geometric settling may return false. Schema, IDs and finite values are
// semantic contracts and remain immediately fatal; no assertion is caught.
export function menuGeometryIssue(menu,viewport,expectedIds) {
  assert.equal(menu.visible,true,'Menu must be visible before geometry readiness');
  assert.ok(Array.isArray(menu.buttons),'Public menu buttons missing');
  assert.deepEqual(menu.buttons.map(b=>b.id),expectedIds,'Wrong public menu button order/count');
  const rects=menu.buttons.map(b=>b.rect);
  for(const r of rects)assert.ok(Array.isArray(r)&&r.length===4&&r.every(Number.isFinite),'Nonfinite or malformed menu rect');
  if(rects.some(r=>r[0]<0||r[1]<0||r[2]<48||r[3]<54||r[0]+r[2]>viewport[0]||r[1]+r[3]>viewport[1]))return 'Menu control clipped/offscreen or below full target size';
  if(!rects.every((r,i)=>i===0||r[1]>=rects[i-1][1]+rects[i-1][3]+9.5))return 'Menu targets overlap or gap collapsed';
  return null;
}
export function menuGeometryReady(menu,viewport,expectedIds) {
  return menuGeometryIssue(menu,viewport,expectedIds)===null;
}
export async function waitForMenuTransition(read,ready,label,{now=Date.now,sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms))}={}) {
  // One shared original 3s window, including every actual snapshot read and
  // settling poll. Each read is additionally bounded by the existing 5s cap.
  const until=now()+3000;
  while(now()<until) {
    const observation=await read(until);
    if(now()>=until)break;
    if(ready(observation))return observation;
    await sleep(Math.min(120,until-now()));
  }
  throw new Error('Timed out: '+label+' (complete menu geometry within original 3000ms transition)');
}
export function shortcutMenuReady(state) {
  // First open may show the inner Close control. Reopened scrolled menus keep
  // only the source-defined outer Collapse toggle and actionable Main Menu.
  // Collapse alone is not accepted (the tutorial has the same label).
  return !!hudButton(state,/^關閉$/)||!!(hudButton(state,/^收起$/)&&hudButton(state,/^主選單$/));
}

// Exact additive artist schema, emitted only for a visible Help page. Values
// and bounds are observations of ordinary UI controls, never scroll setters.
export function assertHelpScroll(menu,viewport,requireFinal=false) {
  if(!(menu.visible&&menu.page==='help')) {
    assert.equal(Object.hasOwn(menu,'help_scroll'),false,'Help telemetry leaked outside visible Help');
    return null;
  }
  const h=menu.help_scroll;
  assert.ok(h&&typeof h==='object'&&!Array.isArray(h),'Visible Help scroll telemetry missing');
  assert.deepEqual(Object.keys(h).sort(),['final_rect','final_text','final_visible_rect','maximum','page','value'],'Unexpected Help scroll schema');
  for(const key of ['value','maximum','page'])assert.ok(Number.isFinite(h[key])&&h[key]>=0,'Invalid Help scroll '+key);
  assert.ok(h.value<=Math.max(0,h.maximum-h.page),'Help scroll value outside actual range');
  assert.equal(h.final_text,HELP_FINAL_PARAGRAPH,'Help final paragraph changed');
  for(const key of ['final_rect','final_visible_rect']) {
    const r=h[key];assert.ok(Array.isArray(r)&&r.length===4&&r.every(Number.isFinite)&&r[2]>=0&&r[3]>=0,'Invalid Help '+key);
  }
  if(requireFinal) {
    assert.ok(h.page>0&&h.final_rect[2]>0&&h.final_rect[3]>0,'Final Help paragraph has no positive reading area');
    assert.deepEqual(h.final_visible_rect,h.final_rect,'Final Help paragraph is not completely visible after six gestures');
    const [x,y,w,height]=h.final_rect;
    assert.ok(x>=0&&y>=0&&x+w<=viewport[0]&&y+height<=viewport[1],'Final Help paragraph outside viewport');
    const back=menuButton(menu,'BackButton',viewport).rect;
    assert.ok(back[3]>=54,'Back clipped after Help scrolling');
    assert.ok(y+height<=back[1],'Final Help paragraph overlaps Back');
  }
  return h;
}

export function helpSwipePoints(menu,viewport) {
  const r=menuButton(menu,'BackButton',viewport).rect;
  // Source-derived inner panel top (height min(640,h-48), 20px padding),
  // bounded by actual public Back geometry. This is input geometry only, not
  // an assertion that prose scrolled or its last paragraph became visible.
  const top=(viewport[1]-Math.min(640,viewport[1]-48))/2+32;
  const bottom=r[1]-24;
  assert.ok(bottom-top>=70,'No safe prose-only swipe span');
  return {start:[r[0]+r[2]/2,bottom],end:[r[0]+r[2]/2,top]};
}
export function hudButton(state,matcher) {
  assert.equal(state.hud?.schema,2);
  const matches=state.hud.buttons.filter(b=>!b.disabled&&matcher.test(b.text)&&Array.isArray(b.rect)&&b.rect.length===4&&b.rect.every(Number.isFinite)&&b.rect[2]>=48&&b.rect[3]>=46);
  assert.ok(matches.length<=1,'Ambiguous public HUD button');
  return matches[0]??null;
}
export function assertResumedMatch(paused,resumed) {
  assert.equal(paused.paused,true);assert.equal(resumed.paused,false);assert.equal(resumed.game_over,false);
  assert.ok(Number.isInteger(resumed.tick)&&resumed.tick>=paused.tick);
  for(const key of ['selected','bank_milli','age','economy_scale','population','capacity','delivered','built','trained','own_pending_commands','touch_mode','build_mode'])assert.deepEqual(resumed[key],paused[key],'Resume changed '+key);
  assertCamera(resumed.hud.camera);assert.deepEqual(resumed.hud.camera,paused.hud.camera);
}

export function assertFreshMatchDefault(state) {
  assert.deepEqual(state.bank_milli,{food:150000,wood:200000,stone:100000,iron:0},'Fresh match must expose exact four-resource opening bank');
  assert.equal(state.economy_scale,1000);assert.equal(state.age,1,'Fresh match must start in settlement age');
  assert.equal(state.paused,false);assert.equal(state.game_over,false);
  assert.equal(state.selected.length,1,'Fresh match must select one owned town center');
  assert.deepEqual(state.hud.selected_own,[{built:true,category:'building',id:state.selected[0],kind:'town_center',progress:1}],
    'Fresh default selection is not the owned completed town center');
  assertCamera(state.hud.camera);
}
export function assertConfirmedNewMatch(fresh,previous,restarted) {
  assertFreshMatchDefault(fresh);assertFreshMatchDefault(restarted);
  assert.notDeepEqual(previous.selected,fresh.selected,'Distinct retained worker witness missing');
  assert.notDeepEqual(restarted.selected,previous.selected,'New match retained old worker selection');
  assert.deepEqual(restarted.selected,fresh.selected,'New match default differs from ordinary Start');
  assert.ok(Number.isInteger(restarted.tick)&&restarted.tick>=0&&restarted.tick<previous.tick,'New match did not reset observed tick');
  for(const key of ['bank_milli','age','economy_scale','population','capacity','delivered','built','trained','own_pending_commands','touch_mode','build_mode'])
    assert.deepEqual(restarted[key],fresh[key],'New match did not restore startup '+key);
  assert.deepEqual(restarted.hud.camera,fresh.hud.camera,'New match did not restore startup camera');
}

export const BUILDINGS=Object.freeze(['民居','兵營','箭場','倉庫','農田','守望塔','馬廄','工坊']);
export function assertHudRects(state,viewport){
  assert.equal(state.hud.schema,2);assert.deepEqual(state.hud.viewport,viewport);
  const rects=state.hud.buttons.map(b=>b.rect);
  for(const r of rects){
    assert.ok(Array.isArray(r)&&r.length===4&&r.every(Number.isFinite));
    assert.ok(r[0]>=0&&r[1]>=0&&r[2]>0&&r[3]>0&&r[0]+r[2]<=viewport[0]+0.5&&r[1]+r[3]<=viewport[1]+0.5,'Visible control rect outside canvas');
  }
  for(let i=0;i<rects.length;i++)for(let j=i+1;j<rects.length;j++){
    const a=rects[i],b=rects[j];
    assert.ok(Math.min(a[0]+a[2],b[0]+b[2])-Math.max(a[0],b[0])<=0.5||Math.min(a[1]+a[3],b[1]+b[3])-Math.max(a[1],b[1])<=0.5,'Visible control rect overlap');
  }
  // QA reports clipped intersections, not original label bounds. Geometry alone
  // cannot prove absence of clipped glyphs/covered labels: require PNG review.
  assert.ok(!state.hud.buttons.some(b=>['關閉','繼續','投降','主選單'].includes(b.text)),'Unexpected overlay controls');
}
export function stripSwipe(state,back=false){
  const r=state.hud.action_scroll.rect;
  assert.ok(r.length===4&&r.every(Number.isFinite)&&r[2]>=216&&r[3]>=46,'No safe horizontal strip');
  const distance=Math.min(216,r[2]-16),right=[r[0]+r[2]-8,r[1]+r[3]/2],left=[r[0]+r[2]-8-distance,r[1]+r[3]/2];
  return back?{start:left,end:right}:{start:right,end:left};
}

export function assertPalettePair(state,pair){
  assert.ok(Number.isInteger(pair)&&pair>=0&&pair<4);
  const strip=state.hud.action_scroll.rect;
  assert.equal(state.hud.action_scroll.scroll_horizontal,pair*216,'Ordinary drag ended at unexpected palette offset');
  const entries=[];
  for(let index=pair*2;index<pair*2+2;index++){
    const name=BUILDINGS[index];
    const matches=state.hud.buttons.filter(b=>b.in_action_scroll&&b.text.split('\n')[0]===name);
    assert.equal(matches.length,1,'Missing/ambiguous palette entry '+name);
    const button=matches[0],r=button.rect;
    assert.equal(r[0],strip[0]+(index%2)*108,'Entry left edge clipped or displaced');
    assert.equal(r[1],strip[1]);assert.equal(r[2],100,'Full actual100px button required');
    assert.ok(r[3]>=70,'Full locked-row text height required');
    assert.ok(r[0]+r[2]<strip[0]+strip[2],'Entry right edge clipped');
    const locked=['馬廄','工坊'].includes(name);
    assert.equal(button.disabled,locked,'Incorrect age lock');
    assert.equal(button.text.includes('需城防時代'),locked,'Missing/incorrect visible age-lock text');
    entries.push([name,button]);
  }
  return entries;
}

export async function runQA(browser,outputDirectory,origin,profile) {
  assert.equal(profile,PREPARED_PROFILE,'Wrong fixed menu profile');
  assert.match(origin,/^http:\/\/127\.0\.0\.1:\d+$/);
  const manifest=validateManifest(JSON.parse(await readFile(new URL('./scenario-manifest.json',import.meta.url),'utf8')));
  const started=Date.now();
  const evidence={build:manifest.build,source_commit:manifest.source_commit,files_sha256:manifest.files_sha256,
    profile,scenario:PREPARED_SCENARIO,viewport:[...PREPARED_VIEWPORT],resized_viewport:[...RESIZED_VIEWPORT],
    basicSmokePassed:false,releaseQAPassed:false,visualAcceptancePassed:false,phase:'starting',checkpoints:[],
    errors:[],error_count:0,error_limit: 64,screenshots:[],input_timings:[],read_timings:[],pending_menu_geometry:[],
    input:TOUCH?'Chrome emulated touchscreen, including real CDP touch streams; not a physical phone':'Chrome desktop mouse and keyboard',
    observation:'Only valleyMenuSnapshot/valleySnapshot and canvas DOM geometry; no setters or game authority',
    required_visual_review:{status:'pending-human-pixel-review',scope:COVERAGE_SCOPE,checks:[
      'Genuine390x844 top HUD food/wood/stone/iron and AgeI labels readable',
      'All captures have no overlay or unreadable clipped/overlapping controls',
      COVERAGE_SCOPE==='producer-direct'?'Actual paid villager queue and AgeII action cost readable; first worker tap and direct commands in checkpoints':
        COVERAGE_SCOPE==='palette-first'?'Four initial building entries readable in two screenshots':'Four final building entries readable in two screenshots including disabled stable/workshop age locks']},
    not_run:['physical iOS/Android','AgeII completion','military combat','automated pixel acceptance',
      'Other split scopes: each requires its own successful fresh hosted run and PNG review']};
  const addError=error=>{evidence.error_count++;if(evidence.errors.length<evidence.error_limit)evidence.errors.push(error);};
  const network=createNetworkDiagnostics(()=>evidence.phase,addError);evidence.network=network.data;
  const persist=async()=>{await writeFile(`${outputDirectory}/browser-evidence.json.tmp`,JSON.stringify(evidence,null,2));await rename(`${outputDirectory}/browser-evidence.json.tmp`,`${outputDirectory}/browser-evidence.json`);};
  const checkpoint=async(phase,state=null)=>{evidence.phase=phase;evidence.checkpoints.push({phase,elapsed_ms:Date.now()-started,state});await persist();};
  const withinBudget=()=>assert.ok(Date.now()-started<70000,'Scenario 70-second inner budget exhausted; external guard unchanged');
  const delay=milliseconds=>new Promise(resolve=>setTimeout(resolve,milliseconds));
  let context,page,session,canvasBox=null,viewport=[...PREPARED_VIEWPORT];
  try {
    await checkpoint('starting');
    context=await browser.newContext({viewport:{width:viewport[0],height:viewport[1]},deviceScaleFactor:1,hasTouch:TOUCH,serviceWorkers:'block'});
    page=await context.newPage();page.setDefaultTimeout(5000);
    page.on('pageerror',error=>addError({kind:'pageerror',text:String(error).slice(0,2000)}));
    page.on('console',message=>{if(message.type()==='error')addError({kind:'console',text:message.text().slice(0,2000)});});
    context.on('request',network.request);context.on('response',network.response);
    context.on('requestfinished',network.finished);context.on('requestfailed',network.failed);
    await page.route('**/*',route=>new URL(route.request().url()).origin === origin?route.continue():route.abort());
    await page.goto(`${origin}/index.html?qa`,{waitUntil:'load',timeout:25000});
    await page.waitForFunction(()=>typeof window.valleyMenuSnapshot==='function',null,{timeout:20000});
    const recordInput=record=>{evidence.last_input=record;if(evidence.input_timings.length<96)evidence.input_timings.push(record);};
    const observe=async(readDeadline=null)=>{
      withinBudget();const readStarted=Date.now();
      const readBudget=readDeadline===null?5000:Math.min(5000,readDeadline-readStarted);
      assert.ok(readBudget>0,'Original menu transition deadline exhausted before snapshot');
      const pending=page.evaluate(()=>{
        window.valleyMenuSnapshot();
        const game_bridge=typeof window.valleySnapshot==='function';
        if(game_bridge)window.valleySnapshot();
        const canvas=document.querySelector('canvas');let geometry=null;
        if(canvas){const rect=canvas.getBoundingClientRect(),style=getComputedStyle(canvas);geometry={box:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},viewport:[innerWidth,innerHeight],display:style.display,visibility:style.visibility,opacity:Number(style.opacity)};}
        return {state:game_bridge?window.valleyState:null,menu:{...window.valleyMenuState,game_bridge},geometry};
      });
      let observation,readTimer;
      try {observation=await Promise.race([pending,new Promise((_,reject)=>{readTimer=setTimeout(()=>reject(new Error(readBudget===5000?'Canvas geometry/snapshot read exceeded5000ms':'Canvas geometry/snapshot read exceeded original menu transition deadline')),readBudget);})]);}
      finally {clearTimeout(readTimer);}
      canvasBox=validateCanvasGeometry(observation.geometry,viewport,canvasBox);
      assertHelpScroll(observation.menu,viewport);
      if(observation.state){assert.equal(observation.state.build,manifest.build);assert.equal(observation.state.hud?.schema,2);assert.deepEqual(observation.state.hud.viewport,viewport);}
      const duration=Date.now()-readStarted;
      if(evidence.read_timings.length<96)evidence.read_timings.push({elapsed_ms:Date.now()-started,duration_ms:duration,phase:evidence.phase});
      evidence.last_observation=observation;await persist();withinBudget();return observation;
    };
    const waitFor=async(predicate,label,milliseconds=3000)=>{
      const until=Date.now()+milliseconds;
      do {const o=await observe();if(predicate(o))return o;await delay(120);}while(Date.now()<until);
      throw new Error('Timed out: '+label);
    };
    const waitMenu=async({page:targetPage,match=false,fromPage='home',frozen=null,allowHidden=false},label)=>{
      const ids=targetPage==='help'?['BackButton']:targetPage==='confirm'?['ConfirmNewMatchButton','CancelNewMatchButton']:
        match?['ResumeMatchButton','NewMatchButton','HelpButton']:['StartMatchButton','HelpButton'];
      return waitForMenuTransition(observe,o=>{
        assert.ok([fromPage,targetPage].includes(o.menu.page),'Unexpected page during menu transition');
        assert.equal(o.menu.match_exists,match,'Match lifecycle changed during menu transition');
        assert.equal(o.menu.game_bridge,match,'Bridge lifecycle changed during menu transition');
        if(frozen)assertFrozenMatch(frozen,o.state);
        if(!allowHidden)assert.equal(o.menu.visible,true,'Menu disappeared during page transition');
        if(o.menu.page!==targetPage||!o.menu.visible)return false;
        assertMenu(o.menu,{page:targetPage,match_exists:match,game_bridge:match});
        if(match){assert.ok(o.state,'Retained match snapshot missing');assert.equal(o.state.paused,true);assert.equal(o.state.game_over,false);}
        const reason=menuGeometryIssue(o.menu,viewport,ids);
        if(reason){
          evidence.last_menu_geometry_issue=reason;
          if(evidence.pending_menu_geometry.length<32)evidence.pending_menu_geometry.push({elapsed_ms:Date.now()-started,page:targetPage,viewport:[...viewport],reason,buttons:o.menu.buttons});
        }
        return reason===null;
      },label);
    };
    const shot=async(label)=>{
      withinBudget();const name=`${PREPARED_SCENARIO}-${label}.png`;
      await page.screenshot({path:`${outputDirectory}/${name}`,timeout:5000});
      evidence.screenshots.push({name,phase:evidence.phase,viewport:[...viewport],genuine_browser_capture:true});await persist();
    };
    const inputPoint=p=>mapPoint(p,viewport,canvasBox);
    const activate=async(point,label)=>{
      withinBudget();const inputStarted=Date.now(),xy=inputPoint(point);
      if(TOUCH)await page.touchscreen.tap(...xy);else await page.mouse.click(...xy);
      recordInput({kind:TOUCH?'touch-tap':'mouse-click',label,elapsed_ms:Date.now()-started,duration_ms:Date.now()-inputStarted});
    };
    const center=r=>[r[0]+r[2]/2,r[1]+r[3]/2];
    const activateMenu=async(menu,id)=>activate(center(menuButton(menu,id,viewport).rect),id);
    const activateHud=async(state,pattern)=>{const b=hudButton(state,pattern);assert.ok(b,'Missing actionable HUD control '+pattern);await activate(center(b.rect),b.text);};
    const touch=async(type,points)=>{
      withinBudget();if(!session)session=await context.newCDPSession(page);
      await session.send('Input.dispatchTouchEvent',{type,touchPoints:points.map((p,i)=>{const [x,y]=inputPoint(p);return {x,y,id:i};})});
    };
    const gesture=async(points,label,steps=6)=>{
      assert.ok(steps===6||steps===PALETTE_TOUCH_MOVE_STEPS,'Only reviewed ordinary touch sample counts');
      withinBudget();const inputStarted=Date.now();
      if(TOUCH){
        await touch('touchStart',[points.start]);
        for(let step=1;step<=steps;step++){await delay(20);await touch('touchMove',[[points.start[0]+(points.end[0]-points.start[0])*step/steps,points.start[1]+(points.end[1]-points.start[1])*step/steps]]);}
        await touch('touchEnd',[]);
      }else{await page.mouse.move(...inputPoint(points.start));await page.mouse.wheel(0,Math.max(200,points.start[1]-points.end[1]));}
      recordInput({kind:TOUCH?'touch-swipe':'mouse-wheel',label,touch_move_steps:steps,elapsed_ms:Date.now()-started,duration_ms:Date.now()-inputStarted});
      await delay(100);
    };
    const resize=async(next,label)=>{
      assert.ok([PREPARED_VIEWPORT,RESIZED_VIEWPORT].some(v=>JSON.stringify(v)===JSON.stringify(next)));
      withinBudget();await page.setViewportSize({width:next[0],height:next[1]});
      viewport=[...next];canvasBox=null; // Only explicit approved resize invalidates input mapping.
      await delay(180);const o=await observe();await checkpoint(label,o);return o;
    };
    const requireHome=(o,match=false)=>{
      assertMenu(o.menu,{match_exists:match,game_bridge:match});
      assertMenuControls(o.menu,viewport,match?['ResumeMatchButton','NewMatchButton','HelpButton']:['StartMatchButton','HelpButton']);
    };
    let current=await observe();requireHome(current);
    await activateMenu(current.menu,'StartMatchButton');
    await page.waitForFunction(()=>typeof window.valleySnapshot==='function',null,{timeout:20000});
    current=await waitFor(o=>!o.menu.visible&&o.state&&!o.state.paused,'ordinary Start created active match');
    assertFreshMatchDefault(current.state);
    await checkpoint('ordinary-start-default-observed',current);
    const stableHud=o=>{
      assert.equal(o.menu.visible,false);assert.equal(o.state.paused,false);assert.equal(o.state.game_over,false);
      assert.equal(o.state.age,1);assert.equal(o.state.build_mode,'');assert.equal(o.state.touch_mode,false);
      assertHudRects(o.state,viewport);
    };
    const dragStrip=async(label,steps=6)=>{
      const before=current.state.hud.action_scroll.scroll_horizontal;
      await gesture(stripSwipe(current.state),label,steps);
      current=await observe();stableHud(current);
      assert.ok(current.state.hud.action_scroll.scroll_horizontal>before,'Real horizontal drag did not advance strip');
    };
    // One actual ordinary train tap. No queue API, forced time, or cancellation.
    stableHud(current);
    const beforeTrain=structuredClone(current.state);
    await activateHud(current.state,/^訓練村民\n/);
    current=await waitFor(o=>o.state.population===beforeTrain.population+1&&o.state.bank_milli.food===beforeTrain.bank_milli.food-50000,'ordinary enqueue debit and reservation');
    assert.equal(current.state.trained,beforeTrain.trained,'Queue must still be pending, no production milestone wait');
    for(const key of ['wood','stone','iron'])assert.equal(current.state.bank_milli[key],beforeTrain.bank_milli[key]);
    stableHud(current);await checkpoint('villager-queued-real-debit-reservation',current);
    await dragStrip('producer-strip-1');
    const age=hudButton(current.state,/^城防時代\n/);assert.ok(age&&age.rect[2]>=160,'Actual age action not fully exposed');
    assert.equal(age.text,'城防時代\n食 350 木 150 鐵 50');
    assert.equal(current.state.age,1);assert.ok(current.state.bank_milli.food<350000&&current.state.bank_milli.iron<50000);
    evidence.age_action={text:age.text,disabled:age.disabled,affordable:false,clicked:false};
    await checkpoint('producer-queue-and-age-action-pixels-required',current);await shot('producer-queue-age');
    const worker=current.state.hud.own_targets.find(t=>t.kind==='villager');assert.ok(worker,'Visible ordinary villager missing');
    await activate(worker.screen,'select-natural-worker');
    current=await waitFor(o=>o.state.selected.length===1&&o.state.selected[0]===worker.id,'worker selected');
    stableHud(current);
    assert.ok(current.state.hud.buttons.some(b=>BUILDINGS.includes(b.text.split('\n')[0])),'Worker palette not immediately available');
    await checkpoint('worker-palette-immediately-available',current);
    // Fixed public ground probes are not a path or placement search. Pick one
    // geometrically separated from the currently visible selected worker.
    let witness=current.state.hud.own_targets.find(t=>t.id===worker.id);assert.ok(witness);
    const ground=current.state.hud.ground_points.find(p=>Math.hypot(p[0]-witness.screen[0],p[1]-witness.screen[1])>35);
    assert.ok(ground,'No separated public empty-ground probe');
    const camera=structuredClone(current.state.hud.camera);
    await activate(ground,'direct-ground-order-no-command-overlay');
    current=await waitFor(o=>/^生命 \d+ \/ \d+   ·   移動(?: |$)/u.test(o.state.hud.selection_detail),'applied direct movement status');
    stableHud(current);assert.deepEqual(current.state.selected,[worker.id]);assert.deepEqual(current.state.hud.camera,camera);
    await checkpoint('worker-direct-ground-move',current);
    const resource=current.state.hud.context_targets.find(t=>t.category==='resource');
    assert.ok(resource,'No public visible tappable resource');
    await activate(resource.screen,'direct-resource-order-no-command-overlay');
    current=await waitFor(o=>/^生命 \d+ \/ \d+   ·   採集(?: |$)/u.test(o.state.hud.selection_detail),'applied direct resource gathering status');
    stableHud(current);assert.deepEqual(current.state.selected,[worker.id]);assert.deepEqual(current.state.hud.camera,camera);
    evidence.resource_target={id:resource.id,kind:resource.kind,screen:resource.screen};
    await checkpoint('worker-direct-resource-target',current);
    evidence.coverage_scope=COVERAGE_SCOPE;
    assert.equal(evidence.screenshots.length,1,'Exact scoped genuine capture count required');
    assert.equal(evidence.error_count,0,'Browser errors recorded');
    if(session){await session.detach();session=null;}
    await checkpoint('closing-context');await context.close(); context = null;
    assert.equal(evidence.error_count,0,'Browser errors during context close');assertPublicStreamCompletions(evidence.network.records,origin);
    evidence.basicSmokePassed=true;await checkpoint('completed');
  }catch(error){
    evidence.basicSmokePassed=false;evidence.failure=String(error);evidence.failedDuringPhase=evidence.phase;evidence.phase='failed';await persist();
    if(page&&!page.isClosed()&&Date.now()-started<68000){try{await page.screenshot({path:`${outputDirectory}/${PREPARED_SCENARIO}-failure.png`,timeout:1500});evidence.failure_screenshot='written';}catch(captureError){evidence.failure_screenshot=String(captureError).slice(0,500);}}
    else evidence.failure_screenshot='skipped: no remaining inner budget or page closed';
    throw error;
  }finally{
    if(session){try{await session.detach();}catch(error){addError({kind:'cdp-detach',text:String(error).slice(0,1000)});}}
    if(context){try{await context.close();}catch(error){addError({kind:'context-close',text:String(error).slice(0,1000)});}}
    if(evidence.error_count)evidence.basicSmokePassed=false;await persist();
  }
  return evidence;
}
