extends SceneTree
# Controlled native fixture, NOT a natural opening. No fog/tree edits.
const Policy=preload("res://scripts/ai_fortify.gd")
var g
var checks=[]
var shots=[]
var out="/tmp/ai-fortify-capture"
func check(n,v):checks.append({"name":n,"passed":bool(v)})
func _initialize():call_deferred("run")
func shot(stage):
 g._update_visuals(0);g._update_hud()
 var meta={"stage":stage,"tick":g.tick_count,"rendered":false,"walls":[],"bank":g.economy.bank_milli(1).duplicate(true)}
 for e in g.entities:
  if e.team==1 and e.kind=="wall" and e.alive:meta.walls.append({"id":e.id,"position":str(e.pos),"progress":e.progress,"hp":e.hp,"built":e.built,"visible_player":g._visible_to(e,0)})
 if DisplayServer.get_name()!="headless":
  for i in 3:await process_frame
  await RenderingServer.frame_post_draw
  meta.rendered=root.get_texture().get_image().save_png(out+"/ai-fortify-"+stage+".png")==OK
 shots.append(meta)
func run():
 DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(960,540)
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true
 var stocks=g.INITIAL_STOCKS.duplicate(true);stocks[1].wood=500;g._test_reset(stocks);g.set_process(false);g.ai_enabled=false
 await process_frame
 var ws=[]
 for e in g.entities:
  if e.team==1 and e.kind=="villager":ws.append(e)
 while ws.size()<8:ws.append(g._spawn("villager",1,Vector3(8+ws.size(),0,-12)))
 var tower=g._spawn("tower",1,Vector3(10,0,-10))
 for i in ws.size():
  ws[i].pos=Vector3(12+i,0,-12)
  if i<2:
   var berry=g._nearest_resource(ws[i].pos,"food",1);g._order(ws[i],"gather",berry.id)
  else:g._set_stance(ws[i],"STOP")
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory();g.tick_count=100
 g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_claimed_workers={};g.ai_build_submitted=false
 var legal=false;var chosen={}
 for x in range(-12,25,6):
  for z in range(-24,13,6):
   tower.pos=Vector3(x,0,z)
   g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
   var plan=Policy.plan(g._ai_records(),{},[],500000,{},100)
   var opposite=Policy.plan(g._ai_records(),{},[],500000,{},100,{tower.id:1})
   if not plan.is_empty() and not opposite.is_empty() and g._placement_reason("wall",plan.position,1,plan.builder).is_empty() and g._placement_reason("wall",opposite.position,1,opposite.builder).is_empty() and g._ai_fortify_lane(plan,g._ai_records()):legal=true;chosen=plan;break
  if legal:break
 check("controlled tower has visible legal open flank",legal)
 var keep0=g._first(1,"town_center");var toward=(Vector3.ZERO-keep0.pos).normalized()
 var facing=Vector3.FORWARD if absf(toward.z)>=absf(toward.x) else Vector3.LEFT
 if facing.dot(toward)<0:facing=-facing
 var across=Vector3.RIGHT if absf(facing.z)>0 else Vector3.BACK
 var observers=[]
 for side in [-1,1]:
  var house=g._spawn("house",0,tower.pos+facing*3+across*(8*side));observers.append({"id":house.id,"position":str(house.pos),"initial_hp":house.hp,"reason":"ordinary player vision outside six-metre central lane and tower six-metre firing range"})
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
 g.camera_focus=tower.pos+facing*3;g.camera_zoom=18
 g.camera.position=g.camera_focus+Vector3(0,24,9);g.camera.look_at(g.camera_focus);g.camera.size=18
 g.tutorial_panel.hide()
 await shot("before")
 var accepted=g._ai_fortify(g._ai_records())
 check("real integration submits ordinary wall",accepted)
 var builds=g.commands.filter(func(c):return c.type=="build" and c.kind=="wall")
 check("submission no free wall or debit",g._count(1,"wall")==0 and g.economy.bank_milli(1).wood==500000)
 check("same turn duplicate prevented",not g._ai_fortify(g._ai_records()) and builds.size()==1)
 if accepted:
  g._tick(.05)
  check("ordinary thirty wood debit",g.economy.bank_milli(1).wood==470000 and g._count(1,"wall")==1)
  var wall=g._first(1,"wall")
  var captured=false
  for i in 1600:
   if not captured and wall.progress>=0.3 and not wall.built:
    captured=true;await shot("construction")
   if wall.built:break
   g._tick(.05)
  check("real builder travels and finishes wall",wall.built and wall.hp==250)
  check("lifetime mask retained after completion",g.ai_fortify_attempts.get(tower.id,0)==1)
  while g.tick_count%100!=0:g._tick(.05)
  g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
  g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_claimed_workers={};g.ai_build_submitted=false
  check("second flank submitted without repeating first",g._ai_fortify(g._ai_records()) and g.ai_fortify_attempts.get(tower.id,0)==3)
  g._tick(.05)
  check("second flank paid thirty wood",g.economy.bank_milli(1).wood==440000 and g._count(1,"wall")==2)
  for i in 1600:
   var unfinished=g.entities.filter(func(e):return e.alive and e.team==1 and e.kind=="wall" and not e.built)
   if unfinished.is_empty():break
   g._tick(.05)
  var walls=g.entities.filter(func(e):return e.alive and e.team==1 and e.kind=="wall" and e.built and e.hp==250)
  check("both paid walls completed at full constructed health",walls.size()==2)
  var observer=g._spawn("scout",0,tower.pos+facing*10);g._set_stance(observer,"STOP")
  observers.append({"id":observer.id,"position":str(observer.pos),"initial_hp":observer.hp,"reason":"post-construction stationary scout for tower and lane visibility; added only after both policy/build operations, outside firing range"})
  g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
  await shot("completed")
  var keep=g._first(1,"town_center");var forward=(Vector3.ZERO-keep.pos).normalized()
  var front=Vector3.FORWARD if absf(forward.z)>=absf(forward.x) else Vector3.LEFT
  if front.dot(forward)<0:front=-front
  var lateral=Vector3.RIGHT if absf(forward.z)>=absf(forward.x) else Vector3.BACK
  for kind in ["cavalry","siege"]:
   var offset=-1.0 if kind=="cavalry" else 1.0
   var start=tower.pos+front*7+lateral*offset;var goal=tower.pos+front*2+lateral*offset
   var unit=g._spawn(kind,1,start);var initial_hp=unit.hp
   g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
   g._submit("order",{"ids":[unit.id],"target":-1,"position":goal},1)
   for i in 500:
    g._tick(.05)
    if unit.pos.distance_to(goal)<0.8:break
   check(kind+" ordinary move crosses central lane",unit.pos.distance_to(goal)<0.8 and unit.hp==initial_hp)
   check(kind+" probe visible through ordinary scout vision",g._visible_to(unit,0))
   await shot("lane-"+kind)
   print("LANE_TRACE "+JSON.stringify({"kind":kind,"start":str(start),"goal":str(goal),"end":str(unit.pos),"status":unit.get("path_status","")}))
 check("conserved paid economy",g.economy.audit().ok)
 check("all captured wall stages visible through normal observer house vision",shots.all(func(s):return s.walls.all(func(w):return w.visible_player)))
 check("observer houses unharmed and outside central lane",observers.all(func(o):return g._get_entity(o.id).hp==o.initial_hp and (absf((g._get_entity(o.id).pos-tower.pos).dot(across))==8 or g._get_entity(o.id).kind=="scout")))
 var proof={"observers":observers,"suite":"ai_fortify_controlled_capture","build":g.Rules.BUILD_ID,"scope":"Controlled setup: 500 AI wood, eight AI villagers, one AI tower; two player houses provide ordinary observer vision; a stationary scout is added after both walls finish for lane inspection. AI isolated. No deleted trees or fog mutations. Two walls paid and built by normal simulation. Cavalry/siege spawned path probes, ordinary move commands. Inspection camera. Headless outputs metadata, NOT screenshots.","shots":shots,"checks":checks,"audit":g.economy.audit()}
 var f=FileAccess.open(out+"/ai-fortify-proof.json",FileAccess.WRITE);f.store_string(JSON.stringify(proof,"  "));f.close()
 print("AI_FORTIFY_CAPTURE ",JSON.stringify(proof))
 quit(0 if checks.all(func(c):return c.passed) else 1)
