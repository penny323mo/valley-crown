// Pure sequencing plus injected I/O. This explicitly acknowledges presentation
// only after the exact PNG bytes and their pre/post observations are persisted.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const PNG=Uint8Array.from([137,80,78,71,13,10,26,10]);
export function currentCaptureId(o){
  const c=o?.diagnostic?.capture;
  assert.equal(c?.awaiting_ack,true,'Capture is not awaiting persistence');
  assert.ok(Number.isInteger(c.id)&&c.id>0&&c.id<=2147483647,'Invalid capture ID');
  assert.equal(o.diagnostic.acknowledged_id,c.id-1,'Nonconsecutive capture ID');
  return c.id;
}
export function pngIdentity(bytes){
  assert.ok(bytes instanceof Uint8Array&&bytes.length>=8&&bytes.length<=8*1024*1024,'Invalid bounded stored PNG');
  assert.deepEqual([...bytes.slice(0,8)],[...PNG],'Stored frame is not PNG');
  return {bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')};
}
export async function persistAndAcknowledgeCapture(before,ops){
  const id=currentCaptureId(before),requested=structuredClone(before.diagnostic.capture);
  const screenshotBytes=await ops.screenshot();
  const savedBytes=await ops.readStored();
  const stored=pngIdentity(savedBytes);
  assert.deepEqual(savedBytes,screenshotBytes,'Stored file differs from returned actual screenshot');
  const after=await ops.observe();
  assert.equal(currentCaptureId(after),id,'Capture changed before successful persistence');
  assert.equal(after.diagnostic.capture.label,requested.label,'Capture phase changed before persistence');
  assert.deepEqual(after.diagnostic.camera,before.diagnostic.camera,'Camera moved during unacknowledged capture');
  const pre=before.diagnostic,post=after.diagnostic;
  assert.ok(Number.isInteger(pre.snapshot.tick)&&post.snapshot.tick>=pre.snapshot.tick,'Capture tick interval reversed');
  assert.ok(Number.isInteger(pre.drawn_frame)&&post.drawn_frame>=pre.drawn_frame,'Rendered frame interval reversed');
  const record={capture_id:id,capture_request:requested,event_tick:requested.event_tick,
    pre_capture_tick:pre.snapshot.tick,post_capture_tick:post.snapshot.tick,
    pre_drawn_frame:pre.drawn_frame,post_drawn_frame:post.drawn_frame,
    tick_label:'Actual stored PNG occurred between these observations; no exact simulation tick is claimed',
    camera:pre.camera,pre_public_records:pre.current_public_records??[],post_public_records:post.current_public_records??[],
    pre_selection_detail:before.state?.hud.selection_detail??null,post_selection_detail:after.state?.hud.selection_detail??null,
    stored_png:stored};
  await ops.persist(record); // File and evidence must both succeed before ACK.
  const ack=await ops.acknowledge(id); // Never retried if outcome is uncertain.
  assert.equal(ack?.accepted,true,'Current persisted capture acknowledgment rejected');
  assert.equal(ack.current_id,id);assert.equal(ack.acknowledged_id,id);
  return {record,after,ack};
}
