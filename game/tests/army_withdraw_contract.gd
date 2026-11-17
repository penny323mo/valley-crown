extends SceneTree
const Rules=preload("res://scripts/rules.gd")
const Formation=preload("res://scripts/army_formation.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():await process_frame;await process_frame
func tap(p):
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.position=p;e.index=4;e.pressed=down;root.push_input(e);await process_frame
func run():
 root.size=Vector2i(960,640)
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;await settle()
 var worker=g._first(0,"villager");var resource={};var best=INF
 for r in g.faction_views[0].records().values():
  if r.kind=="berry" and not r.remembered and r.pos.distance_to(worker.pos)<best:best=r.pos.distance_to(worker.pos);resource=r
 g._submit("order",{"ids":[worker.id],"target":resource.id,"position":resource.pos});g._tick(Rules.TICK)
 var troops=[]
 for i in 3:troops.append(g._spawn(["spearman","archer","siege"][i],0,Vector3(8+i*2,0,-3)))
 var foe=g._spawn("archer",1,Vector3(8,0,-6));var untouched=g._spawn("scout",0,Vector3(14,0,-3))
 g._update_vision();g._publish_faction_views();g.camera_focus=Vector3(10,0,-1);g.camera_zoom=22;g._camera_update();g._layout_ui();await settle()
 # A real engagement precedes the withdrawal; neither side is made harmless.
 g._order(troops[1],"attack",foe.id);g._order(foe,"attack",troops[0].id)
 for i in 2:g._tick(Rules.TICK)
 var pre_shot=false
 for aid in range(1,g.attack_ledger.next_attack_id()):
  if g.attack_ledger.event(aid).attacker_id==troops[1].id:pre_shot=true
 check("selected archer actually fired before withdrawal",pre_shot)
 var ids=[worker.id,troops[0].id,troops[1].id,troops[2].id]
 var dest=Vector3(10,0,5);var plan=Formation.plan(troops,dest,"line",true)
 check("withdraw places siege ahead of archer and melee",plan[troops[2].id].z>plan[troops[1].id].z and plan[troops[1].id].z>plan[troops[0].id].z)
 var normal=Formation.plan(troops,dest,"line")
 check("ordinary advance formation stays melee first",normal[troops[0].id].z>normal[troops[1].id].z)
 troops.reverse();check("withdraw slots independent of selection order",plan==Formation.plan(troops,dest,"line",true));troops.reverse()
 var epoch=worker.work_epoch;var target=worker.target;var unepoch=untouched.work_epoch;var unmode=untouched.mode
 var original=troops[0].mode
 check("bad coordinates rejected before mutation",not g._order_withdraw(ids,Vector3.INF,0) and troops[0].mode==original)
 check("bad id rejects entire batch",not g._order_withdraw([troops[0].id,"invalid"],dest,0) and troops[0].mode==original)
 check("outside map rejected",not g._order_withdraw(ids,Vector3(100,0,0),0))
 g._select(ids);g._update_hud();await settle()
 var button=g.find_child("ArmyWithdraw",true,false);check("mixed army exposes withdraw action",is_instance_valid(button))
 button.pressed.emit();await settle();check("withdraw action arms destination mode",g.touch_command and g.unit_command_kind=="withdraw" and g.selection_detail.text.contains("仍會受傷"))
 var screen=g.camera.unproject_position(dest);check("destination is world input",g._box_point_in_world(screen));await tap(screen)
 check("real touch submits one authoritative withdraw",g.commands.size()==1 and g.commands[0].type=="withdraw")
 check("destination completion clears transient targeting",not g.touch_command and g.unit_command_kind=="order")
 var cooldown_before=troops[1].cooldown_ticks
 g._tick(Rules.TICK)
 check("withdraw does not reset attack cooldown",troops[1].cooldown_ticks==maxi(0,cooldown_before-1))
 check("all military use ordinary MOVE",troops.all(func(u):return u.mode=="MOVE" and u.target==-1))
 check("worker and unselected scout unchanged",worker.work_epoch==epoch and worker.target==target and untouched.work_epoch==unepoch and untouched.mode==unmode)
 var destinations={}
 for u in troops:destinations[g._cell(u.dest)]=true
 check("ordinary destination reservations do not overlap",destinations.size()==3 and troops.all(func(u):return u.dest.is_finite()))
 # Enemy keeps attacking while a moving withdrawn unit cannot shoot back.
 g._order(foe,"attack",troops[0].id);var hp=troops[0].hp;var starts={};var moved=false;var moving_shot=false
 for u in troops:starts[u.id]=u.pos
 var old_attack=g.attack_ledger.next_attack_id()
 for i in 70:
  var moving=[]
  for u in troops:
   if u.state=="move" and u.mode=="MOVE":moving.append(u.id)
  g._tick(Rules.TICK)
  for attack_id in range(old_attack,g.attack_ledger.next_attack_id()):
   var event=g.attack_ledger.event(attack_id)
   if event.get("attacker_id",-1) in moving:moving_shot=true
  old_attack=g.attack_ledger.next_attack_id()
  for u in troops:
   if u.pos.distance_to(starts[u.id])>1:moved=true
 check("ordinary ticks move withdrawn army",moved)
 check("withdraw does not grant immunity",troops[0].hp<hp)
 check("moving retreat does not become advance fire",not moving_shot)
 var arrival=false
 for i in 200:
  g._tick(Rules.TICK)
  if troops.all(func(u):return u.alive and u.mode=="STOP" and u.pos.distance_to(u.dest)<1.5):arrival=true;break
 check("withdrawal reaches reserved destinations in ordinary ticks",arrival)
 check("arrival uses existing stop stance not a new retreat state",troops.all(func(u):return u.mode=="STOP"))
 print("WITHDRAW_DIAGNOSTIC tick=",g.tick_count," hp=",troops.map(func(u):return u.hp)," positions=",troops.map(func(u):return u.pos)," destinations=",troops.map(func(u):return u.dest))
 # Execute-time stale target membership never touches dead or enemy units.
 var live=troops[1];g._submit("withdraw",{"ids":[live.id,foe.id],"position":Vector3(10,0,8)});g._kill(live);var enemy_dest=foe.dest;g._tick(Rules.TICK)
 check("execution ignores dead or enemy membership",not live.alive and foe.dest==enemy_dest)
 g._select([troops[0].id]);g._start_withdraw_command();var count=g.commands.size();g._cancel_mode();check("cancel emits no retreat",g.commands.size()==count and not g.touch_command)
 g.paused=true;g._start_withdraw_command();check("pause cannot arm retreat",not g.touch_command);g.paused=false
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await settle();g._start_withdraw_command();await settle()
  check("withdraw readable and cancel present "+str(size),g.touch_command and g.selection_detail.text.contains("整隊撤離") and g.actions.get_child_count()>0)
  g._cancel_mode()
 g.free();await settle()
 print(JSON.stringify({"suite":"army_withdraw_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Controlled native synthetic touch and ordinary combat ticks; no physical-phone, natural match or guaranteed safe retreat claim."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
