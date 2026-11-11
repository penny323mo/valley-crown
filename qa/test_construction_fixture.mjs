// Synthetic unit data tests only, never evidence of actual gameplay.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {validateManifest,mapPoint,buttonByText,selectedSite,assertStoppedProgress,assertResumedProgress,runQA} from './browser_qa.mjs';

const manifest = {reviewed:true,build:'vc-123456789abc',source_commit:'a'.repeat(40),profile:'portrait',hud_schema:1,
  files_sha256:Object.fromEntries(['index.html','index.pck','index.wasm'].map(name => [name,'b'.repeat(64)]))};
function state(tick, progress, label, paused=false) {
  return {tick,paused,hud:{schema:1,selection_detail:label,selected_own:[{id:7,category:'building',kind:'house',built:false,progress}],buttons:[]}};
}

test('final reviewed identity is required and safe paths only', () => {
  validateManifest(manifest);
  assert.throws(() => validateManifest({...manifest,reviewed:false}));
  assert.throws(() => validateManifest({...manifest,build:null}));
  assert.throws(() => validateManifest({...manifest,files_sha256:{...manifest.files_sha256,'../bad':'b'.repeat(64)}}));
});
test('wrong profile cannot invoke any fake browser methods', async () => {
  let calls=0;
  await assert.rejects(runQA({newContext:async () => {calls++;}}, '/unused','http://127.0.0.1:12345','desktop'), /one portrait context/);
  assert.equal(calls,0);
});
test('logical points map to real canvas geometry and reject offscreen points', () => {
  assert.deepEqual(mapPoint([195,422],[390,844],{x:10,y:20,width:780,height:1688}),[400,864]);
  assert.throws(() => mapPoint([390,4],[390,844],{x:0,y:0,width:390,height:844}));
});
test('only a unique enabled clipped public button is actionable', () => {
  const s=state(1,0,'');
  s.hud.buttons=[{text:'停止',rect:[10,20,44,46],disabled:false}];
  assert.equal(buttonByText(s,/^停止$/).text,'停止');
  s.hud.buttons[0].disabled=true; assert.equal(buttonByText(s,/^停止$/),null);
  s.hud.buttons[0].disabled=false; s.hud.buttons.push({...s.hud.buttons[0]});
  assert.throws(() => buttonByText(s,/^停止$/));
});
test('stopped proof requires visible no-builder, stable progress and real ticks', () => {
  const before=state(100,0.1,'施工 10% · 無施工村民');
  assertStoppedProgress(before,state(120,0.1,'施工 10% · 無施工村民'),7);
  assert.throws(() => assertStoppedProgress(before,state(119,0.1,'無施工村民'),7));
  assert.throws(() => assertStoppedProgress(before,state(120,0.2,'無施工村民'),7));
  assert.throws(() => assertStoppedProgress(before,state(120,0.1,'已暫停',true),7));
});
test('resumed proof requires same site plus active text and increased progress', () => {
  const before=state(100,0.1,'無施工村民');
  assertResumedProgress(before,state(130,0.12,'建造中'),7);
  assert.throws(() => assertResumedProgress(before,state(130,0.1,'建造中'),7));
  assert.throws(() => assertResumedProgress(before,state(130,0.12,'村民移動到工地'),7));
  assert.equal(selectedSite(before,999),null);
});
test('fixture contains no arbitrary game state bridge or authority setter', async () => {
  const source=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');
  assert.equal((source.match(/page\.evaluate\(/g)||[]).length,1);
  assert.ok(source.includes('window.valleySnapshot(); return window.valleyState;'));
  for (const forbidden of ['_test_reset','_submit(','.valleyState =','scrollLeft =','scroll_horizontal =']) assert.ok(!source.includes(forbidden));
  assert.ok(source.includes("'Input.dispatchTouchEvent'"));
  assert.ok(source.includes('page.touchscreen.tap'));
  assert.ok(source.includes('70000'));
});
