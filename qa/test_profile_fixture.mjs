// Inert tests only. Fake callbacks/data, no browser/network/resource probes.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {selectProfile,pointerClick,runQA,assertQueued,assertCompleted} from './browser_qa.mjs';

test('portrait dispatch uses touch; invalid input fails closed',async()=>{
  const calls=[];const page={touchscreen:{tap:async(...xy)=>calls.push(['touch',...xy])},mouse:{click:async(...xy)=>calls.push(['mouse',...xy])}};
  await pointerClick(page,'portrait',42,56);await assert.rejects(pointerClick(page,'unknown',0,0));
  assert.deepEqual(calls,[['touch',42,56]]);
  assert.deepEqual(selectProfile('portrait'),{name:'portrait',viewport:{width:390,height:844},hasTouch:true});
  let called=false;await assert.rejects(runQA({newContext:async()=>{called=true;}},'/unused','http://127.0.0.1:12345','desktop'));assert.equal(called,false);
});
test('failure persists truthful atomic evidence',async()=>{
  const dir=await mkdtemp(path.join(os.tmpdir(),'rts-economy-fixture-'));
  try{
    await assert.rejects(runQA({newContext:async()=>{throw new Error('fake-context-failure');}},dir,'http://127.0.0.1:12345','portrait'),/fake-context-failure/);
    const evidence=JSON.parse(await readFile(path.join(dir,'browser-evidence.json'),'utf8'));
    assert.equal(evidence.phase,'failed');assert.equal(evidence.failedDuringPhase,'starting');
    assert.equal(evidence.basicSmokePassed,false);assert.equal(evidence.economyLoopPassed,false);assert.equal(evidence.releaseQAPassed,false);
    assert.deepEqual(evidence.cases,[]);assert.deepEqual(await readdir(dir),['browser-evidence.json']);
  }finally{await rm(dir,{recursive:true,force:true});}
});
const initial={bank_milli:{food:150000,wood:200000},economy_scale:1000,population:6,capacity:10,trained:0,delivered:0};
const queued={...initial,bank_milli:{food:100000,wood:200000},population:7};
const completed={...queued,bank_milli:{food:110000,wood:200000},trained:1,delivered:10};
const villagers={...completed,selected:[1,2,3,4,5,79]};
test('exact debit, deposit, unit and reservation deltas pass',()=>{
  assertQueued(initial,queued);assertCompleted(initial,queued,completed,villagers);
});
test('wrong debit, uncredited cargo, missing newborn and leaked reservations reject',()=>{
  assert.throws(()=>assertQueued(initial,{...queued,bank_milli:{food:149000,wood:200000}}));
  for(const bad of [{...completed,bank_milli:{food:100000,wood:200000}},{...completed,population:8},{...completed,trained:0},{...completed,delivered:0}])assert.throws(()=>assertCompleted(initial,queued,bad,villagers));
  assert.throws(()=>assertCompleted(initial,queued,completed,{...villagers,selected:[1,2,3,4,5]}));
  assert.throws(()=>assertCompleted(initial,queued,completed,{...villagers,selected:[1,2,3,4,5,5]}));
});
test('only read-only bridge and ordinary touch; all existing host guard bounds retained',async()=>{
  const fixture=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');
  assert.equal((fixture.match(/page\.evaluate\(/g)||[]).length,1);
  assert.ok(fixture.includes('window.valleySnapshot();return window.valleyState;'));
  for(const forbidden of ['page.keyboard','dispatchEvent','valleyTouchCancel','_test_advance','window.valleyState='])assert.ok(!fixture.includes(forbidden));
  for(const phase of ['initial-state-asserted','training-queued-asserted','gather-command-issued','training-and-deposit-observed','newborn-and-reservation-asserted'])assert.ok(fixture.includes(`checkpoint('${phase}'`));
  const guard=await readFile(new URL('./run_host_browser.py',import.meta.url),'utf8');
  for(const setting of ['--property=MemoryMax=3G','--property=MemorySwapMax=0','--property=TasksMax=256','--property=CPUQuota=200%','--property=RuntimeMaxSec=100','--property=TimeoutStopSec=5','--property=KillMode=control-group'])assert.ok(guard.includes(setting));
  const host=await readFile(new URL('./host_main.mjs',import.meta.url),'utf8');assert.ok(host.includes('Math.min(90000,'));assert.ok(host.includes('chromiumSandbox:true'));
});
