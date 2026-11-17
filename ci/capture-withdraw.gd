extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var worker
var troops=[]
var out=""
var checks=[]
var metadata_only=false
var report={"captures":[],"scope":"Controlled spawned three military types and enemy archer; ordinary starting villager keeps gather intent. Actual pre-withdraw combat, routed touch destination, ordinary movement and incoming damage. NOT guaranteed safe retreat or formation preservation along path. No natural recruitment or physical phone claim."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"pass":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func touch(p,down):
 var e=InputEventScreenTouch.new();e.position=p;e.index=10;e.pressed=down;root.push_input(e);await process_frame
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await settle()
 var units=[]
 for u in [worker]+troops:units.append({"id":u.id,"kind":u.kind,"position":str(u.pos),"state":u.state,"target":u.target,"work_epoch":u.get("work_epoch",-1),"hp":u.hp,"mode":u.mode,"dest":str(u.dest)})
 var row={"name":name,"tick":g.tick_count,"selected":g.selected.duplicate(),"title":g.selection_title.text,"summary":g.selection_summary.text,"box_mode":g.box_select_mode,"military_only":g.box_select_military_only,"units":units,"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v96-withdraw-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(960,640);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["game","army_formation","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 worker=g._first(0,"villager");var resource={};var best=INF
 for r in g.faction_views[0].records().values():
  if r.kind=="berry" and not r.remembered and r.pos.distance_to(worker.pos)<best:best=r.pos.distance_to(worker.pos);resource=r
 if not check("normal visible gather target",not resource.is_empty()):finish();return
 g._submit("order",{"ids":[worker.id],"target":resource.id,"position":resource.pos});g._tick(Rules.TICK)
 for i in 3:troops.append(g._spawn(["spearman","archer","siege"][i],0,Vector3(8+i*2,0,-3)))
 var foe=g._spawn("archer",1,Vector3(8,0,-6))
 g._update_vision();g._publish_faction_views();g.camera_focus=Vector3(10,0,-1);g.camera_zoom=22;g._camera_update();g._layout_ui();await settle()
 g._order(troops[1],"attack",foe.id);g._order(foe,"attack",troops[0].id)
 for i in 2:g._tick(Rules.TICK)
 var fired=false
 for aid in range(1,g.attack_ledger.next_attack_id()):
  if g.attack_ledger.event(aid).attacker_id==troops[1].id:fired=true
 check("real attack before withdrawal",fired)
 g._select([worker.id,troops[0].id,troops[1].id,troops[2].id]);g._update_hud();await settle()
 var button=g.find_child("ArmyWithdraw",true,false);g.action_scroll.ensure_control_visible(button);await settle()
 await shot("01-before-withdraw-real-combat")
 var epoch=worker.work_epoch;var target=worker.target
 button.pressed.emit();await settle()
 check("actual withdraw destination mode",g.touch_command and g.unit_command_kind=="withdraw")
 var screen=g.camera.unproject_position(Vector3(10,0,5))
 if not check("destination world input",g._box_point_in_world(screen)):finish();return
 await touch(screen,true)
 await shot("02-touch-withdraw-destination")
 await touch(screen,false)
 check("routed touch authoritative withdraw",g.commands.size()==1 and g.commands[0].type=="withdraw")
 g._tick(Rules.TICK)
 check("ordinary MOVE only troops",troops.all(func(u):return u.mode=="MOVE" and u.target==-1) and worker.work_epoch==epoch and worker.target==target)
 g._order(foe,"attack",troops[0].id);var hp=troops[0].hp;var moving_shot=false;var old_attack=g.attack_ledger.next_attack_id()
 for i in 70:
  var moving=[]
  for u in troops:
   if u.state=="move" and u.mode=="MOVE":moving.append(u.id)
  g._tick(Rules.TICK)
  for aid in range(old_attack,g.attack_ledger.next_attack_id()):
   if g.attack_ledger.event(aid).attacker_id in moving:moving_shot=true
  old_attack=g.attack_ledger.next_attack_id()
 check("still takes incoming damage",troops[0].hp<hp)
 check("moving withdrawal no return shots",not moving_shot)
 await shot("03-withdraw-under-fire")
 var arrived=false
 for i in 200:
  g._tick(Rules.TICK)
  if troops.all(func(u):return u.alive and u.mode=="STOP" and u.pos.distance_to(u.dest)<1.5):arrived=true;break
 check("ordinary arrival",arrived)
 await shot("04-arrived-existing-stop")
 report.enemy_final_hp=foe.hp
 finish()
