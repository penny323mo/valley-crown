// Synthetic contract/control-flow tests only. No browser/engine/process launch.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,writeFile,copyFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {validateManifest,mapPoint,validateCanvasGeometry,assertMenuControls,helpSwipePoints,assertResumedMatch,
  PREPARED_SCENARIO,PREPARED_VIEWPORT,RESIZED_VIEWPORT,PREPARED_PROFILE,TOUCH,HELP_SCROLL_GESTURES,runQA} from './browser_qa.mjs';
const manifest={reviewed:true,build:'vc-123456789abc',source_commit:'a'.repeat(40),profile:PREPARED_PROFILE,hud_schema:2,
  scenario:PREPARED_SCENARIO,viewport:[...PREPARED_VIEWPORT],resized_viewport:[...RESIZED_VIEWPORT],
  files_sha256:Object.fromEntries(['index.html','index.pck','index.wasm'].map(n=>[n,'b'.repeat(64)]))};
function geometry(v=PREPARED_VIEWPORT){return {box:{x:0,y:0,width:v[0],height:v[1]},viewport:[...v],display:'block',visibility:'visible',opacity:1};}
function menu(page='home',match=false,visible=true,v=PREPARED_VIEWPORT){
  const ids=!visible?[]:page==='help'?['BackButton']:page==='confirm'?['ConfirmNewMatchButton','CancelNewMatchButton']:match?['ResumeMatchButton','NewMatchButton','HelpButton']:['StartMatchButton','HelpButton'];
  return {visible,page,match_exists:match,game_bridge:match,buttons:ids.map((id,i)=>({id,text:id,rect:page==='help'?[20,v[1]-80,200,54]:[20,Math.min(180,v[1]-ids.length*64-20)+i*64,200,54]}))};
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
  const shortcut=tick=>{const o=active(tick);o.state.hud.buttons=[{text:'關閉',rect:[210,70,60,46],disabled:false},{text:'主選單',rect:[20,300,200,46],disabled:false}];return o;};
  const paused=(v=PREPARED_VIEWPORT,tick=45,page='home')=>obs(menu(page,true,true,v),state(tick,true,[7],v),v);
  const result=[home(),...Array.from({length:TOUCH?3:1},home),help(PREPARED_VIEWPORT)];
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
  assert.deepEqual(r.resizes,[RESIZED_VIEWPORT,PREPARED_VIEWPORT,RESIZED_VIEWPORT,PREPARED_VIEWPORT].map(v=>({width:v[0],height:v[1]})));
  for(const label of ['home','help-after-scroll','help-resized-before-extra-scroll','help-resized-after-scroll','help-restored','paused-home','paused-home-resized','paused-home-restored','new-match-confirmation','new-match-canceled','resumed','confirmed-new-match'])assert.ok(r.shots.includes(`${PREPARED_SCENARIO}-${label}.png`),label);
  assert.equal(r.evidence.input_timings.filter(x=>x.label.startsWith('help-scroll')).length,12);
  if(TOUCH){assert.ok(r.touches.some(x=>x.type==='touchCancel'));assert.ok(r.touches.some(x=>x.touchPoints.length===2));}
  else{assert.equal(r.touches.length,0);assert.ok(r.inputs.some(x=>x[0]==='key'));assert.ok(r.inputs.some(x=>x[0]==='wheel'));}
  for(const [url,expected] of [['http://127.0.0.1:12345/index.pck','continue'],['http://127.0.0.1:12346/index.pck','abort'],['https://example.invalid/a','abort']]){
    let action;await r.routeHandler({request:()=>({url:()=>url}),continue:()=>{action='continue';},abort:()=>{action='abort';}});assert.equal(action,expected);
  }
});
test('fake early bridge fails before any touch',async()=>{const r=await fakeRun(fs=>{fs[0].menu.game_bridge=true;});assert.ok(r.error);assert.equal(r.inputs.length,0);});
test('fake clipped Back fails before scrolling',async()=>{const r=await fakeRun(fs=>{fs.find(o=>o.menu.page==='help').menu.buttons[0].rect[3]=53;});assert.match(String(r.error),/54px menu target clipped/);assert.equal(r.evidence.basicSmokePassed,false);});
test('fake paused resize cannot silently resume or change retained economy',async()=>{const r=await fakeRun(fs=>{fs.find(o=>o.state?.paused&&o.geometry.viewport[0]===RESIZED_VIEWPORT[0]).state.bank_milli.wood--;});assert.match(String(r.error),/deep-equal|bank_milli/);assert.equal(r.evidence.basicSmokePassed,false);});
test('fake canceled new match cannot silently reset tick',async()=>{const r=await fakeRun(fs=>{const i=fs.findIndex(o=>o.menu.page==='confirm');fs[i+1].state.tick=1;});assert.match(String(r.error),/Paused main menu advanced simulation/);assert.equal(r.evidence.basicSmokePassed,false);});
test('failed public stream including close-time abort remains fatal',async()=>{const r=await fakeRun(null,true);assert.match(String(r.error),/Browser errors during context close/);assert.equal(r.evidence.basicSmokePassed,false);assert.ok(r.evidence.error_count>0);});
