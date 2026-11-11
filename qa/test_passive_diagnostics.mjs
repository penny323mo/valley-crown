// Fake emitters/requests only. No HTTP listener, sockets, browser or host probes.
import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {readFile} from 'node:fs/promises';
import {createNetworkDiagnostics,MAX_REQUESTS} from './network_diagnostics.mjs';
import {createServerDiagnostics} from './server_diagnostics.mjs';

function request(url='http://127.0.0.1:1234/index.pck?private=omitted') {
  return {url:() => url,method:() => 'GET',resourceType:() => 'fetch',failure:() => ({errorText:'net::ERR_ABORTED'})};
}
test('stable request ID and safe metadata track response and finish by phase', () => {
  let time=100, phase='loading'; const errors=[];
  const trace=createNetworkDiagnostics(() => phase,e => errors.push(e),() => time);
  const req=request(); trace.request(req); time=110;
  trace.response({request:() => req,status:() => 200,headers:() => ({'content-type':'application/octet-stream','content-length':'12345','set-cookie':'secret','authorization':'secret','x-rts-request-id':'s0001'})});
  phase='game-ready'; time=150; trace.finished(req);
  const record=trace.data.records[0];
  assert.equal(record.id,'r0001'); assert.equal(trace.data.records.length,1);
  assert.equal(record.url,'http://127.0.0.1:1234/index.pck');
  assert.deepEqual(record.started,{elapsed_ms:0,phase:'loading'});
  assert.deepEqual(record.finished,{elapsed_ms:50,phase:'game-ready'});
  assert.equal(record.response.status,200); assert.equal(record.response.headers['x-rts-request-id'],'s0001');
  assert.ok(!JSON.stringify(record).includes('secret')); assert.equal(errors.length,0);
});
test('an abort after context closing remains fatal without a whitelist', () => {
  const errors=[]; const trace=createNetworkDiagnostics(() => 'closing-context',e => errors.push(e));
  const req=request(); trace.request(req); trace.failed(req);
  assert.equal(trace.data.records[0].failed.error,'net::ERR_ABORTED');
  assert.equal(trace.data.records[0].failed.phase,'closing-context');
  assert.equal(errors[0].kind,'requestfailed');
});
test('network record cap is hard and overflow is fatal', () => {
  const errors=[]; const trace=createNetworkDiagnostics(() => 'load',e => errors.push(e));
  for (let i=0;i<MAX_REQUESTS+50;i++) trace.request(request());
  assert.equal(trace.data.records.length,MAX_REQUESTS); assert.equal(trace.data.overflow,true);
  assert.equal(errors.filter(e => e.kind==='request-log-overflow').length,1);
});
function pair() {
  const req=new EventEmitter(); req.url='/index.pck?private=omitted'; req.method='GET';
  const res=new EventEmitter(); res.statusCode=200; res.writableFinished=false; res.setHeader=(name,value) => {res.header=[name,value];};
  return [req,res];
}
test('server log distinguishes queued bytes from response completion', () => {
  const lines=[]; const trace=createServerDiagnostics(line => lines.push(JSON.parse(line)),() => 'construction-scenario',() => 0);
  const [req,res]=pair(); const record=trace.attach(req,res); record.setBodyBytes(12345);
  res.writableFinished=true; res.emit('finish'); res.emit('close');
  assert.deepEqual(lines.map(x => x.event),['request','response-finish','response-close']);
  assert.equal(lines[1].body_bytes_queued,12345); assert.equal(lines[1].writable_finished,true);
  assert.equal(lines[1].path,'/index.pck'); assert.equal(lines[1].id,'s0001');
  assert.equal(trace.state.failed,false);
});
test('server premature close and record overflow remain fatal and bounded', () => {
  const lines=[]; const trace=createServerDiagnostics(line => lines.push(line),() => 'closing');
  const [req,res]=pair(); trace.attach(req,res); res.emit('close');
  assert.equal(trace.state.failed,true);
  for(let i=0;i<1000;i++){const [a,b]=pair();trace.attach(a,b);b.writableFinished=true;b.emit('finish');b.emit('close');}
  assert.ok(lines.length<=513); assert.ok(lines.every(x => x.length<2048));
});
test('fixture rechecks errors after close and host preserves launch/deadline', async () => {
  const fixture=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');
  const close=fixture.indexOf('await context.close(); context = null;');
  assert.ok(close>=0 && fixture.indexOf("'Browser errors during context close'",close)>close);
  assert.ok(fixture.includes('error_limit: 64'));
  const host=await readFile(new URL('./host_main.mjs',import.meta.url),'utf8');
  assert.ok(host.includes('chromium.launch({executablePath:chromePath, headless:true, chromiumSandbox:true, timeout:20000})'));
  assert.ok(host.includes('Math.min(90000, admitted.remaining_seconds*1000)'));
  assert.ok(!host.includes('--no-sandbox'));
});
