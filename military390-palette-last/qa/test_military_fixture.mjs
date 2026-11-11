// Pure inert tests. Run on the later hosted job, never locally.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {BUILDINGS,stripSwipe,assertHudRects,validateManifest,assertPalettePair} from './browser_qa.mjs';
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

const pairState=pair=>({hud:{action_scroll:{rect:[140,756,234,78],scroll_horizontal:pair*216},buttons:
 BUILDINGS.slice(pair*2,pair*2+2).map((name,i)=>({text:name+'\n木 100'+(['馬廄','工坊'].includes(name)?'\n需城防時代':''),in_action_scroll:true,disabled:['馬廄','工坊'].includes(name),rect:[140+i*108,756,100,70]}))}});
for(let pair=0;pair<4;pair++)assert.equal(assertPalettePair(pairState(pair),pair).length,2);
for(const mutate of [s=>{s.hud.buttons[0].rect[2]=99;},s=>{s.hud.buttons[0].rect[0]=141;},s=>{s.hud.buttons[0].rect[3]=69;},s=>{s.hud.buttons[0].disabled=false;},s=>{s.hud.buttons[0].text='馬廄\n木 100';},s=>{s.hud.action_scroll.scroll_horizontal=647;},s=>{s.hud.action_scroll.rect[2]=208;}]){
 const s=pairState(3);mutate(s);assert.throws(()=>assertPalettePair(s,3));
}
