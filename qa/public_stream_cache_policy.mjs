// Header-only correction for the two exact public export files. Chrome156's
// no-store streamed-body completion defect is documented by Playwright#42742;
// this is not an abort whitelist or proof that a subsequent run will succeed.
import assert from 'node:assert/strict';

const PUBLIC_PINS = Object.freeze({
  'index.wasm':'26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6',
  'index.pck':'05052b7b14ef9d149ece01770b2f0b72f21547f78408b1f3a66f2b261e733042',
});

export function createPublicStreamCachePolicy(manifest) {
  assert.equal(manifest.reviewed,true,'Public stream cache policy requires reviewed manifest');
  assert.equal(manifest.build,'vc-21ae974acec8');
  assert.equal(manifest.source_commit,'861ca5fa35e01b6a7fa96da1b2457ceea1b3c57c');
  for (const [name,digest] of Object.entries(PUBLIC_PINS)) {
    assert.ok(Object.hasOwn(manifest.files_sha256 ?? {},name),'Missing exact public export file: '+name);
    assert.equal(manifest.files_sha256[name],digest,'Changed public export hash: '+name);
  }
  // Use the raw request path, not a decoded/normalized path or extension match.
  // A query does not change the exact public path; aliases keep no-store.
  return requestTarget => {
    const rawPath=String(requestTarget).split('?',1)[0];
    return rawPath==='/index.wasm' || rawPath==='/index.pck' ? 'no-cache' : 'no-store';
  };
}

export function assertPublicStreamCompletions(records, origin) {
  for (const name of Object.keys(PUBLIC_PINS)) {
    const matches=records.filter(record => record.url===origin+'/'+name);
    assert.ok(matches.some(record => record.method==='GET'),'Missing exact public stream GET: '+name);
    for (const record of matches) {
      assert.equal(record.response?.status,200,'Public stream status must be200: '+name);
      assert.equal(record.response?.headers?.['cache-control'],'no-cache','Actual no-cache response header missing: '+name);
      assert.ok(record.finished && Number.isFinite(record.finished.elapsed_ms),'Public stream did not finish normally: '+name);
      assert.equal(record.failed,undefined,'Public stream failure remains fatal: '+name);
    }
  }
}
