extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Controlled spawned siege/wall/archer, ordinary practice ticks and commands. Same fresh starting configuration except target policy. Not natural training/economic progression or universal survival buff; no HP/damage/terrain/fog overrides. No physical phone/browser verification."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"pass":bool(b)});return bool(b)
func shot(g,siege,wall,enemy,name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await process_frame;await process_frame
 var row={"name":name,"policy":siege.target_policy,"tick":g.tick_count,"siege_hp":siege.hp,"wall_hp":wall.hp,"wall_alive":wall.alive,"archer_hp":enemy.hp,"archer_alive":enemy.alive,"siege_position":str(siege.pos),"siege_target":siege.target,"bank":g.economy.bank_milli(0),"camera":str(g.camera_focus),"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func battle(policy):
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.history_path=out+"/"+policy+"-history.json";root.add_child(g);g.set_process(false);g.ai_enabled=false;await process_frame
 var siege=g._spawn("siege",0,Vector3(8,0,-2.2));var wall=g._spawn("wall",1,Vector3(8,0,0));var enemy=g._spawn("archer",1,Vector3(6.8,0,-2.2))
 g._navigation_rebuild();g._update_vision();g._publish_faction_views();g._select([siege.id]);g.camera_focus=Vector3(8,0,0);g.camera_zoom=15;g._camera_update();g._layout_ui()
 var bank=g.economy.bank_milli(0).duplicate(true)
 check(policy+" full health starting fixture",wall.hp==250 and siege.hp==siege.max_hp and enemy.hp==40)
 g._submit("advance",{"ids":[siege.id],"position":Vector3(8,0,4)})
 g._submit("target_policy",{"ids":[siege.id],"policy":policy})
 var first="";var moves_ok=true
 for i in 101:
  var pos=siege.pos;g._tick(Rules.TICK);moves_ok=moves_ok and pos.distance_to(siege.pos)<=Rules.SPEED.siege*Rules.TICK+.0001
  if first.is_empty():
   if wall.hp<wall.max_hp:first="wall"
   elif enemy.hp<enemy.max_hp:first="unit"
 check(policy+" first target",first==("wall" if policy=="counter" else "unit"))
 await shot(g,siege,wall,enemy,"01-nearest-at101" if policy=="nearest" else "02-counter-at101")
 if policy=="counter":
  for i in 369:
   if not wall.alive:break
   var pos=siege.pos;g._tick(Rules.TICK);moves_ok=moves_ok and pos.distance_to(siege.pos)<=Rules.SPEED.siege*Rules.TICK+.0001
  check("wall broken normally",not wall.alive and siege.alive and enemy.hp==40)
  check("wall navigation opened",not g.navigation.is_point_solid(g._cell(wall.pos)))
  await shot(g,siege,wall,enemy,"03-counter-wall-breached")
  g._submit("order",{"ids":[siege.id],"target":-1,"position":Vector3(8,0,3.5)})
  for i in 200:
   var pos=siege.pos;g._tick(Rules.TICK);moves_ok=moves_ok and pos.distance_to(siege.pos)<=Rules.SPEED.siege*Rules.TICK+.0001
   if siege.pos.z>1.5:break
  check("ordinary movement crosses",siege.pos.z>1.5 and siege.alive)
  await shot(g,siege,wall,enemy,"04-counter-crossed-gap")
 check(policy+" unchanged bank and movement speed",g.economy.bank_milli(0)==bank and moves_ok)
 var valid=true;var last=-1;var events=[]
 for id in range(1,g.attack_ledger.next_attack_id()):
  var e=g.attack_ledger.event(id)
  if e.attacker_id!=siege.id:continue
  valid=valid and e.damage==Rules.CONTENT.resolve_damage("siege","wall" if e.target_id==wall.id else "archer").damage and (last<0 or e.release_tick-last>=Rules.ATTACK_TICKS.siege)
  last=e.release_tick;events.append({"tick":e.release_tick,"damage":e.damage,"target":e.target_id})
 check(policy+" unchanged damage cooldown",valid and not events.is_empty());report[policy+"_releases"]=events
 g.free();await process_frame
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v93-siege-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(960,540);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["game","target_priority","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 await battle("nearest");await battle("counter")
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
