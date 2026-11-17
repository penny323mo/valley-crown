extends SceneTree
const Priority=preload("res://scripts/target_priority.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func fresh():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.history_path="/tmp/v93-history-"+str(Time.get_ticks_usec());root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;return g
func run():
 var unit={"id":2,"kind":"archer","category":"unit"}
 for kind in Rules.CONTENT.building_kinds():
  var building={"id":3,"kind":kind,"category":"building"}
  check("siege ranking matches authoritative bonus "+kind,Priority.bonus("siege",building)==Rules.CONTENT.resolve_damage("siege",kind).bonus and Priority.better("siege","counter",building,unit,1.2,.8))
 check("nearest siege behavior unchanged",not Priority.better("siege","nearest",{"id":3,"kind":"wall","category":"building"},unit,1.2,.8))
 check("invalid category and building kinds have no bonus",Priority.bonus("siege",{"kind":"wall","category":"unit"})==0 and Priority.bonus("siege",{"kind":"unknown","category":"building"})==0)
 check("ordinary unit counter still matches resolver",Priority.bonus("spearman",{"kind":"cavalry","category":"unit"})==Rules.CONTENT.resolve_damage("spearman","cavalry").bonus)
 await battle("nearest")
 await battle("counter")
 await boundaries()
 print(JSON.stringify({"suite":"siege_target_priority_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Controlled native siege/archer/wall fixture, ordinary tick damage and post-breach movement; no new save fields or natural-match claim."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
func battle(policy):
 var g=fresh();await process_frame
 var siege=g._spawn("siege",0,Vector3(8,0,-2.2));var wall=g._spawn("wall",1,Vector3(8,0,0));var enemy=g._spawn("archer",1,Vector3(6.8,0,-2.2))
 g._navigation_rebuild();g._update_vision();g._publish_faction_views()
 g._submit("advance",{"ids":[siege.id],"position":Vector3(8,0,4)})
 g._submit("target_policy",{"ids":[siege.id],"policy":policy})
 var first="";var wall_death=-1;var before_bank=g.economy.bank_milli(0).duplicate(true);var moves_ok=true
 for i in 470:
  var pos=siege.pos;g._tick(Rules.TICK)
  moves_ok=moves_ok and siege.pos.distance_to(pos)<=Rules.SPEED.siege*Rules.TICK+.0001
  if first.is_empty():
   if wall.hp<wall.max_hp:first="wall"
   elif enemy.hp<enemy.max_hp:first="unit"
  if not wall.alive:wall_death=g.tick_count;break
 check(policy+" ordinary tick hits intended first target",first==("wall" if policy=="counter" else "unit"))
 check(policy+" no free resources or changed movement speed",g.economy.bank_milli(0)==before_bank and moves_ok)
 if policy=="counter":
  check("counter actually destroys full health wall through ordinary combat",wall_death>=0 and siege.alive and enemy.alive)
  var cell=g._cell(wall.pos)
  check("destroyed wall releases real navigation cells",not g.navigation.is_point_solid(cell))
  g._submit("order",{"ids":[siege.id],"target":-1,"position":Vector3(8,0,3.5)})
  var crossed=false
  for i in 200:
   var pos=siege.pos;g._tick(Rules.TICK)
   moves_ok=moves_ok and siege.pos.distance_to(pos)<=Rules.SPEED.siege*Rules.TICK+.0001
   if siege.pos.z>1.5:crossed=true;break
  check("ordinary move crosses former wall footprint without teleport",crossed and moves_ok and siege.alive)
 else:check("nearest retains combat distraction rather than forced wall preference",wall.alive)
 var releases=[];var ledger_ok=true;var last=-1
 for attack_id in range(1,g.attack_ledger.next_attack_id()):
  var event=g.attack_ledger.event(attack_id)
  if event.attacker_id!=siege.id:continue
  var target_kind="wall" if event.target_id==wall.id else "archer"
  ledger_ok=ledger_ok and event.damage==Rules.CONTENT.resolve_damage("siege",target_kind).damage
  if last>=0:ledger_ok=ledger_ok and event.release_tick-last>=Rules.ATTACK_TICKS.siege
  last=event.release_tick;releases.append(event.release_tick)
 check(policy+" ledger preserves exact damage and attack interval",ledger_ok and not releases.is_empty())
 print("SHOT_DIAGNOSTIC ",policy," releases=",releases," wall_death_tick=",wall_death)
 print("BATTLE_DIAGNOSTIC ",policy," first=",first," tick=",g.tick_count," wall_hp=",wall.hp," siege_hp=",siege.hp," enemy_hp=",enemy.hp," pos=",siege.pos)
 g.free();await process_frame
func boundaries():
 var g=fresh();await process_frame
 var siege=g._spawn("siege",0,Vector3(8,0,-2.2));var wall=g._spawn("wall",1,Vector3(8,0,0));var enemy=g._spawn("archer",1,Vector3(6.8,0,-2.2));g._navigation_rebuild();g._update_vision()
 g._order_advance([siege.id],Vector3(8,0,4),0);g._set_target_policy([siege.id],"counter",0)
 check("automatic advance selects visible in range fortification",g._advance_target(siege).get("id",-1)==wall.id)
 wall.pos=Vector3(8,0,2);g._update_vision()
 check("counter does not extend weapon range",g._advance_target(siege).get("id",-1)==enemy.id)
 wall.pos=Vector3(8,0,0);g._update_vision();g.visible_cells[0].fill(0);g.visible_cells[0][g._cell_index(enemy.pos)]=1;g._publish_faction_views()
 var first=g._advance_target(siege).get("id",-1);wall.hp=wall.hp-1;g._publish_faction_views()
 check("remembered wall and hidden health cannot redirect targeting",first==enemy.id and g._advance_target(siege).get("id",-1)==first)
 g._update_vision();g._order(siege,"attack",enemy.id);g._set_target_policy([siege.id],"counter",0)
 var hp=enemy.hp
 for i in 12:g._tick(Rules.TICK)
 check("manual target remains authoritative with counter enabled",siege.target==enemy.id and enemy.hp<hp and wall.hp==wall.max_hp-1)
 check("same existing policy field no new persistent state",siege.target_policy=="counter")
 g.free();await process_frame
