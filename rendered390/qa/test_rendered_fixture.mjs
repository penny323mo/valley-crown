import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {REQUIRED,validateRenderedManifest,validateFinal} from './browser_rendered.mjs';
const overlay={'full_rendered_match.gd':'a'.repeat(64),'full_rendered_match.tscn':'b'.repeat(64)};
const profile={reviewed_for_execution:true,name:'ordinary-rendered-450-ack-v2',diagnostic_only:true,capture_ack_capability:'current_monotonic_id_only_after_png_and_metadata_persistence',product_build:'vc-79ebcaef19e3',product_source:'ce2ea3d2513bd79cf62cf5c651abe3c47aad8513',fixture_seconds:440,scenario_seconds:450,node_seconds:460,service_seconds:470,outer_seconds:475,snapshot_read_seconds:5,diagnostic_overlay:overlay};
const manifest={reviewed:true,diagnostic_only:true,pending_actual_diagnostic_export:false,scenario:'rendered390',profile:'portrait',viewport:[390,844],hud_schema:2,build:profile.product_build,source_commit:profile.product_source,files_sha256:Object.fromEntries(['index.html','index.pck','index.wasm'].map(n=>[n,'c'.repeat(64)])),diagnostic_overlay:overlay};
const final={schema:'vc-rendered-match-observation-v1',finished:true,diagnostic_overlay:true,runtime:{ai_enabled:true,test_mode:false,time_scale:1,end_reason:'keep_destroyed',end_title:'王旗再起'},snapshot:{game_over:true,outcome:'victory'},report:{passed:true,policy_version:'ordinary-rendered-440-ack-v2'},phases:Object.fromEntries(REQUIRED.map((p,i)=>[p,i]))};
test('new diagnostic provenance and explicit time profile are required',()=>{
 assert.equal(validateRenderedManifest(manifest,profile),manifest);
 for(const change of [{reviewed:false},{diagnostic_only:false},{pending_actual_diagnostic_export:true},{scenario:'menu390'},{profile:'desktop'},{viewport:[844,390]},{build:'vc-000000000000'},{diagnostic_overlay:{}}])assert.throws(()=>validateRenderedManifest({...manifest,...change},profile));
 for(const field of ['fixture_seconds','scenario_seconds','node_seconds','service_seconds','outer_seconds','snapshot_read_seconds'])assert.throws(()=>validateRenderedManifest(manifest,{...profile,[field]:profile[field]+1}));
 assert.throws(()=>validateRenderedManifest(manifest,{...profile,reviewed_for_execution:false}));
});
test('all original thirteen natural phases and authentic victory contract required',()=>{
 assert.equal(validateFinal(final),true);
 for(const phase of REQUIRED){const bad=structuredClone(final);delete bad.phases[phase];assert.throws(()=>validateFinal(bad));}
 for(const [key,value] of [['ai_enabled',false],['test_mode',true],['time_scale',3],['end_reason','surrender'],['end_title','enemy surrendered']]){const bad=structuredClone(final);bad.runtime[key]=value;assert.throws(()=>validateFinal(bad));}
 for(const field of ['finished','diagnostic_overlay'])assert.throws(()=>validateFinal({...final,[field]:false}));
 const bad=structuredClone(final);bad.snapshot.outcome='defeat';assert.throws(()=>validateFinal(bad));
});
test('one read-only evaluator plus explicit scoped ACK retain hard failures',async()=>{
 const s=await readFile(new URL('./browser_rendered.mjs',import.meta.url),'utf8');
 assert.equal((s.match(/page\.evaluate\(/g)||[]).length,2);
 for(const v of ['window.valleyMenuSnapshot();','window.valleySnapshot();','window.valleyRenderedReport();','exceeded5000ms','timeout:1500','450000','page.screenshot','assertPublicStreamCompletions','Browser errors during context close','serviceWorkers:\'block\''])assert.ok(s.includes(v),v);
 for(const v of ['dispatchEvent(','_submit(','.evaluateHandle(','Engine.time_scale =','setViewportSize(','_tick('])assert.ok(!s.includes(v),v);
});
