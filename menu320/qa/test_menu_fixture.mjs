// Synthetic contract/control-flow tests only. No browser/engine/process launch.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,writeFile,copyFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {validateManifest,mapPoint,validateCanvasGeometry,assertMenuControls,helpSwipePoints,assertResumedMatch,menuGeometryReady,menuGeometryIssue,waitForMenuTransition,shortcutMenuReady,assertHelpScroll,
  PREPARED_SCENARIO,PREPARED_VIEWPORT,RESIZED_VIEWPORT,PREPARED_PROFILE,TOUCH,HELP_SCROLL_GESTURES,HELP_FINAL_PARAGRAPH,runQA} from './browser_qa.mjs';
const manifest={reviewed:true,build:'vc-123456789abc',source_commit:'a'.repeat(40),profile:PREPARED_PROFILE,hud_schema:2,
  scenario:PREPARED_SCENARIO,viewport:[...PREPARED_VIEWPORT],resized_viewport:[...RESIZED_VIEWPORT],
  files_sha256:Object.fromEntries(['index.html','index.pck','index.wasm'].map(n=>[n,'b'.repeat(64)]))};
function geometry(v=PREPARED_VIEWPORT){return {box:{x:0,y:0,width:v[0],height:v[1]},viewport:[...v],display:'block',visibility:'visible',opacity:1};}
function menu(page='home',match=false,visible=true,v=PREPARED_VIEWPORT){
  const ids=!visible?[]:page==='help'?['BackButton']:page==='confirm'?['ConfirmNewMatchButton','CancelNewMatchButton']:match?['ResumeMatchButton','NewMatchButton','HelpButton']:['StartMatchButton','HelpButton'];
  const m={visible,page,match_exists:match,game_bridge:match,buttons:ids.map((id,i)=>({id,text:id,rect:page==='help'?[20,v[1]-80,200,54]:[20,Math.min(180,v[1]-ids.length*64-20)+i*64,200,54]}))};
  if(visible&&page==='help'){
    const rect=[20,Math.min(180,v[1]-170),200,54];
    m.help_scroll={value:600,maximum:800,page:200,final_rect:[...rect],final_visible_rect:[...rect],final_text:HELP_FINAL_PARAGRAPH};
  }
  return m;
}
function state(tick=40,paused=false,selected=[7],v=PREPARED_VIEWPORT){return {
  build:manifest.build,tick,paused,game_over:false,selected,touch_mode:false,build_mode:'',own_pending_commands:0,
  bank_milli:{food:150000,wood:200000},economy_scale:1000,population:6,capacity:10,delivered:0,built:0,trained:0,
  hud:{schema:2,viewport:[...v],camera:{focus:[-15,0,20],zoom:25},own_targets:[{id:7,kind:'villager',screen:[100,250]}],
    buttons:[{text:'選單',rect:[210,10,60,46],disabled:false}]}};}
