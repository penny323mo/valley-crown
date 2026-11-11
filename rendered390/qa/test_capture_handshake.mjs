// Synthetic sequencing tests only, not Godot/browser runtime acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {currentCaptureId,persistAndAcknowledgeCapture,pngIdentity} from './capture_handshake.mjs';
const png=Buffer.from([137,80,78,71,13,10,26,10,0,1,2,3]);
const view=(tick=100,drawn=60)=>({diagnostic:{capture:{id:1,awaiting_ack:true,label:'barracks_complete',event_tick:95,remaining:0},acknowledged_id:0,snapshot:{tick},drawn_frame:drawn,camera:{focus:[-25,0,24],zoom:30},current_public_records:[{id:5,hp:60}]},state:{hud:{selection_detail:'生命60'}}});
const defer=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
function fixture(change={}){
 const before=view(),calls=[];let record;
 const ops={screenshot:async()=>{calls.push('png');return png;},readStored:async()=>{calls.push('read-png');return Buffer.from(png);},observe:async()=>{calls.push('post-read');return view(120,80);},persist:async r=>{calls.push('persist-metadata');record=r;},acknowledge:async id=>{calls.push(['ack',id]);return {accepted:true,current_id:id,acknowledged_id:id};},...change};
 return {before,ops,calls,get record(){return record;}};
}
test('delayed PNG and metadata cannot ACK early; pre/post interval is actual observation interval',async()=>{
 const screenshot=defer(),entered=defer(),metadata=defer(),metadataEntered=defer();let simTick=100,simDrawn=60,acks=0,record;
 const before=view(simTick,simDrawn);
 const task=persistAndAcknowledgeCapture(before,{
  screenshot:async()=>{entered.resolve();return screenshot.promise;},readStored:async()=>png,
  observe:async()=>view(simTick,simDrawn),persist:async r=>{record=r;metadataEntered.resolve();await metadata.promise;},
  acknowledge:async id=>{acks++;return {accepted:true,current_id:id,acknowledged_id:id};}
 });
 await entered.promise;simTick+=200;simDrawn+=180;assert.equal(acks,0);assert.equal(before.diagnostic.capture.id,1);
 screenshot.resolve(png);await metadataEntered.promise;assert.equal(acks,0);simTick+=100;simDrawn+=120;
 metadata.resolve();const out=await task;assert.equal(acks,1);assert.equal(out.record,record);
 assert.equal(record.pre_capture_tick,100);assert.equal(record.post_capture_tick,300);assert.equal(record.pre_drawn_frame,60);assert.equal(record.post_drawn_frame,240);
 assert.match(record.tick_label,/no exact simulation tick/);assert.deepEqual(record.stored_png,pngIdentity(png));
});
test('exact PNG and metadata persistence precede the only ACK',async()=>{
 const f=fixture();const r=await persistAndAcknowledgeCapture(f.before,f.ops);
 assert.deepEqual(f.calls,['png','read-png','post-read','persist-metadata',['ack',1]]);assert.equal(r.ack.accepted,true);
});
test('failed screenshot, file read, corrupt or mismatched PNG, post-read or metadata produces no ACK',async()=>{
 const failures=[{screenshot:async()=>{throw Error('PNG timeout');}},{readStored:async()=>{throw Error('disk failure');}},{readStored:async()=>Buffer.from('bad')},{readStored:async()=>Buffer.concat([png,Buffer.from([9])])},{observe:async()=>{throw Error('post read timeout');}},{persist:async()=>{throw Error('metadata persistence failed');}}];
 for(const change of failures){let acks=0;const f=fixture({...change,acknowledge:async()=>{acks++;}});await assert.rejects(persistAndAcknowledgeCapture(f.before,f.ops));assert.equal(acks,0);}
});
test('duplicate, out-of-order and foreign IDs or changed camera cannot be acknowledged by stored-frame sequence',async()=>{
 for(const mutate of [o=>o.diagnostic.capture.awaiting_ack=false,o=>o.diagnostic.acknowledged_id=1,o=>o.diagnostic.capture.id=2,o=>o.diagnostic.capture.id=999,o=>o.diagnostic.capture.id='1',o=>o.diagnostic.capture.id=NaN]){
  const bad=view();mutate(bad);assert.throws(()=>currentCaptureId(bad));
 }
 for(const mutate of [o=>o.diagnostic.capture.id=2,o=>o.diagnostic.capture.id=999,o=>o.diagnostic.capture.label='other',o=>o.diagnostic.camera.zoom=15,o=>o.diagnostic.snapshot.tick=99,o=>o.diagnostic.drawn_frame=59]){
  let acks=0;const after=view(120,80);mutate(after);const f=fixture({observe:async()=>after,acknowledge:async()=>{acks++;}});await assert.rejects(persistAndAcknowledgeCapture(f.before,f.ops));assert.equal(acks,0);
 }
});
test('rejected, foreign and uncertain ACK outcomes fail after one call and are never retried',async()=>{
 for(const outcome of [{accepted:false,current_id:1,acknowledged_id:0},{accepted:true,current_id:2,acknowledged_id:2},new Error('ACK deadline uncertain')]){
  let calls=0;const f=fixture({acknowledge:async()=>{calls++;if(outcome instanceof Error)throw outcome;return outcome;}});
  await assert.rejects(persistAndAcknowledgeCapture(f.before,f.ops));assert.equal(calls,1);
 }
});
