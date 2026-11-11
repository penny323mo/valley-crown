// Pure metadata tests only. No server listener, browser, cache or network use.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createPublicStreamCachePolicy,assertPublicStreamCompletions} from './public_stream_cache_policy.mjs';

function manifest() {
  return {reviewed:true,build:'vc-542ddb524e45',source_commit:'422acc862d9fc56f1fe2c95440f411893ded5edf',files_sha256:{
    'index.wasm':'26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6',
    'index.pck':'f75ccbd9484f33676fc46c413d63711fd3144116c8c7dfbb56f2467b194b5fa5'}};
}
test('only exact reviewed public paths receive no-cache', () => {
  const policy=createPublicStreamCachePolicy(manifest());
  for (const target of ['/index.wasm','/index.pck','/index.wasm?v=1','/index.pck?v=1']) assert.equal(policy(target),'no-cache');
  for (const target of ['/', '/index.html','/index.js','/index.png','/index.audio.worklet.js',
    '/other.wasm','/other.pck','/nested/index.wasm','/nested/../index.wasm','/index.wasm/','/index.wasm.bak',
    '/INDEX.WASM','/%69ndex.wasm','/index.%70ck','//index.pck','/index.pck#fragment',
    'http://localhost/index.wasm','/private.json?file=index.pck','']) assert.equal(policy(target),'no-store',target);
});
test('missing, changed, inherited or unreviewed pins fail closed', () => {
  let m=manifest();m.reviewed=false;assert.throws(() => createPublicStreamCachePolicy(m));
  m=manifest();m.build='vc-000000000000';assert.throws(() => createPublicStreamCachePolicy(m));
  m=manifest();m.source_commit='0'.repeat(40);assert.throws(() => createPublicStreamCachePolicy(m));
  for (const name of ['index.wasm','index.pck']) {
    m=manifest();delete m.files_sha256[name];assert.throws(() => createPublicStreamCachePolicy(m));
    m=manifest();m.files_sha256[name]='0'.repeat(64);assert.throws(() => createPublicStreamCachePolicy(m));
  }
  m=manifest();m.files_sha256=Object.create(m.files_sha256);assert.throws(() => createPublicStreamCachePolicy(m));
});
test('actual manifest is blocked while unreviewed and must match exact public pins once bound', async () => {
  const actual=JSON.parse(await readFile(new URL('./scenario-manifest.json',import.meta.url),'utf8'));
  if (actual.reviewed) assert.equal(createPublicStreamCachePolicy(actual)('/index.pck'),'no-cache');
  else assert.throws(() => createPublicStreamCachePolicy(actual));
});
test('fresh context, fatal request failures, origin fence and bounds remain', async () => {
  const host=await readFile(new URL('./host_main.mjs',import.meta.url),'utf8');
  assert.ok(host.includes("res.setHeader('Cache-Control','no-store')"));
  assert.ok(host.includes("'Cache-Control':publicStreamCachePolicy(req.url)"));
  assert.ok(host.includes('Math.min(90000, admitted.remaining_seconds*1000)'));
  assert.ok(host.includes('chromium.launch({executablePath:chromePath, headless:true, chromiumSandbox:true, timeout:20000})'));
  const fixture=await readFile(new URL('./browser_qa.mjs',import.meta.url),'utf8');
  for (const marker of ['browser.newContext(',"serviceWorkers:'block'",'new URL(route.request().url()).origin === origin',
    'Browser errors during context close','70000','exceeded5000ms']) assert.ok(fixture.includes(marker),marker);
  assert.ok(!host.includes('launchPersistentContext'));
});
test('both exact streams need observed200/no-cache/finished and no failure', () => {
  const origin='http://127.0.0.1:1234';
  const valid=() => ['index.wasm','index.pck'].map(name => ({url:origin+'/'+name,method:'GET',
    response:{status:200,headers:{'cache-control':'no-cache'}},finished:{elapsed_ms:100,phase:'starting'}}));
  assertPublicStreamCompletions(valid(),origin);
  assert.throws(() => assertPublicStreamCompletions(valid().slice(0,1),origin));
  for (const index of [0,1]) {
    for (const mutate of [r => {delete r.finished;},r => {r.failed={error:'net::ERR_ABORTED'};},
      r => {r.response.status=206;},r => {r.response.headers['cache-control']='no-store';},
      r => {delete r.response.headers['cache-control'];},r => {r.url='http://example.invalid/index.wasm';},
      r => {r.method='HEAD';}]) {
      const records=valid();mutate(records[index]);assert.throws(() => assertPublicStreamCompletions(records,origin));
    }
  }
});

test('read failures precede success headers and errors explicitly restore no-store', async () => {
  const host=await readFile(new URL('./host_main.mjs',import.meta.url),'utf8');
  const body=host.indexOf("const body=req.method === 'HEAD' ? undefined : await readFile(target);");
  const success=host.indexOf('res.writeHead(200,');
  assert.ok(body >= 0 && body < success);
  assert.match(host,/catch \{trace\.setBodyBytes\(9\); res\.setHeader\('Cache-Control','no-store'\); res\.writeHead\(404\); res\.end\('Not found'\);\}/);
});
