import test from 'node:test';
import assert from 'node:assert/strict';
import {menuButton,assertMenu,assertCamera,assertSameCamera,assertPausedMatch,assertFrozenMatch,contextResource,cargo,assertDirectGather,projectedMovement,menuSwipePoints} from './public_observation_assertions.mjs';
const viewport=[390,844];
const state=()=>({tick:20,paused:false,game_over:false,selected:[7],touch_mode:false,build_mode:'',own_pending_commands:0,
 bank_milli:{food:150000,wood:200000},economy_scale:1000,population:6,capacity:10,delivered:0,built:0,trained:0,
 hud:{schema:2,viewport,selection_detail:'待命 · 守備',camera:{focus:[-15,0,20],zoom:25},
 own_targets:[{id:7,kind:'villager',screen:[150,300]}],context_targets:[{id:40,category:'resource',kind:'oak',team:-1,screen:[190,320]}],ground_points:[[100,400]],buttons:[]}});
const gathering=()=>{const s=state();s.tick=40;s.hud.selection_detail='採集 · 負重 1 / 10';s.hud.own_targets[0].screen=[175,320];return s;};
test('menu requires exact lifecycle and full clipped public target',()=>{
 const m={visible:true,page:'home',match_exists:false,game_bridge:false,buttons:[{id:'StartMatchButton',text:'開始戰役',rect:[10,180,200,48]}]};
 assertMenu(m);menuButton(m,'StartMatchButton',viewport);
 for(const mutate of [s=>s.visible=false,s=>s.game_bridge=true,s=>s.match_exists=true,s=>s.page='help']) {const c=structuredClone(m);mutate(c);assert.throws(()=>assertMenu(c));}
 for(const mutate of [s=>s.buttons[0].rect[3]=47,s=>s.buttons[0].rect[0]=-1,s=>s.buttons[0].rect[2]=500,s=>s.buttons[0].rect[1]=NaN,s=>s.buttons.push({...s.buttons[0]})]){const c=structuredClone(m);mutate(c);assert.throws(()=>menuButton(c,'StartMatchButton',viewport));}
});
test('camera witness rejects unknown telemetry and camera motion',()=>{
 const a=state();assertCamera(a.hud.camera);assertSameCamera(a,state());
 for(const mutate of [s=>s.hud.camera.focus[0]++,s=>s.hud.camera.zoom++,s=>s.hud.camera=null]){const b=state();mutate(b);assert.throws(()=>assertSameCamera(a,b));}
});
test('menu pause and retain cannot advance ticks, queue commands, charge or change selection',()=>{
 const a=state(),p=state();p.paused=true;p.tick=21;assertPausedMatch(a,p);assertFrozenMatch(p,structuredClone(p));
 for(const mutate of [s=>s.paused=false,s=>s.own_pending_commands=1,s=>s.selected=[],s=>s.bank_milli.wood--,s=>s.hud.camera.zoom++]){const b=structuredClone(p);mutate(b);assert.throws(()=>assertPausedMatch(a,b));}
 for(const mutate of [s=>s.tick++,s=>s.bank_milli.wood--,s=>s.selected=[],s=>s.touch_mode=true,s=>s.build_mode='house']){const b=structuredClone(p);mutate(b);assert.throws(()=>assertFrozenMatch(p,b));}
});
test('resource chooser sees only finite currently public pine, oak, berry projections',()=>{
 const a=state();assert.equal(contextResource(a,7).id,40);
 for(const mutate of [s=>s.hud.context_targets=[],s=>s.hud.context_targets[0].category='unit',s=>s.hud.context_targets[0].kind='hidden',s=>s.hud.context_targets[0].screen=[-1,20],s=>s.hud.own_targets=[],s=>s.hud.ground_points=Array(10).fill([10,10])]){const b=state();mutate(b);assert.throws(()=>contextResource(b,7));}
 const b=state();b.hud.context_targets.push({id:99,category:'resource',kind:'berry',screen:[151,300]});assert.equal(contextResource(b,7).id,99);
});
test('gather witness requires real cargo increment, advanced tick, selected villager and stable camera',()=>{
 const a=state(),b=gathering();assertDirectGather(a,b,7);assert.equal(cargo(b),1);assert.ok(projectedMovement(a,b,7));
 for(const mutate of [s=>s.hud.selection_detail='採集',s=>s.hud.selection_detail='採集 · 負重 0 / 10',s=>s.hud.selection_detail='移動 · 負重 1 / 10',s=>s.own_pending_commands=1,s=>s.tick=20,s=>s.selected=[8],s=>s.touch_mode=true,s=>s.bank_milli.wood++,s=>s.hud.camera.focus[0]++]){const c=gathering();mutate(c);assert.throws(()=>assertDirectGather(a,c,7));}
 assert.equal(projectedMovement(a,state(),7),false);
});
test('menu swipe endpoints must originate at actual visible menu controls',()=>{
 const a=state();a.hud.buttons=[{text:'關閉',rect:[280,100,60,46],disabled:false},{text:'音效：關',rect:[20,290,320,46],disabled:false}];
 assert.deepEqual(menuSwipePoints(a),{start:[180,313],end:[310,123]});
 for(const mutate of [s=>s.hud.buttons[0].text='hidden',s=>s.hud.buttons[1].rect[1]=140,s=>s.hud.buttons[1].disabled=true,s=>s.hud.buttons[0].rect[2]=0]){const b=structuredClone(a);mutate(b);assert.throws(()=>menuSwipePoints(b));}
});
