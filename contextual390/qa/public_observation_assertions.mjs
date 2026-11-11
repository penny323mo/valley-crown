// Pure read-only public-observation assertions. Importing never launches anything.
import assert from 'node:assert/strict';
export function menuButton(menu,id,viewport) {
  assert.equal(menu.visible,true,'Main menu is not publicly visible');
  const items=menu.buttons.filter(b=>b.id===id);
  assert.equal(items.length,1,'Required unique public menu control missing: '+id);
  const button=items[0],r=button.rect;
  assert.ok(Array.isArray(r)&&r.length===4&&r.every(Number.isFinite));
  assert.ok(r[0]>=0&&r[1]>=0&&r[2]>=48&&r[3]>=48&&r[0]+r[2]<=viewport[0]&&r[1]+r[3]<=viewport[1], 'Menu control clipped/offscreen: '+id);
  return button;
}
export function assertMenu(menu,{visible=true,page='home',match_exists=false,game_bridge=false}={}) {
  assert.equal(menu.visible,visible);assert.equal(menu.page,page);assert.equal(menu.match_exists,match_exists);
  assert.equal(menu.game_bridge,game_bridge,'Game bridge presence differs from ordinary Start lifecycle');
  assert.ok(Array.isArray(menu.buttons));
  if(!visible)assert.deepEqual(menu.buttons,[]);
}
export function assertCamera(camera) {
  assert.ok(camera&&Array.isArray(camera.focus)&&camera.focus.length===3&&camera.focus.every(Number.isFinite));
  assert.ok(Number.isFinite(camera.zoom)&&camera.zoom>0);
}
export function assertSameCamera(before,after) {
  assertCamera(before.hud.camera);assertCamera(after.hud.camera);
  assert.deepEqual(after.hud.camera,before.hud.camera,'Camera changed; projected motion is not an entity-motion witness');
}
export function assertPausedMatch(before,paused) {
  assert.equal(before.paused,false);assert.equal(paused.paused,true);assert.equal(paused.game_over,false);
  assert.equal(paused.own_pending_commands,0);assert.equal(paused.touch_mode,false);assert.equal(paused.build_mode,'');
  assert.deepEqual(paused.selected,before.selected);assertSameCamera(before,paused);
  for(const key of ['bank_milli','economy_scale','population','capacity','delivered','built','trained'])assert.deepEqual(paused[key],before[key], 'Menu changed '+key);
}
export function assertFrozenMatch(before,after) {
  assert.equal(before.paused,true);assert.equal(after.paused,true);assert.equal(after.tick,before.tick,'Paused main menu advanced simulation');
  for(const key of ['selected','bank_milli','economy_scale','population','capacity','delivered','built','trained','own_pending_commands','touch_mode','build_mode'])assert.deepEqual(after[key],before[key]);
  assertSameCamera(before,after);
}
export function contextResource(state,workerId) {
  assert.equal(state.hud.schema,2);assertSameCamera(state,state);
  const worker=state.hud.own_targets.find(t=>t.id===workerId&&t.kind==='villager');assert.ok(worker,'Selected villager not currently publicly tappable');
  const validPoint=p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&p[0]>=0&&p[0]<state.hud.viewport[0]&&p[1]>=0&&p[1]<state.hud.viewport[1];
  assert.ok(validPoint(worker.screen));
  assert.ok(Array.isArray(state.hud.ground_points)&&state.hud.ground_points.length<=9);
  assert.ok(state.hud.ground_points.every(validPoint));
  const resources=state.hud.context_targets.filter(t=>t.category==='resource'&&['pine','oak','berry'].includes(t.kind)&&validPoint(t.screen));
  resources.sort((a,b)=>Math.hypot(...a.screen.map((v,i)=>v-worker.screen[i]))-Math.hypot(...b.screen.map((v,i)=>v-worker.screen[i]))||a.id-b.id);
  assert.ok(resources.length,'No current public tree/berry target: no artificial reveal or substitute');
  return resources[0];
}
export function cargo(state) {
  const match=state.hud.selection_detail.match(/負重\s+(\d+)\s*\/\s*10/);return match?Number(match[1]):0;
}
export function assertDirectGather(before,after,workerId) {
  assert.equal(before.paused,false);assert.equal(after.paused,false);assert.equal(after.game_over,false);
  for(const s of [before,after]) {assert.deepEqual(s.selected,[workerId]);assert.equal(s.touch_mode,false);assert.equal(s.build_mode,'');}
  assert.equal(after.own_pending_commands,0);assert.ok(after.tick>before.tick);assertSameCamera(before,after);
  assert.ok(cargo(after)>cargo(before),'Need actual visible cargo increase, not queued intent or gather status alone');
  assert.match(after.hud.selection_detail,/採集/,'Need actual visible gather status');
  for(const key of ['bank_milli','economy_scale','population','capacity','delivered','built','trained'])assert.deepEqual(after[key],before[key],'Unexpected economy effect before first observed cargo: '+key);
}
export function projectedMovement(before,after,workerId) {
  assertSameCamera(before,after);
  const a=before.hud.own_targets.find(t=>t.id===workerId),b=after.hud.own_targets.find(t=>t.id===workerId);
  return !!(a&&b&&after.tick>before.tick&&Math.hypot(a.screen[0]-b.screen[0],a.screen[1]-b.screen[1])>=2);
}
export function menuSwipePoints(state) {
  const known=/^(關閉|主堡|閒置村民|全軍|所有村民|斥候|小地圖|框選單位|音效：關|音效：開|取消模式|移動／攻擊|投降)$/;
  const buttons=state.hud.buttons.filter(b=>!b.disabled&&known.test(b.text)&&b.rect[2]>=12&&b.rect[3]>=12);
  const top=buttons.find(b=>b.text==='關閉');assert.ok(top,'No visible shortcut-menu top control for bounded swipe');
  const low=[...buttons].sort((a,b)=>(b.rect[1]+b.rect[3]/2)-(a.rect[1]+a.rect[3]/2))[0];
  const center=b=>[b.rect[0]+b.rect[2]/2,b.rect[1]+b.rect[3]/2];
  const start=center(low),end=center(top);
  for(const point of [start,end])assert.ok(point.every(Number.isFinite)&&point[0]>=0&&point[1]>=0&&point[0]<state.hud.viewport[0]&&point[1]<state.hud.viewport[1], 'Menu swipe endpoint offscreen');
  assert.ok(start[1]-end[1]>=90,'Insufficient visible menu scroll span');
  return {start,end};
}

