extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
var out=""
var metadata_only=false
var captures=[]
func shot(g,name,focus):
 g.camera_focus=focus;g.camera_zoom=22;g._camera_update();g._layout_ui();g._refresh_fog();g._update_visuals(0);g._update_hud()
 await process_frame;await process_frame
 var alive=[]
 for e in g.entities:
  if e.team==0 and e.category=="unit" and e.alive:alive.append({"id":e.id,"kind":e.kind,"hp":e.hp,"position":str(e.pos)})
 var row={"name":name,"tick":g.tick_count,"stage":g.breach_mission.stage,"outcome":g.outcome,"game_over":g.game_over,"army":alive,"camera":str(g.camera_focus),"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" png",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 captures.append(row)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v97-breach-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(960,540)
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="breach";g.history_path=out+"/history.json";root.add_child(g);g.set_process(false)
 await process_frame
 if not is_instance_valid(g.camera) or g._get_entity(g.breach_mission.post_id).is_empty():push_error("Incomplete game initialization");quit(2);return
 var ids=[]
 for e in g.entities:
  if e.team==0 and e.category=="unit" and e.kind not in ["villager","scout"]:ids.append(e.id)
 check("all authored army starts statically legal",ids.all(func(id):var u=g._get_entity(id);return g._static_unit_step_is_free(u,u.pos) and not g._route_grid(u).is_point_solid(g._cell(u.pos))))
 check("final front tower coordinates",g._get_entity(g.breach_mission.post_id).pos==Vector3(0,0,-13))
 check("sixteen authored front walls",g.entities.filter(func(e):return e.alive and e.team==1 and e.kind=="wall").size()==16)
 g._select(ids)
 await shot(g,"01-authored-frontline-opening",Vector3(-3,0,4))
 var captured_wall=false;var captured_tower=false
 var assigned={};var secondwall=-1;var thirdwall=-1;var phase=0;var wall_id=-1;var targets=[];var lasttarget=-1;var wall_crossed=false;var normal_damage=true;var checked_attack=1;var steps=[]
 g._submit("advance",{"ids":ids,"position":Vector3(6,0,-3)})
 for i in 6500:
  if g.game_over:break
  if i%20==0:
   var records=g.faction_views[0].records()
   var known=[]
   for e in records.values():
    if e.get("alive",false) and not e.get("remembered",false) and e.get("team",-1)==1:known.append(e)
   if phase==0 and ids.filter(func(id):return g._get_entity(id).kind=="siege").all(func(id):return g._get_entity(id).pos.distance_to(Vector3(6,0,-3))<7):
    for e in known:
     if e.kind=="wall" and e.pos==Vector3(0,0,-9):wall_id=e.id;phase=1;break
   var target=-1
   for e in known:
    if e.kind=="wall" and e.pos==Vector3(-2,0,-9):secondwall=e.id
    if e.kind=="wall" and e.pos==Vector3(2,0,-9):thirdwall=e.id
   if phase==1:
    if secondwall>=0 and thirdwall>=0 and not g._get_entity(wall_id).alive and not g._get_entity(secondwall).alive and not g._get_entity(thirdwall).alive:phase=2;steps.append({"wall_destroyed":g.tick_count});assigned.clear();g._submit("order",{"ids":ids,"target":-1,"position":Vector3(0,0,-10)})
    else:target=wall_id if g._get_entity(wall_id).alive else (secondwall if g._get_entity(secondwall).alive else thirdwall)
   if phase==2:
    if g.breach_mission.stage>=1:phase=3;steps.append({"post_destroyed":g.tick_count});assigned.clear();g._submit("advance",{"ids":ids,"position":Vector3(17,0,-15),"formation":"line"});lasttarget=-1
    else:
     for e in known:
      if e.id==g.breach_mission.post_id:target=e.id
   if phase==3:
    for e in known:
     if e.kind=="tower" and e.id!=g.breach_mission.post_id:target=e.id
    if target<0:
     for e in known:
      if e.kind=="town_center":target=e.id
   if phase==3 and target<0 and lasttarget>=0 and not g._get_entity(lasttarget).alive:
    g._submit("advance",{"ids":ids,"position":Vector3(25,0,-24)});lasttarget=-1;assigned.clear()
   for id in ids:
    var unit=g._get_entity(id)
    if not unit.alive or phase==0:continue
    # Let large actors physically enter the cleared breach before replacing
    # the movement with a tower attack. Shared sight is not arrival.
    if unit.kind in ["cavalry","siege"] and phase==2 and unit.pos.distance_to(Vector3(0,0,-10))>3:continue
    if unit.kind in ["cavalry","siege"] and phase==3 and unit.pos.distance_to(Vector3(17,0,-15))>10:continue
    var chosen=target
    if unit.kind!="siege" and (unit.kind=="archer" or phase>=2):
     var nearest=INF
     for e in known:
      if e.category=="unit" and e.pos.distance_squared_to(unit.pos)<nearest:
       chosen=e.id;nearest=e.pos.distance_squared_to(unit.pos)
    if chosen>=0 and chosen!=assigned.get(id,-1) and records.has(chosen) and not records[chosen].get("remembered",false):
     g._submit("order",{"ids":[id],"target":chosen,"position":records[chosen].pos});assigned[id]=chosen;lasttarget=chosen
     if chosen not in targets:targets.append(chosen)
  g._tick(Rules.TICK)
  if phase>=2:
   for id in ids:
    var e=g._get_entity(id)
    if e.alive and e.pos.z<-9 and e.pos.distance_to(Vector3(0,0,-9))<3:wall_crossed=true
  for aid in range(checked_attack,g.attack_ledger.next_attack_id()):
   var event=g.attack_ledger.event(aid);var a=g._get_entity(event.attacker_id);var t=g._get_entity(event.target_id)
   if not a.is_empty() and not t.is_empty():normal_damage=normal_damage and event.damage==Rules.CONTENT.resolve_damage(a.kind,t.kind).damage
  checked_attack=g.attack_ledger.next_attack_id()
  if phase>=2 and not captured_wall:
   captured_wall=true;await shot(g,"02-front-walls-breached",Vector3(0,0,-9))
  if phase>=3 and not captured_tower:
   captured_tower=true;await shot(g,"03-front-tower-destroyed",Vector3(0,0,-13))
  if i%500==0:print("BREACH_TICK ",g.tick_count," phase=",phase," live=",ids.filter(func(id):return g._get_entity(id).alive).size()," target=",lasttarget," hp=",g._get_entity(lasttarget).get("hp",-1))
 check("normal commands destroyed front wall",wall_id>=0 and secondwall>=0 and thirdwall>=0 and not g._get_entity(wall_id).alive and not g._get_entity(secondwall).alive and not g._get_entity(thirdwall).alive)
 check("normal movement crosses broken wall",wall_crossed)
 check("ordinary damage equals shared rules",normal_damage and checked_attack>1)
 check("normal combat completed both objectives",g.breach_mission.stage==2 and g.game_over and g.outcome=="victory")
 check("mission economy AI stayed disabled by scenario not test flag",g.ai_enabled and g.ai_raids==0)
 print("BREACH_MEMBERS ",ids.map(func(id):var e=g._get_entity(id);return {"id":id,"kind":e.kind,"alive":e.alive,"hp":e.hp,"pos":e.pos,"state":e.state,"path":e.path_status,"reason":e.path_reason,"dest":e.dest,"requested":e.path_request_goal,"resolved":e.path_resolved_goal}))
 print("BREACH_JOURNEY ",JSON.stringify({"tick":g.tick_count,"phase":phase,"stage":g.breach_mission.stage,"steps":steps,"targets":targets,"survivors":ids.filter(func(id):return g._get_entity(id).alive),"outcome":g.outcome}))
 await shot(g,"04-enemy-keep-victory",Vector3(25,0,-24))
 var report={"build":Rules.BUILD_ID,"driver_sha256":FileAccess.get_sha256(get_script().resource_path),"captures":captures,"checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"steps":steps,"tick":g.tick_count,"scope":"Continuous actual authored scenario with normal player orders against observed targets. No HP/resource/spawn/fog/result/AI flag overrides. Only four render points; no natural human or physical phone claim."}
 for p in ["game","breach_mission","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 g.free();await process_frame
 print(JSON.stringify({"suite":"breach_mission_journey","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Actual authored scenario opening, simulated player uses ordinary commands against observed targets; no HP/resource/vision/spawn mutation or AI flag override."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
