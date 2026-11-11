// INERT MODULE: no launch or server on import. Invoke only inside reviewed guard.
// Caller owns browser lifecycle. Uses existing read-only snapshot bridge only.
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';

export async function runQA(browser, outputDirectory, origin = 'http://127.0.0.1:8080') {
  assert.match(origin, /^http:\/\/127\.0\.0\.1:\d+$/);
  const evidence = {build: 'vc-dd795d96905c', cases: [], errors: [],
    not_run: ['settings (no panel found)',
      'real iPhone Safari', 'real Android Chrome', 'audible audio verification']};
  try {
    for (const profile of [
      {name: 'desktop', viewport: {width: 1440, height: 900}, hasTouch: false},
      {name: 'portrait', viewport: {width: 390, height: 844}, hasTouch: true},
    ]) {
      const context = await browser.newContext({viewport: profile.viewport, hasTouch: profile.hasTouch, deviceScaleFactor: 1, serviceWorkers: 'block'});
      const page = await context.newPage();
      page.setDefaultTimeout(15000);
      page.on('pageerror', error => evidence.errors.push({profile: profile.name, kind: 'pageerror', text: String(error).slice(0, 2000)}));
      page.on('console', message => {if (message.type() === 'error') evidence.errors.push({profile: profile.name, kind: 'console', text: message.text().slice(0, 2000)});});
      page.on('requestfailed', request => evidence.errors.push({profile: profile.name, kind: 'requestfailed', url: request.url(), failure: request.failure()}));
      await page.route('**/*', route => {
        const url = new URL(route.request().url());
        return url.origin === origin ? route.continue() : route.abort();
      });
      await page.goto(`${origin}/index.html?qa`, {waitUntil: 'load', timeout: 30000});
      await page.waitForFunction(() => typeof window.valleySnapshot === 'function', null, {timeout: 30000});
      const snapshot = () => page.evaluate(() => {window.valleySnapshot(); return window.valleyState;});
      const initial = await snapshot();
      assert.equal(initial.build, evidence.build, 'Wrong runtime build');
      assert.equal(initial.paused, false, 'Expected normal initial live match');
      await page.screenshot({path: `${outputDirectory}/${profile.name}-loaded.png`});
      // Existing public keyboard action, not a game-state setter or test reset.
      await page.keyboard.press('p');
      await page.waitForTimeout(300);
      const toggled = await snapshot();
      assert.notEqual(toggled.paused, initial.paused, 'Pause action did not toggle');
      if (toggled.paused) {
        await page.waitForTimeout(350);
        assert.equal((await snapshot()).tick, toggled.tick, 'Simulation advanced while paused');
      }
      await page.screenshot({path: `${outputDirectory}/${profile.name}-pause-toggle.png`});
      await page.keyboard.press('p');
      await page.waitForTimeout(300);
      const restored = await snapshot();
      assert.equal(restored.paused, initial.paused, 'Repeated pause action failed to restore');
      if (!restored.paused) {
        await page.waitForTimeout(400);
        assert.ok((await snapshot()).tick > restored.tick, 'Simulation failed to resume');
      }
      // Fixed source-derived canvas geometry, never search/click arbitrary game
      // positions. Assertions fail closed if actual exported layout differs.
      const width = profile.viewport.width, height = profile.viewport.height;
      const narrow = width < 620, margin = narrow ? 6 : 8;
      const topHeight = narrow ? 77 : 54;
      const menuY = margin + topHeight + 6;
      const menuX = Math.max(margin, width - 380 - margin);
      const click = async (x, y) => {await page.mouse.click(x, y); await page.waitForTimeout(180);};
      const menuButton = [width - margin - 10 - 30, narrow ? 56 : 35];
      await click(...menuButton);
      await page.screenshot({path: `${outputDirectory}/${profile.name}-menu-open.png`});
      await click(width - margin - 14 - 30, menuY + 10 + 23);
      await page.screenshot({path: `${outputDirectory}/${profile.name}-menu-close.png`});
      const afterClose = await snapshot();
      assert.deepEqual(afterClose.selected, restored.selected, 'Close leaked a world selection');
      assert.equal(afterClose.paused, false, 'Close changed pause');
      await click(...menuButton);
      // title 46px + 6 gap + one 20px mission line +6 +46 nav +6;
      // second row: All villagers. Selected count confirms this real action.
      await click(menuX + 14 + 48, menuY + 10 + 46 + 6 + 20 + 6 + 46 + 6 + 23);
      const selected = await snapshot();
      assert.ok(selected.selected.length >= 1, 'Menu villagers action missed: inspect screenshots/geometry');
      const command = [margin + 10 + 27, height - margin - 4 - 23];
      const cancel = [command[0] + 54 + 8, command[1]];
      for (let round = 0; round < 2; round++) {
        await click(...command);
        assert.equal((await snapshot()).touch_mode, true, 'Command-mode button missed');
        if (round === 0) await page.keyboard.press('Escape');
        else await click(...cancel);
        await page.waitForTimeout(180);
        const cancelled = await snapshot();
        assert.equal(cancelled.touch_mode, false, 'Cancel failed to exit command mode');
        assert.equal(cancelled.paused, false, 'Cancel unexpectedly paused game');
        assert.deepEqual(cancelled.selected, selected.selected, 'Cancel changed selection');
      }
      // Repeated browser touchcancel follows the shipped public event listener.
      // It is synthetic input, explicitly not evidence of real-device gestures.
      await click(...command);
      assert.equal((await snapshot()).touch_mode, true);
      await page.locator('canvas').dispatchEvent('touchcancel', {bubbles: true});
      await page.locator('canvas').dispatchEvent('touchcancel', {bubbles: true});
      const repeatedCancel = await snapshot();
      assert.equal(repeatedCancel.touch_mode, false);
      assert.equal(repeatedCancel.paused, false);
      assert.deepEqual(repeatedCancel.selected, selected.selected);
      const buildCancel = [];
      for (let round = 0; round < 2; round++) {
        const beforeBuild = await snapshot();
        await click(margin + 10 + 54 + 8 + 45, command[1]);
        assert.equal((await snapshot()).build_mode, 'house', 'House action target missed');
        await page.keyboard.press('Escape');
        await page.waitForTimeout(180);
        const afterBuild = await snapshot();
        assert.equal(afterBuild.build_mode, '', 'Build preview cancellation failed');
        assert.equal(afterBuild.bank_milli.wood, beforeBuild.bank_milli.wood, 'Cancelled preview spent wood');
        assert.equal(afterBuild.paused, false);
        buildCancel.push({before:beforeBuild, after:afterBuild});
      }
      let training = {notRun:'desktop-only bounded check'};
      if (profile.name === 'desktop') {
        // Use real Home menu button, avoiding Space being consumed by HUD focus.
        await click(...menuButton);
        await click(menuX + 14 + 39, menuY + 10 + 46 + 6 + 20 + 6 + 23);
        const home = await snapshot();
        assert.equal(home.selected.length, 1, 'Home did not select one town center');
        const train = [margin + 10 + 100 + 8 + 60, command[1]];
        const cancelTrain = [margin + 10 + 100 + 8 + 120 + 8 + 65, command[1]];
        await click(...train);
        const queued = await snapshot();
        assert.equal(queued.bank_milli.food, home.bank_milli.food - 50 * home.economy_scale, 'Training debit mismatch');
        assert.equal(queued.population, home.population + 1, 'Training population reservation missing');
        await click(...cancelTrain);
        const refunded = await snapshot();
        assert.equal(refunded.bank_milli.food, queued.bank_milli.food + 37 * home.economy_scale, 'Started training 75%-floor refund mismatch');
        assert.equal(refunded.population, home.population, 'Cancelled training reservation remained');
        await click(...train);
        await page.screenshot({path: `${outputDirectory}/desktop-training-queued.png`});
        const until = Date.now() + 25000;
        let completed = await snapshot();
        while (completed.trained <= home.trained && Date.now() < until) {
          await page.waitForTimeout(400); completed = await snapshot();
        }
        training = {home, queued, refunded, completed, completedWithinBudget:completed.trained > home.trained};
        if (!training.completedWithinBudget) evidence.not_run.push('Training completion not observed within 25-second budget');
        await page.screenshot({path: `${outputDirectory}/desktop-training-after-wait.png`});
      }
      await page.keyboard.down('ArrowRight');
      await page.waitForTimeout(250);
      await page.keyboard.up('ArrowRight');
      await page.screenshot({path: `${outputDirectory}/${profile.name}-after-inputs.png`});
      const final = await snapshot();
      assert.equal(final.build, evidence.build);
      assert.equal(final.paused, false);
      evidence.cases.push({profile: profile.name, initial, toggled, restored, afterClose, selected, repeatedCancel, buildCancel, training, final,
        camera: 'ArrowRight exercised; screenshot recorded; snapshot has no camera field',
        menu: 'source-derived clicks and villagers-selection assertion; screenshots need visual review',
        repeatedCancelMethod: 'two synthetic public touchcancel input events; not a device test'});
      await context.close();
    }
    assert.equal(evidence.errors.length, 0, 'Browser errors recorded');
    evidence.basicSmokePassed = true;
    // Bounded smoke pass is separate from full release/real-device acceptance.
    evidence.releaseQAPassed = false;
  } catch (error) {
    evidence.failure = String(error);
    throw error;
  } finally {
    await writeFile(`${outputDirectory}/browser-evidence.json`, JSON.stringify(evidence, null, 2));
  }
  return evidence;
}
