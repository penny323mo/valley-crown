// Inert tests: fake browser only. No browser import, launch, network or telemetry.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {selectProfile, runQA} from './browser_qa.mjs';

test('one explicit profile maps to the established viewport', () => {
  assert.deepEqual(selectProfile('desktop'), {name:'desktop', viewport:{width:1440,height:900},hasTouch:false});
  assert.deepEqual(selectProfile('portrait'), {name:'portrait', viewport:{width:390,height:844},hasTouch:true});
  for (const bad of [undefined, '', 'all', 'mobile', ['desktop','portrait']]) assert.throws(() => selectProfile(bad));
});

test('invalid profile rejects before fake browser invocation', async () => {
  let called = false;
  await assert.rejects(runQA({newContext:async () => {called=true;}}, '/unused', 'http://127.0.0.1:12345', 'all'));
  assert.equal(called, false);
});

test('failure persists an atomic truthful checkpoint without a pass', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'rts-fixture-test-'));
  try {
    const browser = {newContext:async () => {throw new Error('fake-context-failure');}};
    await assert.rejects(runQA(browser, dir, 'http://127.0.0.1:12345', 'portrait'), /fake-context-failure/);
    const evidence = JSON.parse(await readFile(path.join(dir, 'browser-evidence.json'), 'utf8'));
    assert.equal(evidence.profile, 'portrait');
    assert.equal(evidence.phase, 'failed');
    assert.equal(evidence.failedDuringPhase, 'starting');
    assert.equal(evidence.basicSmokePassed, false);
    assert.equal(evidence.releaseQAPassed, false);
    assert.deepEqual(evidence.cases, []);
    assert.equal(evidence.checkpoints[0].phase, 'starting');
    assert.ok(evidence.not_run.includes('training completion intentionally excluded from bounded beta smoke'));
    assert.deepEqual(await readdir(dir), ['browser-evidence.json']);
  } finally {await rm(dir, {recursive:true, force:true});}
});

test('phase coverage and unchanged guard bounds remain explicit', async () => {
  const fixture = await readFile(new URL('./browser_qa.mjs', import.meta.url), 'utf8');
  for (const phase of ['load-build-asserted','pause-resume-asserted','menu-close-selection-asserted',
    'command-repeated-cancel-asserted','build-preview-cancel-asserted','training-debit-cancel-refund-asserted','final-state-asserted']) {
    assert.ok(fixture.includes(`checkpoint('${phase}'`), phase);
  }
  for (const assertion of ['Training debit mismatch','Training population reservation missing',
    'Started training 75%-floor refund mismatch','Cancelled training reservation remained',
    'Cancelled preview spent wood','Cancel failed to exit command mode']) assert.ok(fixture.includes(assertion));
  assert.ok(!fixture.includes('25000'));
  assert.ok(!fixture.includes('completedWithinBudget'));
  const guard = await readFile(new URL('./run_host_browser.py', import.meta.url), 'utf8');
  for (const bound of ['--property=MemoryMax=3G','--property=MemorySwapMax=0','--property=TasksMax=256',
    '--property=CPUQuota=200%','--property=RuntimeMaxSec=100','--property=TimeoutStopSec=5','--property=KillMode=control-group']) assert.ok(guard.includes(bound));
  assert.ok(guard.includes("evidence.get('profile') == lock['profile']"));
  const host = await readFile(new URL('./host_main.mjs', import.meta.url), 'utf8');
  assert.ok(host.includes('Math.min(90000,'));
  assert.ok(host.includes('chromiumSandbox:true'));
  assert.ok(host.includes('runQA(browser, output, origin, profile)'));
});
