extends SceneTree
const Tactics=preload("res://scripts/raid_tactics.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var attacker={"id":1,"owned":true,"alive":true,"remembered":false,"team":1,"category":"unit","kind":"siege","pos":Vector3.ZERO,"state":"idle","target":-1}
 var tower={"id":2,"owned":false,"alive":true,"remembered":false,"team":0,"category":"building","kind":"tower","pos":Vector3(3,0,0),"radius":1.0,"built":true}
 var keep={"id":3,"owned":false,"alive":true,"remembered":false,"team":0,"category":"building","kind":"town_center","pos":Vector3(8,0,0),"radius":1.0,"built":true}
 check("nearby visible completed tower is siege objective",Tactics.siege_target(attacker,[tower],keep).get("id",-1)==2)
 var near_keep=keep.duplicate();near_keep.pos=Vector3(1,0,0)
 check("keep already in striking range keeps priority",Tactics.siege_target(attacker,[tower],near_keep).is_empty())
 for field in ["remembered","owned"]:
  var invalid=tower.duplicate();invalid[field]=true
  check(field+" tower cannot be targeted",Tactics.siege_target(attacker,[invalid],keep).is_empty())
 for field in ["alive","built"]:
  var invalid=tower.duplicate();invalid[field]=false
  check(field+" false tower cannot be targeted",Tactics.siege_target(attacker,[invalid],keep).is_empty())
 var distant=tower.duplicate();distant.pos=Vector3(Rules.SIGHT.siege+1,0,0)
 check("shared distant sight cannot divert siege",Tactics.siege_target(attacker,[distant],keep).is_empty())
 var house=tower.duplicate();house.kind="house"
 check("civilian buildings do not distract siege",Tactics.siege_target(attacker,[house],keep).is_empty())
 var wrong=attacker.duplicate();wrong.kind="archer"
 check("escorts retain their separate unit tactics",Tactics.siege_target(wrong,[tower],keep).is_empty())
 var current=tower.duplicate();current.id=4;current.pos=Vector3(4,0,0);attacker.state="attack";attacker.target=4
 check("equivalent local current target is stable",Tactics.siege_target(attacker,[tower,current],keep).get("id",-1)==4)
 var original=attacker.duplicate(true);var tower_original=tower.duplicate(true)
 Tactics.siege_target(attacker,[tower],keep)
 check("planning does not mutate observations",attacker==original and tower==tower_original)
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game.ai_enabled=false
 game._test_reset();game.set_process(false);await process_frame
 var real_keep=game._first(0,"town_center");var pos=real_keep.pos+Vector3(4.5,0,0)
 var siege=game._spawn("siege",1,pos);var defense=game._spawn("tower",0,pos+Vector3(1.8,0,0));defense.built=true;defense.hp=1
 game._update_vision()
 var records=game._ai_records();var observed=game.faction_views[1].get_record(siege.id);var objective=game.faction_views[1].get_record(real_keep.id)
 check("controlled fixture actually observes tower and keep",not objective.is_empty() and not game.faction_views[1].get_record(defense.id).is_empty())
 game._ai_raid_order(observed,records,objective)
 check("normal AI submits tower order without direct authority mutation",game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==defense.id and siege.id in c.get("ids",[])))
 game._tick(Rules.TICK)
 check("ordinary siege settlement destroys controlled one HP tower",not defense.alive)
 game._ai_raid_order(game.faction_views[1].get_record(siege.id),game._ai_records(),game.faction_views[1].get_record(real_keep.id))
 check("siege resumes keep after tower destroyed",game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==real_keep.id and siege.id in c.get("ids",[])))
 check("tactical change preserves economy ledger",game.economy.audit().ok)
 game.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"siege_tactics_contract","checks":checks,"failed":failed,"scope":"Controlled spawned battlefield and one HP tower; normal queued attack settlement, not natural match victory"}))
 quit(1 if failed else 0)
