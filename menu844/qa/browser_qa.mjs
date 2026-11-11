// Inert on import. Exact fixed menu scenario, ordinary input, read-only bridge.
import assert from 'node:assert/strict';
import {readFile,writeFile,rename} from 'node:fs/promises';
import {createNetworkDiagnostics} from './network_diagnostics.mjs';
import {menuButton,assertMenu,assertCamera,assertPausedMatch,assertFrozenMatch,menuSwipePoints} from './public_observation_assertions.mjs';
import {assertPublicStreamCompletions} from './public_stream_cache_policy.mjs';
export const PREPARED_SCENARIO = 'menu844';
export const PREPARED_VIEWPORT = Object.freeze([844, 390]);
export const RESIZED_VIEWPORT = Object.freeze([390, 844]);
export const PREPARED_PROFILE = 'portrait';
export const TOUCH = true;
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
    required_visual_review:{status:'pending-human-pixel-review',help_final_paragraph:HELP_FINAL_PARAGRAPH,
      checks:['all required genuine PNGs','illustration crop and title hierarchy','glyphs, contrast, visible focus','no clipping or micro-scrollbars','Help final paragraph visible after bounded scrolling and resize','new-match destructive/keep hierarchy']},
    not_run:['physical iOS Safari/Android Chrome','OS background interruption','audible audio','combat or terminal victory/defeat navigation','complete command ledger or hidden instance identity','automated aesthetic/pixel acceptance: genuine PNG review still required']};
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
    const gesture=async(points,label)=>{
      withinBudget();const inputStarted=Date.now();
      if(TOUCH){
        await touch('touchStart',[points.start]);
        for(let step=1;step<=6;step++){await delay(20);await touch('touchMove',[[points.start[0]+(points.end[0]-points.start[0])*step/6,points.start[1]+(points.end[1]-points.start[1])*step/6]]);}
        await touch('touchEnd',[]);
      }else{await page.mouse.move(...inputPoint(points.start));await page.mouse.wheel(0,Math.max(200,points.start[1]-points.end[1]));}
      recordInput({kind:TOUCH?'touch-swipe':'mouse-wheel',label,elapsed_ms:Date.now()-started,duration_ms:Date.now()-inputStarted});
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
    await checkpoint('fresh-home',current);await shot('home');
    if(!TOUCH){await page.keyboard.press('Tab');await checkpoint('desktop-keyboard-focus');await shot('keyboard-focus');}
    // Interrupted-pointer probes do not invoke handlers/dispatchEvent/game APIs.
    // Touch release is genuinely canceled, dragged or multi-touch interrupted.
    const start=center(menuButton(current.menu,'StartMatchButton',viewport).rect);
    if(TOUCH){
      await touch('touchStart',[start]);await touch('touchCancel',[]);await delay(120);
      current=await observe();requireHome(current);await checkpoint('touchcancel-did-not-start',current);
      await touch('touchStart',[start]);await touch('touchMove',[[start[0]+24,start[1]]]);await touch('touchEnd',[]);await delay(120);
      current=await observe();requireHome(current);await checkpoint('drag-did-not-start',current);
      const help=center(menuButton(current.menu,'HelpButton',viewport).rect);
      await touch('touchStart',[start]);await touch('touchStart',[start,help]);await touch('touchEnd',[]);await delay(120);
      current=await observe();requireHome(current);await checkpoint('multitouch-did-not-start',current);
    }else{
      await page.mouse.move(...inputPoint(start));await page.mouse.down();await page.mouse.move(...inputPoint([2,2]));await page.mouse.up();
      current=await observe();requireHome(current);await checkpoint('mouse-drag-out-did-not-start',current);
    }
    await activateMenu(current.menu,'HelpButton');
    current=await waitMenu({page:'help'},'Help opened');assertMenu(current.menu,{page:'help'});
    assertMenuControls(current.menu,viewport,['BackButton']);await checkpoint('help-open',current);await shot('help-before-scroll');
    const scrollHelp=async()=>{
      for(let i=0;i<HELP_SCROLL_GESTURES;i++){
        await gesture(helpSwipePoints(current.menu,viewport),'help-scroll-'+(i+1));
        current=await observe();assertMenu(current.menu,{page:'help'});assertMenuControls(current.menu,viewport,['BackButton']);
      }
    };
    await scrollHelp();assertHelpScroll(current.menu,viewport,true);await checkpoint('help-after-bounded-scroll-pixels-required',current);await shot('help-after-scroll');
    current=await resize(RESIZED_VIEWPORT,'help-scrolled-resized');assertMenu(current.menu,{page:'help'});assertMenuControls(current.menu,viewport,['BackButton']);await shot('help-resized-before-extra-scroll');
    await scrollHelp();assertHelpScroll(current.menu,viewport,true);await checkpoint('help-resized-after-bounded-scroll-pixels-required',current);await shot('help-resized-after-scroll');
    current=await resize(PREPARED_VIEWPORT,'help-scrolled-restored');assertMenuControls(current.menu,viewport,['BackButton']);await shot('help-restored');
    await activateMenu(current.menu,'BackButton');current=await waitMenu({page:'home',fromPage:'help'},'Back actionable after scrolling and resize');requireHome(current);
    await checkpoint('help-back-actionable',current);
    await activateMenu(current.menu,'StartMatchButton');
    await page.waitForFunction(()=>typeof window.valleySnapshot==='function',null,{timeout:20000});
    current=await waitFor(o=>!o.menu.visible&&o.state&&!o.state.paused,'ordinary Start created active match');
    assertMenu(current.menu,{visible:false,match_exists:true,game_bridge:true});assertCamera(current.state.hud.camera);
    const freshStart=structuredClone(current.state);assertFreshMatchDefault(freshStart);
    await checkpoint('ordinary-start-default-observed',current);
    const worker=current.state.hud.own_targets.find(t=>t.kind==='villager');assert.ok(worker,'Natural visible villager absent');
    await activate(worker.screen,'select-natural-worker');
    current=await waitFor(o=>o.state.selected.length===1&&o.state.selected[0]===worker.id&&o.state.tick>=40,'distinct retained selection and natural elapsed ticks',5000);
    const before=current.state;await checkpoint('live-match-before-pause',current);
    const openMainMenu=async(o)=>{
      await activateHud(o.state,/^選單$/);
      o=await waitFor(x=>shortcutMenuReady(x.state),'shortcut menu opened');
      for(let i=0;i<2&&!hudButton(o.state,/^主選單$/);i++){
        await gesture(menuSwipePoints(o.state),'shortcut-menu-scroll-'+(i+1));
        o=await observe();
      }
      assert.ok(hudButton(o.state,/^主選單$/),'Main menu not exposed by two bounded shortcut gestures');
      await activateHud(o.state,/^主選單$/);
      o=await waitMenu({page:'home',match:true,allowHidden:true},'paused home opened');requireHome(o,true);return o;
    };
    current=await openMainMenu(current);const paused=current.state;assertPausedMatch(before,paused);
    await checkpoint('paused-three-button-home',current);await shot('paused-home');
    // Resize while a real Resume touch is held. Release cannot resume the match.
    if(TOUCH)await touch('touchStart',[center(menuButton(current.menu,'ResumeMatchButton',viewport).rect)]);
    current=await resize(RESIZED_VIEWPORT,'paused-home-resized');requireHome(current,true);assertFrozenMatch(paused,current.state);await shot('paused-home-resized');
    if(TOUCH){await touch('touchEnd',[]);await delay(120);current=await observe();requireHome(current,true);assertFrozenMatch(paused,current.state);await checkpoint('resize-canceled-held-resume',current);}
    current=await resize(PREPARED_VIEWPORT,'paused-home-restored');requireHome(current,true);assertFrozenMatch(paused,current.state);await shot('paused-home-restored');
    await activateMenu(current.menu,'NewMatchButton');current=await waitMenu({page:'confirm',match:true,frozen:paused},'new match confirmation visible');
    assertMenu(current.menu,{page:'confirm',match_exists:true,game_bridge:true});assertMenuControls(current.menu,viewport,['ConfirmNewMatchButton','CancelNewMatchButton']);assertFrozenMatch(paused,current.state);
    await checkpoint('new-match-confirmation',current);await shot('new-match-confirmation');
    await activateMenu(current.menu,'CancelNewMatchButton');current=await waitMenu({page:'home',match:true,fromPage:'confirm',frozen:paused},'Cancel keeps current match');requireHome(current,true);assertFrozenMatch(paused,current.state);
    await checkpoint('new-match-cancel-preserved-match',current);await shot('new-match-canceled');
    await activateMenu(current.menu,'ResumeMatchButton');current=await waitFor(o=>!o.menu.visible&&!o.state.paused&&o.state.tick>=paused.tick+20,'resume advances natural ticks',5000);
    assertMenu(current.menu,{visible:false,match_exists:true,game_bridge:true});assertResumedMatch(paused,current.state);
    await checkpoint('resumed-same-observed-match',current);
    current=await openMainMenu(current);const beforeRestart=current.state;
    await activateMenu(current.menu,'NewMatchButton');current=await waitMenu({page:'confirm',match:true,frozen:beforeRestart},'second explicit new match confirmation');assertFrozenMatch(beforeRestart,current.state);
    await activateMenu(current.menu,'ConfirmNewMatchButton');current=await waitFor(o=>!o.menu.visible&&o.state&&!o.state.paused&&o.state.tick<beforeRestart.tick,'confirmed new match reset observed tick',5000);
    assertConfirmedNewMatch(freshStart,beforeRestart,current.state);
    await checkpoint('confirmed-new-match-observed-reset',{fresh_start:freshStart,before:beforeRestart,after:current});
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
