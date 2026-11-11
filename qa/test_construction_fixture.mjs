// Inert synthetic metadata and fake-browser tests. No runtime or gameplay evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,writeFile,copyFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {validateManifest,mapPoint,validateCanvasGeometry,buttonByText,selectedSite,assertStoppedProgress,
  assertResumedProgress,assertPinnedStop,assertCommandToolbar,assertUnchangedEconomy,assertNoUnintendedOrder,
  PREPARED_SCENARIO,PREPARED_VIEWPORT,runQA} from './browser_qa.mjs';

const manifest = {reviewed:true,build:'vc-123456789abc',source_commit:'a'.repeat(40),profile:'portrait',hud_schema:2,
  scenario:PREPARED_SCENARIO,viewport:[...PREPARED_VIEWPORT],
  files_sha256:Object.fromEntries(['index.html','index.pck','index.wasm'].map(name => [name,'b'.repeat(64)]))};
const geometry = () => ({box:{x:0,y:0,width:PREPARED_VIEWPORT[0],height:PREPARED_VIEWPORT[1]},viewport:[...PREPARED_VIEWPORT],display:'block',visibility:'visible',opacity:1});
const button = (text,x,width,in_action_scroll) => ({text,rect:[x,PREPARED_VIEWPORT[1]-52,width,46],disabled:false,in_action_scroll});
function state(tick=1) {
  return {build:manifest.build,tick,paused:false,game_over:false,selected:[7],touch_mode:false,build_mode:'',
    own_pending_commands:0,bank_milli:{food:150000,wood:200000},economy_scale:1000,population:6,capacity:10,delivered:0,built:0,trained:0,
    hud:{schema:2,viewport:[...PREPARED_VIEWPORT],camera:{focus:[-15,0,20],zoom:25},context_targets:[{id:100,category:'resource',kind:'oak',team:-1,screen:[200,300]}],ground_points:[[100,400]],selection_detail:'生命 100 / 100 · 待命 · 守備 · 按指令再點目標',
      own_targets:[{id:7,kind:'villager',category:'unit',screen:[170,240]}],selected_own:[],
      action_scroll:{rect:[130,PREPARED_VIEWPORT[1]-52,PREPARED_VIEWPORT[0]-136,46],scroll_horizontal:0},
      buttons:[button('指令',6,54,false),button('停止',68,54,false),button('民居\n木 50',130,90,true),{text:'選單',rect:[250,20,60,46],disabled:false,in_action_scroll:false}]}};
}
function command(s) {
  s=structuredClone(s);s.touch_mode=true;s.hud.selection_detail='點樹木或漿果採集，點空地移動；取消可返回選取。';
  s.hud.buttons[0].text='指令中';s.hud.buttons[1].text='取消';return s;
}
function site(tick,progress,label) {
  const s=state(tick);s.selected=[21];s.bank_milli.wood=150000;s.hud.selection_detail=label;
  const building={id:21,category:'building',kind:'house',built:false,progress,screen:[200,300]};
  s.hud.selected_own=[building];s.hud.own_targets.push(building);return s;
}

