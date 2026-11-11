// Diagnostic rendered match: read observations, tap Start, and explicitly ACK
// the current presentation capture after actual PNG and metadata persistence.
// The separately bound GDScript overlay runs the exact verified ordinary policy.
import assert from 'node:assert/strict';
import {readFile,writeFile,rename} from 'node:fs/promises';
import {createNetworkDiagnostics} from './network_diagnostics.mjs';
import {mapPoint,validateCanvasGeometry,assertMenuControls} from './browser_qa.mjs';
import {menuButton,assertMenu} from './public_observation_assertions.mjs';
import {assertPublicStreamCompletions} from './public_stream_cache_policy.mjs';
import {persistAndAcknowledgeCapture,pngIdentity} from './capture_handshake.mjs';
export const REQUIRED=Object.freeze(['menu_started','cargo_collected','cargo_deposited','house_complete','barracks_complete','range_complete','spearman_produced','archer_produced','enemy_attack_observed','own_health_loss','enemy_health_loss','enemy_keep_damaged','normal_victory']);
export function validateRenderedManifest(m,p){
  assert.equal(m.reviewed,true);assert.equal(m.diagnostic_only,true);assert.equal(m.pending_actual_diagnostic_export,false);
  assert.equal(m.scenario,'rendered390');assert.equal(m.profile,'portrait');assert.deepEqual(m.viewport,[390,844]);assert.equal(m.hud_schema,2);
  assert.equal(p.reviewed_for_execution,true);assert.equal(p.name,'ordinary-rendered-450-ack-v2');assert.equal(p.diagnostic_only,true);assert.equal(p.capture_ack_capability,'current_monotonic_id_only_after_png_and_metadata_persistence');
  assert.equal(m.build,p.product_build);assert.equal(m.source_commit,p.product_source);
  assert.deepEqual([p.fixture_seconds,p.scenario_seconds,p.node_seconds,p.service_seconds,p.outer_seconds,p.snapshot_read_seconds],[440,450,460,470,475,5]);
  for(const f of ['index.html','index.pck','index.wasm'])assert.match(m.files_sha256[f],/^[0-9a-f]{64}$/);
  assert.deepEqual(m.diagnostic_overlay,p.diagnostic_overlay);
  return m;
}
export function validateFinal(o){
  assert.equal(o.schema,'vc-rendered-match-observation-v1');assert.equal(o.finished,true);assert.equal(o.diagnostic_overlay,true);
  assert.equal(o.runtime.ai_enabled,true);assert.equal(o.runtime.test_mode,false);assert.equal(o.runtime.time_scale,1);
  assert.equal(o.runtime.end_reason,'keep_destroyed');assert.equal(o.snapshot.game_over,true);assert.equal(o.snapshot.outcome,'victory');
  assert.equal(o.runtime.end_title,'王旗再起');assert.equal(o.report.passed,true);
  assert.equal(o.report.policy_version,'ordinary-rendered-440-ack-v2');
  for(const key of REQUIRED)assert.ok(Object.hasOwn(o.phases,key),'Missing normal phase '+key);
  return true;
}
export async function runQA(browser,outputDirectory,origin,profile){
  assert.equal(profile,'portrait');assert.match(origin,/^http:\/\/127\.0\.0\.1:\d+$/);
  const m=validateRenderedManifest(JSON.parse(await readFile(new URL('./scenario-manifest.json',import.meta.url),'utf8')),JSON.parse(await readFile(new URL('./rendered-profile.json',import.meta.url),'utf8')));
  const started=Date.now(),viewport=[390,844];
  const evidence={build:m.build,source_commit:m.source_commit,files_sha256:m.files_sha256,diagnostic_overlay:m.diagnostic_overlay,diagnostic_only:true,profile,scenario:'rendered390',viewport,
    basicSmokePassed:false,releaseQAPassed:false,visualAcceptancePassed:false,phase:'starting',checkpoints:[],screenshots:[],errors:[],error_count:0,read_timings:[],
    input:'One ordinary emulated touch on menu Start; then automated GDScript ordinary order/build/train policy, not manual or physical iPhone gameplay',
    observation:'Read-only valleyMenuSnapshot, valleySnapshot, valleyRenderedReport and canvas DOM geometry; a separately named current-ID ACK advances presentation only after PNG persistence. No gameplay setter, authority mutation, pause, AI or speed override.',
    required_visual_review:{status:'pending-pixel-review',checks:['genuine menu','earned economy and construction progress','paid spearmen and archers','real AI fight and changing HP','ranged projectile direction across genuine burst frames','enemy keep damage','normal victory panel','390px phone-scale readability']},
    not_run:['physical iPhone Safari or touch acceptance','advanced cavalry/ram fullmatch progression','final replacement weapon/grip art','production-release Web bytes: this is a separately bound diagnostic export']};
  const addError=e=>{evidence.error_count++;if(evidence.errors.length<64)evidence.errors.push(e);};
  const network=createNetworkDiagnostics(()=>evidence.phase,addError);evidence.network=network.data;
  const persist=async()=>{await writeFile(`${outputDirectory}/browser-evidence.json.tmp`,JSON.stringify(evidence,null,2));await rename(`${outputDirectory}/browser-evidence.json.tmp`,`${outputDirectory}/browser-evidence.json`);};
  const withinBudget=()=>assert.ok(Date.now()-started<450000,'Distinct450-second rendered scenario budget exhausted');
  const delay=ms=>new Promise(r=>setTimeout(r,ms));
  let context,page,canvasBox=null,lastCapture=0,reads=0;
  try{
    context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:1,hasTouch:true,serviceWorkers:'block'});
    page=await context.newPage();page.setDefaultTimeout(5000);
    page.on('pageerror',e=>addError({kind:'pageerror',text:String(e).slice(0,2000)}));page.on('console',x=>{if(x.type()==='error')addError({kind:'console',text:x.text().slice(0,2000)});});
    context.on('request',network.request);context.on('response',network.response);context.on('requestfinished',network.finished);context.on('requestfailed',network.failed);
    await page.route('**/*',r=>new URL(r.request().url()).origin===origin?r.continue():r.abort());
    await page.goto(`${origin}/index.html?qa`,{waitUntil:'load',timeout:25000});
    await page.waitForFunction(()=>typeof window.valleyMenuSnapshot==='function'&&typeof window.valleyRenderedReport==='function'&&typeof window.valleyRenderedCaptureAck==='function',null,{timeout:20000});
    const observe=async()=>{
      withinBudget();assert.ok(++reads<=2400,'Bounded read evidence exhausted');const begin=Date.now();let timer;
      const pending=page.evaluate(()=>{
        window.valleyMenuSnapshot();const game_bridge=typeof window.valleySnapshot==='function';if(game_bridge)window.valleySnapshot();window.valleyRenderedReport();
        const canvas=document.querySelector('canvas');let geometry=null;
        if(canvas){const r=canvas.getBoundingClientRect(),s=getComputedStyle(canvas);geometry={box:{x:r.x,y:r.y,width:r.width,height:r.height},viewport:[innerWidth,innerHeight],display:s.display,visibility:s.visibility,opacity:Number(s.opacity)};}
        return {menu:{...window.valleyMenuState,game_bridge},state:game_bridge?window.valleyState:null,diagnostic:window.valleyRenderedState,geometry};
      });
      let o;try{o=await Promise.race([pending,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Canvas geometry/snapshot read exceeded5000ms')),5000);})]);}finally{clearTimeout(timer);}
      canvasBox=validateCanvasGeometry(o.geometry,viewport,canvasBox);
      if(o.state){assert.equal(o.state.build,m.build);assert.equal(o.state.hud.schema,2);assert.deepEqual(o.state.hud.viewport,viewport);}
      if(o.diagnostic.snapshot){assert.equal(o.diagnostic.runtime.ai_enabled,true);assert.equal(o.diagnostic.runtime.test_mode,false);assert.equal(o.diagnostic.runtime.time_scale,1);assert.equal(o.diagnostic.snapshot.paused,false,'Normal match unexpectedly paused');}
      evidence.last_observation=o;evidence.reads=reads;evidence.elapsed_ms=Date.now()-started;
      if(evidence.read_timings.length<96)evidence.read_timings.push({elapsed_ms:evidence.elapsed_ms,duration_ms:Date.now()-begin});
      withinBudget();return o;
    };
    const screenshot=async name=>{
      withinBudget();assert.ok(evidence.screenshots.length<48,'Screenshot evidence limit');
      return page.screenshot({path:`${outputDirectory}/${name}`,timeout:5000});
    };
    const acknowledge=async id=>{
      withinBudget();let timer;
      const pending=page.evaluate(captureId=>{
        window.valleyRenderedCaptureAck(captureId);
        return window.valleyRenderedAckResult;
      },id);
      try{return await Promise.race([pending,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Presentation capture ACK exceeded original5000ms operation cap; outcome uncertain, no retry')),5000);})]);}
      finally{clearTimeout(timer);}
    };
    const shot=async(label,o)=>{
      assert.match(label,/^[a-z0-9_-]+$/);const name=`rendered390-${label}.png`;
      const result=await persistAndAcknowledgeCapture(o,{
        screenshot:()=>screenshot(name),readStored:()=>readFile(`${outputDirectory}/${name}`),observe,
        persist:async record=>{evidence.screenshots.push({name,phase:label,elapsed_ms:Date.now()-started,viewport:[...viewport],genuine_browser_capture:true,...record});await persist();},
        acknowledge
      });
      evidence.last_capture_ack=result.ack;await persist();return result;
    };
    let current=await observe();assertMenu(current.menu,{match_exists:false,game_bridge:false});assertMenuControls(current.menu,viewport,['StartMatchButton','HelpButton']);
    evidence.phase='menu';
    const menuName='rendered390-00-menu.png',menuBytes=await screenshot(menuName),menuStored=await readFile(`${outputDirectory}/${menuName}`);
    assert.deepEqual(menuStored,menuBytes);const menuAfter=await observe();assertMenu(menuAfter.menu,{match_exists:false,game_bridge:false});
    evidence.screenshots.push({name:menuName,phase:'00-menu',elapsed_ms:Date.now()-started,viewport:[...viewport],genuine_browser_capture:true,stored_png:pngIdentity(menuStored),pre_drawn_frame:current.diagnostic.drawn_frame,post_drawn_frame:menuAfter.diagnostic.drawn_frame});await persist();
    const rect=menuButton(current.menu,'StartMatchButton',viewport).rect;
    await page.touchscreen.tap(...mapPoint([rect[0]+rect[2]/2,rect[1]+rect[3]/2],viewport,canvasBox));
    evidence.menu_start_input={type:'ordinary-touch-tap',elapsed_ms:Date.now()-started};
    const seenPhases=new Set();
    for(;;){
      current=await observe();const d=current.diagnostic;
      for(const [phase,tick] of Object.entries(d.phases??{}))if(!seenPhases.has(phase)){seenPhases.add(phase);evidence.checkpoints.push({phase,event_tick:tick,elapsed_ms:Date.now()-started,snapshot:d.snapshot});}
      if(d.capture?.awaiting_ack&&d.capture.id>lastCapture){assert.equal(d.capture.id,lastCapture+1,'Capture ID skipped');evidence.phase=d.capture.label;await shot(`${String(d.capture.id).padStart(2,'0')}-${d.capture.label}`,current);lastCapture=d.capture.id;}
      if(d.finished){
        await writeFile(`${outputDirectory}/full-match-report.json`,JSON.stringify(d.report??d,null,2));
        validateFinal(d);
        if(!d.capture_queue_remaining&&d.capture.label==='normal_victory'&&d.capture.remaining===0&&!d.capture.awaiting_ack&&d.acknowledged_id===d.capture.id&&lastCapture===d.capture.id){
          evidence.phase='victory';break;
        }
      }
      assert.equal(evidence.error_count,0,'Browser errors recorded during normal match');await persist();await delay(250);
    }
    for(const label of REQUIRED)assert.ok(evidence.screenshots.some(s=>s.phase.endsWith('-'+label)),'Missing genuine phase capture '+label);
    evidence.phase='closing-context';await context.close();context=null;
    assert.equal(evidence.error_count,0,'Browser errors during context close');assertPublicStreamCompletions(evidence.network.records,origin);
    evidence.basicSmokePassed=true;evidence.phase='completed';await persist();
  }catch(error){
    evidence.failure=String(error);evidence.failedDuringPhase=evidence.phase;evidence.phase='failed';await persist();
    if(page&&!page.isClosed()&&Date.now()-started<448000){try{await page.screenshot({path:`${outputDirectory}/rendered390-failure.png`,timeout:1500});evidence.failure_screenshot='written';}catch(e){evidence.failure_screenshot=String(e).slice(0,500);}}
    throw error;
  }finally{
    if(context){try{await context.close();}catch(e){addError({kind:'context-close',text:String(e).slice(0,1000)});}}
    if(evidence.error_count)evidence.basicSmokePassed=false;await persist();
  }
  return evidence;
}
