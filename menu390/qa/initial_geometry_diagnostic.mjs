import assert from 'node:assert/strict';
// Only previously empty/clipped first-frame button geometry may be observed again.
// No input, state mutation, deadline extension, or browser-error suppression.
export async function collectInitialGeometry({observe,validate,delay,record,result,now=Date.now}) {
  const begin=now(),deadline=begin+5000;
  for(let index=0;index<32 && now()<deadline;index++) {
    const observation=await observe(deadline);
    assert.ok(now()<=deadline,'Initial geometry deadline exhausted');
    let geometryError=null;
    try {validate(observation);result.ready=true;}
    catch(error) {
      assert.ok(error instanceof assert.AssertionError,'Unexpected non-geometry error');
      const message=error.message;
      if(!/^Menu control clipped\/offscreen: (StartMatchButton|HelpButton)$/.test(message) && message!=='54px menu target clipped' && message!=='Menu targets overlap or gap collapsed') throw error;
      geometryError=message;
    }
    await record({elapsed_ms:now()-begin,menu:observation.menu,geometry:observation.geometry,error:geometryError});
    if(result.ready)return;
    const remaining=deadline-now();if(remaining<=0)return;
    await delay(Math.min(160,remaining));
  }
}