export function contextGround(state,workerId) {
  const worker=state.hud.own_targets.find(t=>t.id===workerId&&t.kind==='villager');
  assert.ok(worker,'Selected villager not publicly tappable');
  assert.ok(Array.isArray(state.hud.ground_points)&&state.hud.ground_points.length<=9);
  const valid=p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&p[0]>=0&&p[1]>=0&&p[0]<state.hud.viewport[0]&&p[1]<state.hud.viewport[1];
  assert.ok(valid(worker.screen));assert.ok(state.hud.ground_points.every(valid));
  const points=state.hud.ground_points.map(p=>({point:p,distance:Math.hypot(p[0]-worker.screen[0],p[1]-worker.screen[1])}))
    .filter(p=>p.distance>=24&&p.distance<=180).sort((a,b)=>a.distance-b.distance);
  assert.ok(points.length,'No bounded nearby public empty-ground probe; no synthetic substitute');
  return points[0].point;
}
export function movedTowardGround(before,after,workerId,point) {
  assertSameCamera(before,after);
  const a=before.hud.own_targets.find(t=>t.id===workerId),b=after.hud.own_targets.find(t=>t.id===workerId);
  if(!a||!b||after.tick<=before.tick)return false;
  assert.ok([a.screen,b.screen,point].every(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)));
  const distance=p=>Math.hypot(p[0]-point[0],p[1]-point[1]);
  return Math.hypot(a.screen[0]-b.screen[0],a.screen[1]-b.screen[1])>=4&&distance(a.screen)-distance(b.screen)>=4;
}
export function assertDirectGround(before,after,workerId,point) {
  assert.equal(before.paused,false);assert.equal(after.paused,false);assert.equal(after.game_over,false);
  for(const s of [before,after]){assert.deepEqual(s.selected,[workerId]);assert.equal(s.touch_mode,false);assert.equal(s.build_mode,'');}
  assert.equal(after.own_pending_commands,0);assert.ok(movedTowardGround(before,after,workerId,point),'Need actual movement toward tapped public ground, not queued intent or camera motion');
  for(const key of ['bank_milli','economy_scale','population','capacity','delivered','built','trained'])assert.deepEqual(after[key],before[key]);
}
