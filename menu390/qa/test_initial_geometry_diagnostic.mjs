import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {collectInitialGeometry} from './initial_geometry_diagnostic.mjs';
const clipped=()=>assert.fail('Menu control clipped/offscreen: StartMatchButton');
async function fixture({settle=Infinity,error=null,readTime=10}={}) {
 let time=0,count=0;const rows=[],deadlines=[],result={ready:false};
 await collectInitialGeometry({now:()=>time,observe:async deadline=>{deadlines.push(deadline);time+=readTime;return {menu:{buttons:[],n:++count},geometry:{}};},validate:o=>{if(error)throw error;if(o.menu.n<settle)clipped();},delay:async ms=>{assert.ok(ms>=0&&ms<=160);time+=ms;},record:async r=>rows.push(r),result});
 return {time,count,rows,deadlines,result};
}
test('settling only reobserves read-only geometry with one shared5-second deadline',async()=>{const f=await fixture({settle:3});assert.equal(f.count,3);assert.equal(f.result.ready,true);assert.deepEqual(f.deadlines,[5000,5000,5000]);assert.equal(f.rows[0].error,'Menu control clipped/offscreen: StartMatchButton');assert.equal(f.rows[2].error,null);});
test('persistent empty geometry stops within5seconds and at most32observations',async()=>{const f=await fixture();assert.equal(f.result.ready,false);assert.ok(f.count<=32&&f.time<=5000);});
test('already valid first geometry requires no delay/retry',async()=>{const f=await fixture({settle:1});assert.equal(f.count,1);assert.equal(f.time,10);});
test('wrong menu identity and unexpected errors stay fatal',async()=>{await assert.rejects(fixture({error:new assert.AssertionError({message:'Wrong public menu button order/count'})}),/Wrong public/);await assert.rejects(fixture({error:new Error('network failure')}),/Unexpected non-geometry/);});
test('a read finishing after the shared deadline cannot become readiness success',async()=>{await assert.rejects(fixture({settle:1,readTime:5001}),/deadline exhausted/);});
test('diagnostic stops before any gameplay input and preserves fatal close/network gates',async()=>{const s=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');assert.ok(s.includes('Math.min(5000,absoluteDeadline-readStarted)'));assert.ok(s.includes("exceeded5000ms')),readBudget)"));assert.ok(s.indexOf("throw new Error('DIAGNOSTIC_ONLY:")<s.indexOf('let current=await observe();requireHome(current);'));assert.ok(s.includes('assertPublicStreamCompletions(evidence.network.records,origin)'));assert.ok(s.includes('Browser errors during context close'));assert.ok(s.includes('basicSmokePassed:false'));});