const obs=(m,s=null,v=PREPARED_VIEWPORT)=>({menu:m,state:s,geometry:geometry(v)});
function frames(){
  const home=()=>obs(menu()),help=v=>obs(menu('help',false,true,v),null,v);
  const active=(tick=40)=>obs(menu('home',true,false),state(tick));
  const shortcut=tick=>{const o=active(tick);o.state.hud.buttons=[{text:tick===68?'收起':'關閉',rect:[210,70,60,46],disabled:false},{text:'主選單',rect:[20,300,200,46],disabled:false}];return o;};
  const paused=(v=PREPARED_VIEWPORT,tick=45,page='home')=>obs(menu(page,true,true,v),state(tick,true,[7],v),v);
  const initialHelp=help(PREPARED_VIEWPORT);initialHelp.menu.help_scroll.value=0;initialHelp.menu.help_scroll.final_rect[1]=PREPARED_VIEWPORT[1]+10;initialHelp.menu.help_scroll.final_visible_rect=[0,0,0,0];
  const result=[home(),...Array.from({length:TOUCH?3:1},home),initialHelp];
  result.splice(1,0,obs(menu('home',false,true,RESIZED_VIEWPORT),null,RESIZED_VIEWPORT),home());
  for(let i=0;i<HELP_SCROLL_GESTURES;i++)result.push(help(PREPARED_VIEWPORT));
  result.push(help(RESIZED_VIEWPORT));for(let i=0;i<HELP_SCROLL_GESTURES;i++)result.push(help(RESIZED_VIEWPORT));
  result.push(help(PREPARED_VIEWPORT),home(),obs(menu('home',true,false),state(1,false,[])),active(),shortcut(42),paused());
  result.push(paused(RESIZED_VIEWPORT));if(TOUCH)result.push(paused(RESIZED_VIEWPORT));
  result.push(paused(),paused(PREPARED_VIEWPORT,45,'confirm'),paused(),active(65),shortcut(68),paused(PREPARED_VIEWPORT,70),paused(PREPARED_VIEWPORT,70,'confirm'),obs(menu('home',true,false),state(1,false,[])));
  return result;
}
test('review gate binds exact profile, both viewports, identity and safe export files',()=>{
  validateManifest(manifest);
  for(const change of [{reviewed:false},{build:null},{source_commit:null},{profile:'other'},{scenario:'other'},{viewport:[1,2]},
    {resized_viewport:[1,2]},{hud_schema:1},{files_sha256:{...manifest.files_sha256,'../bad':'b'.repeat(64)}}])assert.throws(()=>validateManifest({...manifest,...change}));
});
test('real candidate remains disabled before any fake context is opened',async()=>{
  let calls=0;const browser={newContext:async()=>{calls++;}};
  await assert.rejects(runQA(browser,'/unused','http://127.0.0.1:1',PREPARED_PROFILE==='portrait'?'desktop':'portrait'),/Wrong fixed/);
  const actual=JSON.parse(await readFile(new URL('./scenario-manifest.json',import.meta.url),'utf8'));
  if(actual.reviewed)validateManifest(actual);else await assert.rejects(runQA(browser,'/unused','http://127.0.0.1:1',PREPARED_PROFILE),/pins not reviewed/);
  assert.equal(calls,0);
});
test('canvas mappings reject unexpected resize, hidden/partial canvas and stale cache',()=>{
  assert.deepEqual(mapPoint([50,100],[100,200],{x:10,y:20,width:200,height:400}),[110,220]);
  assert.throws(()=>mapPoint([100,100],[100,200],{x:0,y:0,width:100,height:200}));
  for(const v of [PREPARED_VIEWPORT,RESIZED_VIEWPORT])validateCanvasGeometry(geometry(v),v);
  assert.throws(()=>validateCanvasGeometry(geometry(),[123,456]));
  for(const change of [{display:'none'},{visibility:'hidden'},{opacity:0},{box:{...geometry().box,x:-1}},{box:{...geometry().box,x:2}}])assert.throws(()=>validateCanvasGeometry({...geometry(),...change},PREPARED_VIEWPORT));
  assert.throws(()=>validateCanvasGeometry(geometry(RESIZED_VIEWPORT),RESIZED_VIEWPORT,geometry().box));
});
test('full menu target count/order, height and spacing reject clipping',()=>{
  const ids=['ResumeMatchButton','NewMatchButton','HelpButton'];assertMenuControls(menu('home',true),PREPARED_VIEWPORT,ids);
  for(const mutate of [m=>m.buttons[0].rect[3]=53,m=>m.buttons[1].rect[1]=220,m=>m.buttons.reverse(),m=>m.buttons.pop(),m=>m.buttons[0].rect[0]=-1]){const m=menu('home',true);mutate(m);assert.throws(()=>assertMenuControls(m,PREPARED_VIEWPORT,ids));}
});
test('Help gestures stay above public Back without pretending to observe scroll offset',()=>{
  for(const v of [PREPARED_VIEWPORT,RESIZED_VIEWPORT]){const m=menu('help',false,true,v),p=helpSwipePoints(m,v);assert.ok(p.start[1]<m.buttons[0].rect[1]);assert.ok(p.end[1]>0&&p.start[1]>p.end[1]);}
});
test('resume witnesses reject lost selection, charges, queued commands and nonadvancing identity',()=>{
  const before=state(45,true),after=state(65);assertResumedMatch(before,after);
  for(const mutate of [s=>s.selected=[],s=>s.bank_milli.wood--,s=>s.own_pending_commands=1,s=>s.tick=44,s=>s.paused=true,s=>s.hud.camera.zoom++]){const s=structuredClone(after);mutate(s);assert.throws(()=>assertResumedMatch(before,s));}
});
test('fixture uses one read-only evaluate and unchanged time/network failure contract',async()=>{
  const source=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');
  assert.equal((source.match(/page\.evaluate\(/g)||[]).length,1);
  assert.equal((source.match(/\.getBoundingClientRect\(\)/g)||[]).length,1);
  for(const marker of ['window.valleyMenuSnapshot();','if(game_bridge)window.valleySnapshot();','page.touchscreen.tap','page.mouse.click',
    '70000','exceeded5000ms','timeout:1500',"context.on('requestfailed',network.failed)",'Browser errors during context close',
    'HELP_SCROLL_GESTURES = 6','for(let step=1;step<=6;step++)','pending-human-pixel-review','visualAcceptancePassed:false','releaseQAPassed:false'])assert.ok(source.includes(marker),marker);
  for(const forbidden of ['dispatchEvent','_test_reset','_submit(','.valleyState =','scrollLeft =','scroll_horizontal =','valleyTouchCancel(','valleyMenuTouchCancel('])assert.ok(!source.replace('// Interrupted-pointer probes do not invoke handlers/dispatchEvent/game APIs.','').includes(forbidden),forbidden);
});
async function fakeRun(mutate=null,failStream=false){
  const root=await mkdtemp(path.join(tmpdir(),'rts-menu-inert-')),observations=frames();if(mutate)mutate(observations);
  let reads=0,closed=false,contextCalls=0,options,routeHandler;const shots=[],inputs=[],touches=[],resizes=[];
  try{
    for(const file of ['browser_qa.mjs','network_diagnostics.mjs','public_stream_cache_policy.mjs','public_observation_assertions.mjs'])await copyFile(new URL('./'+file,import.meta.url),path.join(root,file));
    await writeFile(path.join(root,'scenario-manifest.json'),JSON.stringify(manifest));
    const fixture=await import(pathToFileURL(path.join(root,'browser_qa.mjs'))),listeners={};
    const page={setDefaultTimeout(){},on(){},route:async(_p,h)=>{routeHandler=h;},goto:async()=>{},waitForFunction:async()=>{},
      evaluate:async()=>{assert.ok(reads<observations.length,'Unexpected snapshot');return observations[reads++];},
      touchscreen:{tap:async(...p)=>inputs.push(['touch',...p])},keyboard:{press:async key=>inputs.push(['key',key])},
      mouse:Object.fromEntries(['click','move','down','up','wheel'].map(n=>[n,async(...p)=>inputs.push([n,...p])])),
      setViewportSize:async v=>resizes.push(v),screenshot:async o=>shots.push(path.basename(o.path)),isClosed:()=>closed};
    const context={newPage:async()=>page,on:(n,f)=>{listeners[n]=f;},
      newCDPSession:async()=>({send:async(m,d)=>{assert.equal(m,'Input.dispatchTouchEvent');touches.push(d);},detach:async()=>{}}),
      close:async()=>{for(const name of ['index.wasm','index.pck']){
        const req={url:()=>`http://127.0.0.1:12345/${name}`,method:()=>'GET',resourceType:()=>'fetch',failure:()=>({errorText:'net::ERR_ABORTED'})};
        listeners.request(req);listeners.response({request:()=>req,status:()=>200,headers:()=>({'cache-control':'no-cache'})});
        if(failStream&&name==='index.pck')listeners.requestfailed(req);else listeners.requestfinished(req);
      }closed=true;}};
    const browser={newContext:async o=>{contextCalls++;options=o;return context;}};
    let error,result;try{result=await fixture.runQA(browser,root,'http://127.0.0.1:12345',PREPARED_PROFILE);}catch(e){error=e;}
    const evidence=JSON.parse(await readFile(path.join(root,'browser-evidence.json'),'utf8'));
    return {error,result,evidence,reads,shots,inputs,touches,resizes,options,contextCalls,routeHandler};
  }finally{await rm(root,{recursive:true,force:true});}
}
test('fake end-to-end fixed flow requests genuine captures and records only functional success',async()=>{
  const r=await fakeRun();assert.ifError(r.error);assert.equal(r.reads,frames().length);assert.equal(r.evidence.basicSmokePassed,true);
  assert.equal(r.evidence.releaseQAPassed,false);assert.equal(r.evidence.visualAcceptancePassed,false);assert.equal(r.contextCalls,1);
  assert.deepEqual(r.options,{viewport:{width:PREPARED_VIEWPORT[0],height:PREPARED_VIEWPORT[1]},deviceScaleFactor:1,hasTouch:TOUCH,serviceWorkers:'block'});
  assert.deepEqual(r.resizes,[RESIZED_VIEWPORT,PREPARED_VIEWPORT,RESIZED_VIEWPORT,PREPARED_VIEWPORT,RESIZED_VIEWPORT,PREPARED_VIEWPORT].map(v=>({width:v[0],height:v[1]})));
  assert.ok(r.shots.includes(`${PREPARED_SCENARIO}-home-resized.png`),'Fresh568 branding screenshot required');
  for(const label of ['home','help-after-scroll','help-resized-before-extra-scroll','help-resized-after-scroll','help-restored','paused-home','paused-home-resized','paused-home-restored','new-match-confirmation','new-match-canceled'])assert.ok(r.shots.includes(`${PREPARED_SCENARIO}-${label}.png`),label);
  assert.equal(r.evidence.input_timings.filter(x=>x.label.startsWith('help-scroll')).length,12);
  if(TOUCH){assert.ok(r.touches.some(x=>x.type==='touchCancel'));assert.ok(r.touches.some(x=>x.touchPoints.length===2));}
  else{assert.equal(r.touches.length,0);assert.ok(r.inputs.some(x=>x[0]==='key'));assert.ok(r.inputs.some(x=>x[0]==='wheel'));}
  for(const [url,expected] of [['http://127.0.0.1:12345/index.pck','continue'],['http://127.0.0.1:12346/index.pck','abort'],['https://example.invalid/a','abort']]){
    let action;await r.routeHandler({request:()=>({url:()=>url}),continue:()=>{action='continue';},abort:()=>{action='abort';}});assert.equal(action,expected);
  }
});
test('fake early bridge fails before any touch',async()=>{const r=await fakeRun(fs=>{fs[0].menu.game_bridge=true;});assert.ok(r.error);assert.equal(r.inputs.length,0);});
test('fake nonfinite Back fails before scrolling',async()=>{const r=await fakeRun(fs=>{fs.find(o=>o.menu.page==='help').menu.buttons[0].rect[3]=NaN;});assert.match(String(r.error),/Nonfinite or malformed menu rect/);assert.equal(r.evidence.basicSmokePassed,false);});
test('fake paused resize cannot silently resume or change retained economy',async()=>{const r=await fakeRun(fs=>{fs.find(o=>o.state?.paused&&o.geometry.viewport[0]===RESIZED_VIEWPORT[0]).state.bank_milli.wood--;});assert.match(String(r.error),/deep-equal|bank_milli/);assert.equal(r.evidence.basicSmokePassed,false);});
test('fake canceled new match cannot silently reset tick',async()=>{const r=await fakeRun(fs=>{const i=fs.findIndex(o=>o.menu.page==='confirm');fs[i+1].state.tick=1;});assert.match(String(r.error),/Paused main menu advanced simulation/);assert.equal(r.evidence.basicSmokePassed,false);});
test('failed public stream including close-time abort remains fatal',async()=>{const r=await fakeRun(null,true);assert.match(String(r.error),/Browser errors during context close/);assert.equal(r.evidence.basicSmokePassed,false);assert.ok(r.evidence.error_count>0);});

test('transient finite geometry may settle, but original strict acceptance still rejects it',()=>{
  const ids=['ResumeMatchButton','NewMatchButton','HelpButton'];
  const m=menu('home',true);m.buttons.forEach((b,i)=>b.rect=[20,180,[104,86,68][i],54]);
  assert.equal(menuGeometryReady(m,PREPARED_VIEWPORT,ids),false);
  assert.match(menuGeometryIssue(m,PREPARED_VIEWPORT,ids),/overlap/);
  assert.throws(()=>assertMenuControls(m,PREPARED_VIEWPORT,ids),/overlap/);
  assert.equal(menuGeometryReady(menu('home',true),PREPARED_VIEWPORT,ids),true);
  for(const mutate of [m=>m.buttons.reverse(),m=>m.buttons.pop(),m=>m.buttons[0].rect[0]=NaN]){
    const bad=menu('home',true);mutate(bad);assert.throws(()=>menuGeometryReady(bad,PREPARED_VIEWPORT,ids));
  }
});
test('transition geometry then valid uses one original deadline, never a fresh window',async()=>{
  let clock=1000,reads=0;const deadlines=[],sleeps=[];
  const out=await waitForMenuTransition(async deadline=>{deadlines.push(deadline);return ++reads;},x=>x===2,'settling',{
    now:()=>clock,sleep:async ms=>{sleeps.push(ms);clock+=ms;}});
  assert.equal(out,2);assert.deepEqual(deadlines,[4000,4000]);assert.deepEqual(sleeps,[120]);
});
test('persistently invalid geometry expires at original 3000ms and semantic exceptions are immediate',async()=>{
  let clock=0,reads=0;const deadlines=[];
  const invalid=menu('home',true);invalid.buttons.forEach(b=>{b.rect[1]=180;});
  await assert.rejects(waitForMenuTransition(async deadline=>{deadlines.push(deadline);reads++;return invalid;},m=>menuGeometryReady(m,PREPARED_VIEWPORT,['ResumeMatchButton','NewMatchButton','HelpButton']),'persistent bad bounds',{
    now:()=>clock,sleep:async ms=>{clock+=ms;}}),/original 3000ms transition/);
  assert.equal(clock,3000);assert.equal(reads,25);assert.ok(deadlines.every(d=>d===3000));
  let badReads=0,sleeps=0;
  const error=new Error('semantic ID mismatch');
  await assert.rejects(waitForMenuTransition(async()=>{badReads++;return {};},()=>{throw error;},'semantic',{
    now:()=>0,sleep:async()=>{sleeps++;}}),x=>x===error);
  assert.equal(badReads,1);assert.equal(sleeps,0);
});
test('read ending beyond transition deadline cannot pass even with valid geometry',async()=>{
  let clock=0;let readyCalls=0;
  await assert.rejects(waitForMenuTransition(async deadline=>{assert.equal(deadline,3000);clock=3001;return {};},()=>{readyCalls++;return true;},'late read',{
    now:()=>clock,sleep:async()=>{throw new Error('Unexpected sleep');}}),/original 3000ms transition/);
  assert.equal(readyCalls,0);
});
test('actual shortcut labels require Close or actionable Collapse plus Main Menu',()=>{
  const s=state(),b=(text)=>({text,rect:[20,100,100,46],disabled:false});
  for(const labels of [['關閉'],['關閉','收起','主選單'],['收起','主選單']]){
    s.hud.buttons=labels.map(b);assert.equal(shortcutMenuReady(s),true);
  }
  for(const labels of [[],['收起'],['主選單'],['選單'],['關閉選單'],['收起工具','主選單']]){
    s.hud.buttons=labels.map(b);assert.equal(shortcutMenuReady(s),false);
  }
  s.hud.buttons=['收起','主選單'].map(b);s.hud.buttons[1].rect[3]=45;assert.equal(shortcutMenuReady(s),false);
  s.hud.buttons=['收起','主選單'].map(b);s.hud.buttons[0].disabled=true;assert.equal(shortcutMenuReady(s),false);
  s.hud.buttons=['收起','收起','主選單'].map(b);assert.throws(()=>shortcutMenuReady(s),/Ambiguous/);
});
test('fake post-Cancel transient geometry is recorded then fully accepted, never skipped',async()=>{
  const r=await fakeRun(fs=>{
    const i=fs.findIndex(o=>o.menu.page==='confirm')+1;
    const collapsed=structuredClone(fs[i]);collapsed.menu.buttons.forEach(b=>{b.rect[1]=180;});fs.splice(i,0,collapsed);
  });
  assert.ifError(r.error);assert.equal(r.evidence.basicSmokePassed,true);
  assert.equal(r.reads,frames().length+1);assert.equal(r.evidence.pending_menu_geometry.length,1);
  assert.match(r.evidence.pending_menu_geometry[0].reason,/overlap/);
  assert.match(r.evidence.last_menu_geometry_issue,/overlap/);
  assert.ok(r.evidence.checkpoints.some(c=>c.phase==='new-match-cancel-preserved-match'));
});
test('fake transient geometry cannot mask paused match mutation',async()=>{
  const r=await fakeRun(fs=>{
    const i=fs.findIndex(o=>o.menu.page==='confirm')+1;
    fs[i].menu.buttons.forEach(b=>{b.rect[1]=180;});fs[i].state.tick=1;
  });
  assert.match(String(r.error),/Paused main menu advanced simulation/);assert.equal(r.evidence.pending_menu_geometry.length,0);
});
test('no optional active-gameplay PNG replaces any state or required menu evidence',async()=>{
  const s=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');
  for(const label of ['live-before-menu','resumed','confirmed-new-match'])assert.ok(!s.includes("await shot('"+label+"')"));
  for(const label of ['home','keyboard-focus','help-before-scroll','help-after-scroll','help-resized-before-extra-scroll','help-resized-after-scroll','help-restored','paused-home','paused-home-resized','paused-home-restored','new-match-confirmation','new-match-canceled'])assert.ok(s.includes("await shot('"+label+"')"));
  for(const marker of ['o.state.tick>=40','o.state.tick>=paused.tick+20','o.state.tick<beforeRestart.tick','assertResumedMatch(paused,current.state)','assertFrozenMatch(paused,current.state)','assert.deepEqual(current.state.selected,[])',"checkpoint('resumed-same-observed-match'", "checkpoint('confirmed-new-match-observed-reset'"]){
    if(marker==='assert.deepEqual(current.state.selected,[])')assert.ok(s.includes("assert.deepEqual(current.state.selected,[],"));else assert.ok(s.includes(marker),marker);
  }
});

test('Help telemetry exists only on visible Help with the exact finalized schema and paragraph',()=>{
  const m=menu('help');assertHelpScroll(m,PREPARED_VIEWPORT,true);
  for(const other of [menu(),menu('confirm',true),menu('help',true,false)]){
    assert.equal(assertHelpScroll(other,PREPARED_VIEWPORT),null);
    other.help_scroll=structuredClone(m.help_scroll);assert.throws(()=>assertHelpScroll(other,PREPARED_VIEWPORT),/outside visible Help/);
  }
  for(const mutate of [h=>delete h.value,h=>h.extra=1,h=>h.value=NaN,h=>h.value=-1,h=>h.maximum=-1,h=>h.page=Infinity,
    h=>h.value=601,h=>h.final_text='Different wording',h=>h.final_rect[0]=NaN,h=>h.final_visible_rect[2]=-1]){
    const bad=menu('help');mutate(bad.help_scroll);assert.throws(()=>assertHelpScroll(bad,PREPARED_VIEWPORT));
  }
  const missing=menu('help');delete missing.help_scroll;assert.throws(()=>assertHelpScroll(missing,PREPARED_VIEWPORT),/missing/);
});
test('reaching the scrollbar end cannot substitute for full final paragraph visibility',()=>{
  const m=menu('help');m.help_scroll.final_visible_rect[3]-=1;
  assertHelpScroll(m,PREPARED_VIEWPORT);assert.throws(()=>assertHelpScroll(m,PREPARED_VIEWPORT,true),/not completely visible/);
  for(const mutate of [h=>h.final_rect[2]=0,h=>h.page=0,h=>{h.final_rect[1]=PREPARED_VIEWPORT[1]+1;h.final_visible_rect=[...h.final_rect];}]){
    const bad=menu('help');mutate(bad.help_scroll);assert.throws(()=>assertHelpScroll(bad,PREPARED_VIEWPORT,true));
  }
});
test('fake six completed Help gestures fail if final paragraph remains clipped',async()=>{
  const r=await fakeRun(fs=>{
    const index=fs.findIndex(o=>o.menu.page==='help')+HELP_SCROLL_GESTURES;
    fs[index].menu.help_scroll.final_visible_rect[3]-=1;
  });
  assert.match(String(r.error),/Final Help paragraph is not completely visible/);
  assert.equal(r.evidence.basicSmokePassed,false);
  assert.equal(r.evidence.input_timings.filter(x=>x.label.startsWith('help-scroll')).length,6);
  assert.ok(!r.shots.includes(`${PREPARED_SCENARIO}-help-after-scroll.png`));
});