test('manifest requires exact prepared scenario and dimensions with reviewed final pins', () => {
  validateManifest(manifest);
  for(const change of [{reviewed:false},{build:null},{source_commit:null},{profile:'short320'},{scenario:'arbitrary'},
    {viewport:[PREPARED_VIEWPORT[0]+1,PREPARED_VIEWPORT[1]]},{viewport:[844,390]},
    {hud_schema:1},{files_sha256:{...manifest.files_sha256,'../bad':'b'.repeat(64)}}]) assert.throws(() => validateManifest({...manifest,...change}));
});
test('unsupported host profile never reaches context and real pin state is validated without runtime', async () => {
  let calls=0;const browser={newContext:async () => {calls++;}};
  await assert.rejects(runQA(browser,'/unused','http://127.0.0.1:12345','desktop'),/one portrait context/);
  const actual=JSON.parse(await readFile(new URL('./scenario-manifest.json',import.meta.url),'utf8'));
  if (actual.reviewed) validateManifest(actual);
  else await assert.rejects(runQA(browser,'/unused','http://127.0.0.1:12345','portrait'),/pins not reviewed/);
  assert.equal(calls,0);
});
test('logical map rejects offscreen and exact geometry rejects other viewport', () => {
  assert.deepEqual(mapPoint([195,422],[390,844],{x:10,y:20,width:780,height:1688}),[400,864]);
  assert.throws(() => mapPoint([390,4],[390,844],{x:0,y:0,width:390,height:844}));
  const good=geometry();validateCanvasGeometry(good,good.box);
  assert.throws(() => validateCanvasGeometry({...good,viewport:PREPARED_SCENARIO==='short320' ? [390,844] : [320,640]}));
  for(const change of [{visibility:'hidden'},{display:'none'},{opacity:0},{box:{...good.box,width:NaN}},
    {box:{...good.box,x:-1}},{box:{...good.box,x:2}},{box:{...good.box,width:0}}]) assert.throws(() => validateCanvasGeometry({...good,...change}));
  assert.throws(() => validateCanvasGeometry({...good,box:{...good.box,width:good.box.width-1}},good.box));
});
test('both widths demand pinned 54x46 Stop, full 90x46 house and zero scroll', () => {
  assertPinnedStop(state());
  for(const mutate of [s=>s.hud.buttons[1].rect[2]=53.99,s=>s.hud.buttons[1].rect[3]=45.99,
    s=>s.hud.buttons[1].in_action_scroll=true,s=>s.hud.buttons[1].disabled=true,
    s=>s.hud.buttons[2].rect[2]=89.99,s=>s.hud.buttons[2].rect[3]=45.99,
    s=>s.hud.buttons[2].in_action_scroll=false,s=>s.hud.action_scroll.scroll_horizontal=1,
    s=>s.hud.buttons[1].rect[0]=-1,s=>s.hud.buttons[2].rect[0]=PREPARED_VIEWPORT[0]-89,
    s=>s.hud.buttons[1].rect[0]=40,s=>s.hud.buttons.push(button('取消',230,54,false)),
    s=>s.hud.buttons.push({...s.hud.buttons[1]}),s=>s.touch_mode=true,s=>s.build_mode='house',
    s=>s.paused=true,s=>s.game_over=true]) {const s=state();mutate(s);assert.throws(()=>assertPinnedStop(s));}
});
test('Command requires full pinned Cancel and house, never a third pinned Stop', () => {
  assertCommandToolbar(command(state()));
  for(const mutate of [s=>s.hud.buttons[1].text='停止',s=>s.hud.buttons[1].rect[2]=53,
    s=>s.hud.buttons[1].in_action_scroll=true,s=>s.hud.buttons[2].rect[2]=89,
    s=>s.hud.buttons.push(button('停止',230,54,false)),s=>s.hud.buttons[0].text='指令']) {
    const s=command(state());mutate(s);assert.throws(()=>assertCommandToolbar(s));
  }
});
test('no-effect checks reject queued commands, charges, refunds, counters and missing telemetry', () => {
  const before=state();assertUnchangedEconomy(before,state(2));
  for(const mutate of [s=>s.own_pending_commands=1,s=>s.bank_milli.wood-=50000,s=>s.bank_milli.wood+=37000,
    s=>s.bank_milli.food-=50000,s=>s.population++,s=>s.capacity++,s=>s.delivered++,s=>s.built++,s=>s.trained++,
    s=>delete s.economy_scale,s=>delete s.own_pending_commands,s=>delete s.bank_milli,s=>s.paused=true]) {
    const s=state(2);mutate(s);assert.throws(()=>assertUnchangedEconomy(before,s));
  }
});
test('Cancel detects an already-applied Stop at queue zero, movement, selection or build changes', () => {
  const before=state();assertNoUnintendedOrder(before,state(2),7);
  assertNoUnintendedOrder(before,command(state(2)),7,true);
  for(const mutate of [s=>s.hud.selection_detail=s.hud.selection_detail.replace('守備','停止'),
    s=>s.hud.own_targets[0].screen[0]++,s=>s.selected=[8],s=>s.build_mode='house',
    s=>s.hud.own_targets=[],s=>s.tick=0,s=>s.touch_mode=true]) {
    const s=state(2);mutate(s);assert.throws(()=>assertNoUnintendedOrder(before,s,7));
  }
  const alreadyStopped=state();alreadyStopped.hud.selection_detail='待命 · 停止';
  assert.throws(()=>assertNoUnintendedOrder(alreadyStopped,alreadyStopped,7));
});
test('stopped/resumed construction retains same unfinished site and real-tick proofs', () => {
  const before=site(100,0.1,'無施工村民');
  assertStoppedProgress(before,site(120,0.1,'無施工村民'),21);
  assertResumedProgress(before,site(130,0.12,'建造中'),21);
  assert.throws(()=>assertStoppedProgress(before,site(119,0.1,'無施工村民'),21));
  assert.throws(()=>assertStoppedProgress(before,site(120,0.2,'無施工村民'),21));
  assert.throws(()=>assertResumedProgress(before,site(130,0.1,'建造中'),21));
  assert.throws(()=>assertResumedProgress(before,site(130,0.12,'村民移動到工地'),21));
  assert.equal(selectedSite(before,999),null);
});
test('fixture reads only public bridges and retains input, cache and failure bounds', async () => {
  const source=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');
  assert.equal((source.match(/page\.evaluate\(/g)||[]).length,1);
  assert.equal((source.match(/\.getBoundingClientRect\(\)/g)||[]).length,1);
  for(const marker of ['window.valleyMenuSnapshot();','if(game_bridge)window.valleySnapshot();','page.touchscreen.tap',
    '70000','exceeded5000ms','timeout:1500',"new URL(route.request().url()).origin === origin",
    "context.on('requestfailed', network.failed)",'Browser errors during context close']) assert.ok(source.includes(marker),marker);
  for(const forbidden of ['_test_reset','_submit(','.valleyState =','scrollLeft =','scroll_horizontal =',
    'swipeActionStrip','setViewportSize','valleyTouchCancel(']) assert.ok(!source.includes(forbidden),forbidden);
  if(PREPARED_SCENARIO==='short320') {
    assert.ok(source.includes('step<=6'));assert.ok(source.includes('evidence.menu_swipes=1'));
    assert.ok(source.includes('menuSwipePoints(shortcut)'));
  } else assert.ok(!source.includes('Input.dispatchTouchEvent'));
});
function menu(page='home',match_exists=false,visible=true) {
  const ids=visible?(page==='help'?['BackButton']:page==='confirm'?['ConfirmNewMatchButton','CancelNewMatchButton']:match_exists?['ResumeMatchButton','NewMatchButton','HelpButton']:['StartMatchButton','HelpButton']):[];
  return {visible,page,match_exists,game_bridge:match_exists,buttons:ids.map((id,i)=>({id,text:id,rect:[20,180+60*i,200,48]}))};
}
function obs(s=null,m=null) {return {state:s,menu:m??menu('home',true,false),geometry:geometry()};}
function frames() {
  const initial=state(1);initial.selected=[];
  const selected=state(2);
  const prefix=[obs(null,menu())];
  if(PREPARED_SCENARIO==='short320')prefix.push(obs(null,menu('help')),obs(null,menu()));
  prefix.push(obs(initial),obs(initial),obs(selected));
  if(PREPARED_SCENARIO==='contextual390') {
    const gathered=state(32);gathered.hud.selection_detail='生命 100 / 100 · 採集 · 負重 1 / 10 · 守備';gathered.hud.own_targets[0].screen=[182,250];
    return [...prefix,obs(gathered)];
  }
  if(PREPARED_SCENARIO==='short320') {
    const shortcut=t=>{const s=state(t);s.hud.buttons=[{text:'關閉',rect:[240,100,60,46],disabled:false},{text:'音效：關',rect:[20,290,280,46],disabled:false}];return s;};
    const scrolled=shortcut(28);scrolled.hud.buttons=[{text:'主選單',rect:[20,290,280,46],disabled:false}];
    const paused=state(30);paused.paused=true;
    return [...prefix,obs(command(state(3))),obs(state(4)),obs(state(24)),obs(shortcut(25)),obs(state(26)),obs(shortcut(27)),obs(scrolled),
      obs(paused,menu('home',true)),obs(paused,menu('home',true)),obs(paused,menu('confirm',true)),obs(paused,menu('confirm',true)),
      obs(paused,menu('home',true)),obs(paused,menu('home',true)),obs(state(31)),obs(state(32)),obs(state(52))];
  }
  const preview=state(3);preview.build_mode='house';preview.hud.preview={placement_ok:true,held:false,screen:[200,300]};
  const held=structuredClone(preview);held.tick=4;held.hud.preview.held=true;held.hud.buttons=[button('確認建造',130,100,true)];
  const placed=site(5,0.05,'建造');placed.selected=[7];placed.hud.selected_own=[];
  const stopped=site(6,0.1,'無施工村民'),stable=site(26,0.1,'無施工村民');
  const reselected=structuredClone(placed);reselected.tick=28;
  const targeted=command(reselected);targeted.tick=29;
  const submitted=structuredClone(reselected);submitted.tick=30;
  return [...prefix,...[preview,held,placed,stopped,stable,structuredClone(stable),reselected,targeted,submitted,site(31,0.2,'建造中')].map(s=>obs(s))];
}
async function fakeRun(mutator=null,failStream=false) {
  const root=await mkdtemp(path.join(tmpdir(),'rts-consolidated-inert-'));
  const inputs=[],screenshots=[],observations=frames();if(mutator)mutator(observations);
  let contextCalls=0,readIndex=0,contextOptions,routeHandler;const touchProtocol=[];
  try {
    for(const file of ['browser_qa.mjs','network_diagnostics.mjs','public_stream_cache_policy.mjs','public_observation_assertions.mjs']) await copyFile(new URL('./'+file,import.meta.url),path.join(root,file));
    await writeFile(path.join(root,'scenario-manifest.json'),JSON.stringify(manifest));
    const fixture=await import(pathToFileURL(path.join(root,'browser_qa.mjs')));
    const listeners={};let closed=false;
    const page={setDefaultTimeout(){},on(){},route:async (_pattern,handler)=>{routeHandler=handler;},goto:async()=>{},waitForFunction:async()=>{},
      evaluate:async()=>{assert.ok(readIndex<observations.length,'Unexpected extra snapshot');return observations[readIndex++];},
      touchscreen:{tap:async(x,y)=>inputs.push([x,y])},screenshot:async opts=>screenshots.push(path.basename(opts.path)),isClosed:()=>closed};
    const context={newPage:async()=>page,on:(name,fn)=>{listeners[name]=fn;},
      newCDPSession:async()=>({send:async(method,data)=>{assert.equal(method,'Input.dispatchTouchEvent');touchProtocol.push(data);},detach:async()=>{}}),close:async()=>{
      for(const name of ['index.wasm','index.pck']) {
        const req={url:()=>`http://127.0.0.1:12345/${name}`,method:()=> 'GET',resourceType:()=> 'fetch',failure:()=>({errorText:'net::ERR_ABORTED'})};
        listeners.request(req);listeners.response({request:()=>req,status:()=>200,headers:()=>({'cache-control':'no-cache'})});
        if(failStream&&name==='index.pck')listeners.requestfailed(req);else listeners.requestfinished(req);
      }closed=true;
    }};
    const browser={newContext:async options=>{contextCalls++;contextOptions=options;return context;}};
    let result,error;try {result=await fixture.runQA(browser,root,'http://127.0.0.1:12345','portrait');}catch(e){error=e;}
    const evidence=JSON.parse(await readFile(path.join(root,'browser-evidence.json'),'utf8'));
    return {result,error,evidence,inputs,screenshots,contextCalls,contextOptions,routeHandler,readIndex,touchProtocol};
  } finally {await rm(root,{recursive:true,force:true});}
}
test('fake browser exercises fixed ordinary Start and touch path with required screenshot requests',async()=>{
  const r=await fakeRun();assert.ifError(r.error);assert.equal(r.evidence.basicSmokePassed,true);assert.equal(r.evidence.releaseQAPassed,false);
  assert.equal(r.contextCalls,1);assert.deepEqual(r.contextOptions,{viewport:{width:PREPARED_VIEWPORT[0],height:PREPARED_VIEWPORT[1]},deviceScaleFactor:1,hasTouch:true,serviceWorkers:'block'});
  assert.equal(r.evidence.toolbar_swipes,0);
  const shots=[`${PREPARED_SCENARIO}-main-menu.png`];
  if(PREPARED_SCENARIO==='short320')shots.push('short320-menu-help.png');
  shots.push(`${PREPARED_SCENARIO}-opening-terrain.png`);
  if(PREPARED_SCENARIO==='short320') {
    assert.equal(r.inputs.length,13);assert.equal(r.evidence.menu_swipes,1);assert.equal(r.touchProtocol.length,8);
    assert.equal(r.touchProtocol[0].type,'touchStart');assert.equal(r.touchProtocol[7].type,'touchEnd');
    assert.ok(r.touchProtocol.slice(1,7).every(x=>x.type==='touchMove'));
    shots.push('short320-stop-ready.png','short320-command-ready.png','short320-cancel-returned.png','short320-shortcut-menu.png','short320-paused-main-menu.png','short320-menu-resumed-toolbar.png');
  } else {
    assert.equal(r.touchProtocol.length,0);assert.equal(r.evidence.menu_swipes,0);assert.equal(r.evidence.swipe_count,0);
    if(PREPARED_SCENARIO==='natural390') {assert.equal(r.inputs.length,11);shots.push('portrait-stop-ready.png','portrait-construction-stopped.png','portrait-construction-resumed.png');}
    else {assert.equal(r.inputs.length,3);assert.ok(r.evidence.projected_movement_observed);shots.push('contextual390-resource-ready.png','contextual390-actual-gather.png');}
  }
  assert.deepEqual(r.screenshots,shots);
  assert.equal(r.evidence.input_timings.filter(x=>x.label==='StartMatchButton').length,1);
  for(const [url,expected] of [['http://127.0.0.1:12345/index.pck','continue'],['http://127.0.0.1:12346/index.pck','abort'],['https://example.invalid/index.pck','abort']]) {
    let action;await r.routeHandler({request:()=>({url:()=>url}),continue:()=>{action='continue';},abort:()=>{action='abort';}});assert.equal(action,expected);
  }
});
test('fake initial menu rejects an early game bridge before any touch',async()=>{
  const r=await fakeRun(frames=>{frames[0].menu.game_bridge=true;});assert.ok(r.error);assert.equal(r.inputs.length,0);
});
test('fake initial menu rejects a clipped Start before world interaction',async()=>{
  const r=await fakeRun(frames=>{for(const f of frames)for(const b of f.menu.buttons)if(b.id==='StartMatchButton')b.rect[3]=47;});assert.ok(r.error);
});
test('fake missing pinned Stop fails before construction/contextual commands',async()=>{
  const r=await fakeRun(frames=>{const f=frames.find(x=>x.state?.tick===2);f.state.hud.buttons[1].in_action_scroll=true;});
  assert.ok(r.error);assert.equal(r.evidence.basicSmokePassed,false);assert.equal(r.inputs.length,PREPARED_SCENARIO==='short320'?4:2);
});
test('fake context never converts failed public stream or close-time abort into success',async()=>{
  const r=await fakeRun(null,true);assert.ok(r.error);assert.equal(r.evidence.basicSmokePassed,false);assert.ok(r.evidence.error_count>0);
});
test('fake short Cancel rejects applied Stop even with cleared pending queue',{skip:PREPARED_SCENARIO!=='short320'},async()=>{
  const r=await fakeRun(fs=>{const f=fs.find(x=>x.state?.tick===4);f.state.hud.selection_detail=f.state.hud.selection_detail.replace('守備','停止');});assert.ok(r.error);assert.equal(r.inputs.length,6);
});
test('fake short Command rejects unintended queued order before Cancel',{skip:PREPARED_SCENARIO!=='short320'},async()=>{
  const r=await fakeRun(fs=>{fs.find(x=>x.state?.tick===3).state.own_pending_commands=1;});assert.ok(r.error);assert.equal(r.inputs.length,5);
});
test('fake short Cancel rejects charge after queue cleared',{skip:PREPARED_SCENARIO!=='short320'},async()=>{
  const r=await fakeRun(fs=>{fs.find(x=>x.state?.tick===4).state.bank_milli.wood-=50000;});assert.ok(r.error);assert.equal(r.inputs.length,6);
});
test('fake resumed match rejects visible movement or order change',{skip:PREPARED_SCENARIO!=='short320'},async()=>{
  const r=await fakeRun(fs=>{fs.find(x=>x.state?.tick===32).state.hud.own_targets[0].screen[0]++;});assert.ok(r.error);assert.equal(r.evidence.basicSmokePassed,false);
});
test('fake contextual gather rejects unchanged cargo despite gather status',{skip:PREPARED_SCENARIO!=='contextual390'},async()=>{
  const r=await fakeRun(fs=>{fs.at(-1).state.hud.selection_detail='採集';});assert.ok(r.error);assert.equal(r.evidence.basicSmokePassed,false);assert.equal(r.inputs.length,3);
});
test('fake contextual selection cannot target absent resource',{skip:PREPARED_SCENARIO!=='contextual390'},async()=>{
  const r=await fakeRun(fs=>{fs.find(x=>x.state?.tick===2).state.hud.context_targets=[];});assert.ok(r.error);assert.equal(r.inputs.length,2);
});
