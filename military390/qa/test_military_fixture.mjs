// Pure inert tests. Run on the later hosted job, never locally.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {BUILDINGS,stripSwipe,assertHudRects,validateManifest} from './browser_qa.mjs';
assert.equal(BUILDINGS.length,8);assert.equal(new Set(BUILDINGS).size,8);
const manifest=JSON.parse(await readFile(new URL('./scenario-manifest.json',import.meta.url),'utf8'));
if(manifest.reviewed)validateManifest(manifest);else assert.throws(()=>validateManifest(manifest));
assert.throws(()=>validateManifest({...manifest,scenario:'menu390'}));
const state={hud:{schema:2,viewport:[390,844],buttons:[{text:'指令',rect:[10,720,54,54]}],action_scroll:{rect:[130,720,246,62],scroll_horizontal:0}}};
assertHudRects(state,[390,844]);
const f=stripSwipe(state),b=stripSwipe(state,true);
assert.deepEqual(f.start,b.end);assert.deepEqual(f.end,b.start);assert.equal(f.start[0]-f.end[0],216);
assert.throws(()=>assertHudRects({...state,hud:{...state.hud,buttons:[...state.hud.buttons,{text:'停止',rect:[20,720,54,54]}]}},[390,844]));
assert.throws(()=>assertHudRects({...state,hud:{...state.hud,buttons:[{text:'關閉',rect:[10,10,54,54]}]}},[390,844]));
assert.throws(()=>stripSwipe({hud:{action_scroll:{rect:[0,0,100,50]}}}));
console.log('Military fixture inert contracts passed; no browser launched or visual acceptance claimed.');
