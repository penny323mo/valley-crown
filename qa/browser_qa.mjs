// INERT MODULE: no launch/server on import. Invoke only inside reviewed guard.
// Ordinary UI touch only; the sole page evaluation reads the shipped QA bridge.
import assert from 'node:assert/strict';
import {writeFile, rename} from 'node:fs/promises';

export function selectProfile(name) {
  assert.ok(name === 'desktop' || name === 'portrait', 'One explicit reviewed profile required');
  return name === 'desktop'
    ? {name, viewport: {width: 1440, height: 900}, hasTouch: false}
    : {name, viewport: {width: 390, height: 844}, hasTouch: true};
}
export async function pointerClick(page, profileName, x, y) {
  selectProfile(profileName);
  if (profileName === 'portrait') await page.touchscreen.tap(x, y);
  else await page.mouse.click(x, y);
}
export function assertQueued(initial, queued) {
  assert.equal(queued.bank_milli.food, initial.bank_milli.food - 50 * initial.economy_scale, 'Training debit mismatch');
  assert.equal(queued.bank_milli.wood, initial.bank_milli.wood, 'Training changed wood');
  assert.equal(queued.population, initial.population + 1, 'Training population reservation missing');
  assert.equal(queued.trained, initial.trained, 'Training must not complete immediately');
  assert.equal(queued.delivered, initial.delivered, 'Unexpected delivery before worker command');
}
export function assertCompleted(initial, queued, completed, villagers) {
  assert.equal(completed.trained, initial.trained + 1, 'Exactly one training completion required');
  assert.equal(completed.population, queued.population, 'Reservation was not transferred to newborn');
  assert.equal(completed.capacity, initial.capacity, 'Unexpected capacity change');
  assert.equal(completed.delivered - initial.delivered, 10, 'One natural full cargo deposit required');
  assert.equal(completed.bank_milli.food, queued.bank_milli.food + (completed.delivered - initial.delivered) * initial.economy_scale, 'Delivered food credit mismatch');
  assert.equal(completed.bank_milli.wood, initial.bank_milli.wood, 'Food gathering changed wood');
  assert.equal(villagers.selected.length, 6, 'All-villager UI must select six actual living villagers');
  for (const id of [1,2,3,4,5]) assert.ok(villagers.selected.includes(id), 'An opening villager disappeared');
  assert.equal(new Set(villagers.selected).size, 6, 'Duplicate villager selection');
  assert.equal(villagers.selected.filter(id => ![1,2,3,4,5].includes(id)).length, 1, 'Exactly one new villager ID required');
  assert.equal(villagers.population, queued.population, 'Selection changed population');
}
export async function runQA(browser, outputDirectory, origin, profileName) {
  assert.match(origin, /^http:\/\/127\.0\.0\.1:\d+$/);
  const profile = selectProfile(profileName);
  assert.equal(profile.name, 'portrait', 'Focused economy fixture requires portrait');
  const started = Date.now();
  const evidence = {build:'vc-dd795d96905c', profile:profile.name, cases:[], errors:[],
    pointerInput:'Chrome emulated touchscreen taps; not a physical phone',
    basicSmokePassed:false, economyLoopPassed:false, releaseQAPassed:false,
    phase:'starting', checkpoints:[], inputs:[], observations:[],
    source_commit:'c5b78df4dab1e1f58f83bc2d8678512ddc628045',
    game_tree:'c133ed816d338bfabab2ae617bee917f4080799b',
    not_run:['combat','real iPhone Safari','real Android Chrome','audible audio verification','full-game acceptance']};
  const persist = async () => {
    await writeFile(`${outputDirectory}/browser-evidence.json.tmp`, JSON.stringify(evidence,null,2));
    await rename(`${outputDirectory}/browser-evidence.json.tmp`,`${outputDirectory}/browser-evidence.json`);
  };
  const checkpoint = async (phase,state=null) => {
    evidence.phase=phase;
    evidence.checkpoints.push({phase,elapsed_ms:Date.now()-started,state});
    await persist();
  };
  try {
    await checkpoint('starting');
    const context=await browser.newContext({viewport:profile.viewport,hasTouch:true,deviceScaleFactor:1,serviceWorkers:'block'});
    const page=await context.newPage();
    page.setDefaultTimeout(10000);
    page.on('pageerror',error=>evidence.errors.push({kind:'pageerror',text:String(error).slice(0,2000)}));
    page.on('console',message=>{if(message.type()==='error') evidence.errors.push({kind:'console',text:message.text().slice(0,2000)});});
    page.on('requestfailed',request=>evidence.errors.push({kind:'requestfailed',url:request.url(),failure:request.failure()}));
    await page.route('**/*',route=>new URL(route.request().url()).origin===origin?route.continue():route.abort());
    await page.goto(`${origin}/index.html?qa`,{waitUntil:'load',timeout:30000});
    await page.waitForFunction(()=>typeof window.valleySnapshot==='function',null,{timeout:30000});
    const snapshot=()=>page.evaluate(()=>{window.valleySnapshot();return window.valleyState;});
    const capture=async name=>{await page.screenshot({path:`${outputDirectory}/${name}.png`,timeout:7000});};
    const tap=async (action,x,y)=>{
      evidence.inputs.push({action,x,y,elapsed_ms:Date.now()-started,method:'touchscreen.tap'});
      await pointerClick(page,'portrait',x,y);await page.waitForTimeout(180);
    };
    const initial=await snapshot();
    assert.equal(initial.build,evidence.build);
    assert.equal(initial.paused,false);
    assert.equal(initial.game_over,false);
    assert.deepEqual(initial.selected,[0],'Initial town center is not selected');
    assert.equal(initial.population,6);assert.equal(initial.trained,0);assert.equal(initial.delivered,0);
    assert.equal(initial.bank_milli.food,150000);assert.equal(initial.bank_milli.wood,200000);
    await checkpoint('initial-state-asserted',initial);
    // Source-derived bottom strip: 16px origin +100 rally +8 gap +60 center.
    await tap('train one villager',184,811);
    const queued=await snapshot();assertQueued(initial,queued);
    await checkpoint('training-queued-asserted',queued);
    await capture('portrait-training-queued');
    // Immutable initial map projection, independently checked against the actual
    // previous rendered portrait. Camera (19,25,23), ortho30, height844. Worker1
    // (-28.5,0,27.5) anchor+0.6 projects (56.37,417.54); berry22 (-29.5,0,25)
    // anchor+1 projects (79.48,362.58). No camera/game-state setter or search.
    await tap('select opening villager 1',56,418);
    const selected=await snapshot();assert.deepEqual(selected.selected,[1],'Opening villager touch missed');
    await tap('enter command mode',43,811);
    assert.equal((await snapshot()).touch_mode,true,'Command touch missed');
    await tap('gather visible nearby berry',79,363);
    const ordered=await snapshot();
    assert.equal(ordered.touch_mode,false,'Resource command failed to consume targeting');
    assert.deepEqual(ordered.selected,[1],'Resource command changed selection');
    await checkpoint('gather-command-issued',ordered);
    // Observe normal wall-clock play only. No manually advanced ticks. One
    // focused loop must complete within55s and leave reserve under Node90s.
    const deadline=Math.min(started+75000,Date.now()+55000);
    let completed=null, gatheringCapture=false;
    while(Date.now()<deadline){
      const state=await snapshot();
      evidence.observations.push({elapsed_ms:Date.now()-started,state});
      assert.equal(state.build,evidence.build);assert.equal(state.paused,false);assert.equal(state.game_over,false);
      assert.ok(state.tick>=ordered.tick,'Simulation tick moved backwards');
      if(!gatheringCapture && state.tick>=ordered.tick+100){
        await checkpoint('gathering-observed',state);
        await capture('portrait-villager-gathering');gatheringCapture=true;
      }
      if(state.trained===initial.trained+1 && state.delivered>=initial.delivered+10){completed=state;break;}
      await persist();await page.waitForTimeout(400);
    }
    assert.ok(completed,'Natural deposit and training did not both finish within bounded observation');
    await checkpoint('training-and-deposit-observed',completed);
    await capture('portrait-first-deposit');
    // All villagers menu action proves a newborn is an actual selectable unit,
    // not only a counter or reservation. No keyboard shortcuts in this scenario.
    await tap('open menu',344,56);
    await tap('select all villagers',68,252);
    const villagers=await snapshot();assertCompleted(initial,queued,completed,villagers);
    await checkpoint('newborn-and-reservation-asserted',villagers);
    await capture('portrait-six-villagers');
    await tap('open menu',344,56);
    await tap('return to town center',59,200);
    const home=await snapshot();assert.deepEqual(home.selected,[0]);
    assert.equal(home.trained,1);assert.equal(home.population,7);
    await capture('portrait-training-completed');
    evidence.cases.push({initial,queued,selected,ordered,completed,villagers,home,
      deposit:'One full10-food cargo credited by ordinary gathering and automatic return',
      training:'50food debited; reserved population6→7; trained0→1; living villagers5→6; final population7 means no lingering extra reservation',
      queue:'Queue disappearance is rendered evidence, not an added private queue API'});
    await context.close();
    assert.equal(evidence.errors.length,0,'Browser errors recorded');
    evidence.basicSmokePassed=true;evidence.economyLoopPassed=true;
    await checkpoint('completed');
  }catch(error){
    evidence.failure=String(error);evidence.failedDuringPhase=evidence.phase;evidence.phase='failed';throw error;
  }finally{await persist();}
  return evidence;
}
