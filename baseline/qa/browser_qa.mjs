// INERT preparation: runQA refuses the supplied unbound manifest. No main/launcher.
import assert from 'node:assert/strict';
import {readFile,writeFile,rename} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createNetworkDiagnostics} from './network_diagnostics.mjs';
import {assertPublicStreamCompletions} from './public_stream_cache_policy.mjs';

export async function runQA(browser,output,origin,profile) {
  const manifest=JSON.parse(await readFile(new URL('./scenario-manifest.json',import.meta.url),'utf8'));
  assert.equal(manifest.reviewed,true,'Comparison is not reviewed');
  assert.equal(manifest.bound,true,'Diagnostic export is not bound');
  assert.equal(manifest.execution_approved,true,'Execution remains disabled');
  assert.equal(manifest.diagnostic_only,true); assert.equal(profile,'portrait');
  for(const key of ['game_source_sha256','overlay_sha256','diagnostic_source_inventory_sha256','export_artifact_sha256','qa_inventory_sha256',
    'source_archive_sha256','import_manifest_sha256','export_manifest_sha256','source_chain_verification_sha256'])
    assert.match(manifest[key]??'',/^[0-9a-f]{64}$/,'Independent diagnostic source/export chain remains unbound: '+key);
  assert.match(origin,/^http:\/\/127\.0\.0\.1:\d+$/);
  const started=performance.now(),deadline=started+70000;
  const evidence={schema:'vc-paused-browser-v1',phase:'starting',profile,basicSmokePassed:false,releaseQAPassed:false,
    automatic_promotion:false,manifest,errors:[],error_count:0,screenshots:[],environment:{},reads:[],report:null,
    scope:'Paused tick-zero startup presentation; not normal gameplay FPS; no isolated method-time claim',
    source_identity_basis:'Reviewed independently verified diagnostic input/import/export/PCK chain; manifest pins are external provenance, not runtime measurements'};
  const addError=e=>{evidence.error_count++;if(evidence.errors.length<64)evidence.errors.push(e);};
  const network=createNetworkDiagnostics(()=>evidence.phase,addError); evidence.network=network.data;
  const persist=async()=>{await writeFile(`${output}/browser-evidence.json.tmp`,JSON.stringify(evidence,null,2));await rename(`${output}/browser-evidence.json.tmp`,`${output}/browser-evidence.json`);};
  const budget=cap=>{const ms=Math.min(cap,Math.floor(deadline-performance.now()));assert.ok(ms>0,'Original 70-second scenario limit');return ms;};
  const bounded=async(promise,cap=5000)=>{let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Original bounded read deadline')),budget(cap));})]);}finally{clearTimeout(timer);}};
  const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  let context,page,session;
  try {
    await persist();
    context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:1,hasTouch:true,serviceWorkers:'block'});
    page=await context.newPage();page.setDefaultTimeout(5000);
    page.on('pageerror',e=>addError({kind:'pageerror',text:String(e).slice(0,2000)}));
    page.on('console',m=>{if(m.type()==='error')addError({kind:'console',text:m.text().slice(0,2000)});});
    context.on('request',network.request);context.on('response',network.response);
    context.on('requestfinished',network.finished);context.on('requestfailed',network.failed);
    await page.route('**/*',route=>new URL(route.request().url()).origin===origin?route.continue():route.abort());
    // Actual executed command line, not just launch options. Unsupported remains unknown.
    session=await bounded(browser.newBrowserCDPSession());
    const passive=async(method)=>{try{return {status:'observed',value:await bounded(session.send(method))};}catch(e){return {status:'unknown',reason:String(e).slice(0,1000)};}};
    const [argv,system]=await Promise.all([passive('Browser.getBrowserCommandLine'),passive('SystemInfo.getInfo')]);
    evidence.environment={browser_version:browser.version(),executed_argv:argv,gpu:system.status==='observed'?{status:'observed',value:system.value.gpu}:system};
    await session.detach();session=null;
    evidence.phase='loading';await persist();
    await page.goto(`${origin}/index.html`,{waitUntil:'load',timeout:budget(25000)});
    await page.waitForFunction(()=>typeof window.valleyVisibility?.read==='function',null,{timeout:budget(15000),polling:100});
    // The engine performs its fixed 3 s warmup and >=6 s drawn-boundary window.
    // No browser polling, screenshots, CDP or input during this 11 s quiet wait.
    evidence.phase='quiet-window';await persist();
    assert.ok(budget(11000)===11000,'Not enough original budget for quiet window');
    await delay(11000);
    const readStarted=performance.now();
    const observed=await bounded(page.evaluate(()=>{
      const d=Object.getOwnPropertyDescriptor(window,'valleyVisibility');
      const bridge=window.valleyVisibility,report=bridge.read();
      const c=document.querySelector('canvas'),r=c?.getBoundingClientRect(),s=c?getComputedStyle(c):null;
      return {report,bridge_immutable:d?.writable===false&&d?.configurable===false&&Object.isFrozen(bridge)&&Object.keys(bridge).join(',')==='read'&&Object.isFrozen(report),geometry:r?{box:[r.x,r.y,r.width,r.height],viewport:[innerWidth,innerHeight],canvas_pixels:[c.width,c.height],display:s.display,visibility:s.visibility,opacity:Number(s.opacity)}:null};
    }));
    evidence.reads.push({duration_ms:performance.now()-readStarted});evidence.report=observed.report;evidence.observation=observed;
    const r=observed.report;
    assert.equal(observed.bridge_immutable,true);assert.equal(r.schema,'vc-paused-visibility-v1');
    assert.equal(r.phase,'completed','Fixed quiet window ended without a complete measurement');
    for(const key of ['game_source_sha256','overlay_sha256']) {
      assert.equal(typeof r[key],'string','Runtime FileAccess result missing: '+key);
      assert.equal(r.runtime_source_hash_status?.[key],r[key]===''?'unavailable':'observed');
      if(r[key]!=='') assert.equal(r[key],manifest[key],'Nonempty observed source hash differs: '+key);
    }
    assert.equal(r.build,manifest.build);assert.equal(r.diagnostic_only,true);assert.equal(r.normal_gameplay_fps,false);
    assert.deepEqual(r.begin.state,r.end.state);assert.deepEqual(r.end.state,r.current_state);assert.deepEqual(r.end.state.viewport,[390,844]);
    assert.equal(r.end.state.public.tick,0);assert.equal(r.end.state.paused,true);assert.equal(r.end.state.ai_enabled,true);
    assert.equal(r.end.state.test_mode,false);assert.equal(r.end.state.engine_time_scale,1);
    assert.equal(r.end.state.engine_max_fps,0);assert.equal(r.end.state.content_scale_factor,1);
    assert.ok(r.end.wall_usec-r.begin.wall_usec>=6000000);assert.ok(r.begin.wall_usec-r.first_draw_usec>=3000000);
    assert.ok(r.end.drawn_frames>r.begin.drawn_frames&&r.draw_samples>0&&r.draw_call_sum>0);
    assert.deepEqual(observed.geometry?.viewport,[390,844]);assert.deepEqual(observed.geometry?.box,[0,0,390,844]);
    assert.deepEqual(observed.geometry?.canvas_pixels,[390,844]);
    assert.notEqual(observed.geometry.display,'none');assert.equal(observed.geometry.visibility,'visible');assert.equal(observed.geometry.opacity,1);
    evidence.phase='capture-after-window';await persist();
    const png=await page.screenshot({path:`${output}/paused-startup.png`,timeout:budget(5000)});
    assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
    assert.equal(png.readUInt32BE(16),390);assert.equal(png.readUInt32BE(20),844);
    evidence.screenshots.push({name:'paused-startup.png',sha256:createHash('sha256').update(png).digest('hex'),bytes:png.length,genuine_browser_capture:true,viewport:[390,844],scope:'After measurement; stationary scene; pixel review required'});
    assert.equal(evidence.error_count,0,'All browser/network errors are fatal');
    await context.close();context=null;
    assert.equal(evidence.error_count,0,'Shutdown network errors remain fatal');
    assertPublicStreamCompletions(evidence.network.records,origin);
    budget(1);
    evidence.basicSmokePassed=true;evidence.phase='completed';
  } catch(error) {
    evidence.basicSmokePassed=false;evidence.failed_phase=evidence.phase;evidence.phase='failed';evidence.failure=String(error).slice(0,4000);throw error;
  } finally {
    if(session){try{await session.detach();}catch(e){addError({kind:'cdp-detach',text:String(e)});}}
    if(context){try{await context.close();}catch(e){addError({kind:'context-close',text:String(e)});}}
    if(evidence.error_count)evidence.basicSmokePassed=false;
    evidence.elapsed_ms=performance.now()-started;await persist();
  }
  return evidence;
}
