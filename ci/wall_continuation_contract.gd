extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false
 await process_frame
 var soldier=g._spawn("spearman",1,Vector3(0,0,-2),true)
 var wall=g._spawn("wall",0,Vector3.ZERO,true)
 var objective=g._spawn("town_center",0,Vector3(0,0,8),true)
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 var wall_died=-1;var breach_position=Vector3.INF;var regained=false;var reached=false
 for i in 1800:
  if i%20==0:
   var record=g.faction_views[1].get_record(soldier.id)
   var goal=g.faction_views[1].get_record(objective.id)
   if goal.is_empty():goal={"id":objective.id,"kind":"town_center","category":"building","pos":objective.pos,"team":0,"owned":false,"alive":true,"remembered":true,"footprint":4}
   g._ai_raid_order(record,g.faction_views[1].records().values(),goal)
  g._tick(g.Rules.TICK)
  if not wall.alive and wall_died<0:wall_died=g.tick_count;breach_position=soldier.pos
  if wall_died>=0:
   if soldier.state=="attack" and soldier.target==objective.id:regained=true
   if soldier.pos.z>1.1 and soldier.pos.distance_to(objective.pos)<breach_position.distance_to(objective.pos)-1:reached=true
   if objective.hp<objective.max_hp:break
 check("healthy breacher destroys full-health wall with ordinary attacks",wall_died>=0 and wall.hp<=0)
 check("healthy breacher reacquires original keep after destruction",regained)
 check("healthy breacher resumes real motion beyond former barrier",reached)
 check("healthy breacher deals settled damage to original keep",objective.hp<objective.max_hp)
 var wall_damage=0;var keep_damage=0;var first_keep_tick=-1
 for id in range(1,g.attack_ledger.next_attack_id()):
  var e=g.attack_ledger.event(id)
  if e.attacker_id!=soldier.id:continue
  if e.target_id==wall.id:wall_damage+=e.damage
  if e.target_id==objective.id:keep_damage+=e.damage;first_keep_tick=e.get("release_tick",-1)
 check("wall damage confirmed from actual attack ledger",wall_damage>=250)
 check("keep damage confirmed from actual attack ledger",keep_damage>0)
 check("keep damage occurs strictly after wall destruction",first_keep_tick>wall_died)
 # A deliberate critical-health controlled fixture verifies existing recovery
 # precedence, not a claim that natural battle wounds had this source.
 soldier.hp=10
 g._update_vision(false);g._publish_faction_views();g.commands.clear()
 var home=g._first(1,"town_center")
 g.ai_raid_members=[soldier.id];g.ai_raid_departure_count=1
 g._ai_army(g._ai_records(),home)
 var orders=g.commands.filter(func(c):return soldier.id in c.get("ids",[]))
 check("critical post-breach soldier retains ordinary safe-home recovery priority",orders.size()==1 and orders[0].type=="order" and orders[0].target==-1 and orders[0].position==home.pos)
 check("critical post-breach soldier exits offensive raid cohort",soldier.id not in g.ai_raid_members)
 check("no gameplay rules or economy mutation needed for continuation",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"wall_continuation_contract","checks":checks,"failed":failed,"wall_destroyed_tick":wall_died,"wall_damage":wall_damage,"keep_damage":keep_damage,"first_keep_tick":first_keep_tick,"scope":"Controlled real game._tick and ordinary attack/raid orders. Critical hp fixture explicitly assigned only after healthy continuation proof. Not natural crossing/balance proof."}))
 g.free();quit(1 if failed else 0)
