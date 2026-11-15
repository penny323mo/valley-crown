extends SceneTree
const Veteran=preload("res://scripts/combat_veterancy.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func soldier(id,team,kind="spearman"):
 return {"id":id,"team":team,"kind":kind,"category":"unit","alive":true,"hp":10}
func run():
 var units={1:soldier(1,0),2:soldier(2,1),3:soldier(3,0)}
 var lookup=func(id):return units.get(id,{})
 var v=Veteran.new()
 var events=[{"attack_id":1,"attacker_id":1,"target_id":2,"damage":10}]
 v.settle(events,{2:10},lookup);check("settled enemy military kill earns one credit",v.count(1)==1)
 v.settle(events,{2:10},lookup);check("same attack IDs cannot award twice",v.count(1)==1)
 v.settle([{"attack_id":2,"attacker_id":1,"target_id":2,"damage":1}],{2:1},lookup)
 check("nonlethal hit does not grant experience",v.count(1)==1)
 units[2].kind="villager";v.settle([{"attack_id":3,"attacker_id":1,"target_id":2,"damage":10}],{2:10},lookup)
 check("worker kills cannot farm ranks",v.count(1)==1)
 units[2].kind="tower";units[2].category="building";v.settle([{"attack_id":4,"attacker_id":1,"target_id":2,"damage":10}],{2:10},lookup)
 check("building kills excluded",v.count(1)==1)
 units[2]=soldier(2,1)
 v.settle([{"attack_id":5,"attacker_id":1,"target_id":2,"damage":4},{"attack_id":6,"attacker_id":3,"target_id":2,"damage":6}],{2:10},lookup)
 check("largest settled contribution gets exactly one kill",v.count(1)==1 and v.count(3)==1)
 v.settle([{"attack_id":7,"attacker_id":3,"target_id":2,"damage":5},{"attack_id":8,"attacker_id":1,"target_id":2,"damage":5}],{2:10},lookup)
 check("equal contribution breaks tie by stable lower ID",v.count(1)==2 and v.count(3)==1)
 v.settle([{"attack_id":9,"attacker_id":1,"target_id":2,"damage":10}],{2:10,1:10},lookup)
 check("simultaneously killed attacker earns no rank",v.count(1)==2)
 v.settle([{"attack_id":10,"attacker_id":1,"target_id":2,"damage":10}],{2:10},lookup)
 check("three credited kills promote veteran",v.count(1)==3 and v.rank(1)==1)
 for i in range(11,16):v.settle([{"attack_id":i,"attacker_id":1,"target_id":2,"damage":10}],{2:10},lookup)
 check("six kills promote elite and bonus caps at two",v.count(1)==8 and v.rank(1)==2)
 v.settle([{"attack_id":16,"attacker_id":2,"target_id":3,"damage":10}],{3:10},lookup)
 check("AI faction earns the same combat progression",v.count(2)==1)
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game.ai_enabled=false;game._test_reset();game.set_process(false);await process_frame
 var fighter=game._spawn("spearman",0,Vector3.ZERO)
 for i in 3:
  var target=game._spawn("spearman",1,Vector3(0.7,0,0));target.hp=1;fighter.cooldown_ticks=0
  game._update_vision();game._submit("order",{"ids":[fighter.id],"target":target.id,"position":target.pos},0);game._tick(Rules.TICK)
 check("three actual queued combat settlements promote troop",game.combat_veterancy.count(fighter.id)==3 and game.combat_veterancy.rank(fighter.id)==1)
 var target=game._spawn("spearman",1,Vector3(0.7,0,0));game._update_vision();fighter.cooldown_ticks=0
 var released=game._release_attack(fighter,target)
 check("next authoritative attack includes earned plus one",released.applied and released.event.damage==Rules.CONTENT.resolve_damage("spearman","spearman").damage+1)
 game.military_tech_completed[0].forged_blades=-1;fighter.cooldown_ticks=0
 var upgraded=game._release_attack(fighter,target)
 check("earned rank stacks with existing attack research",upgraded.applied and upgraded.event.damage==Rules.CONTENT.resolve_damage("spearman","spearman").damage+3)
 game.military_tech_completed[1].reinforced_armor=-1;fighter.cooldown_ticks=0
 var defended=game._release_attack(fighter,target)
 check("opponent researched armour still reduces veteran hit",defended.applied and defended.event.damage==upgraded.event.damage-1)
 check("already released hit remains frozen after armour change",game.attack_ledger.event(upgraded.event.attack_id).damage==upgraded.event.damage)
 game._publish_faction_views();var record=game.faction_views[0].get_record(fighter.id)
 check("observed unit exposes earned rank and progress",record.combat_kills==3 and record.veterancy_rank==1)
 game._select([fighter.id]);game._update_hud()
 check("selection HUD explains veteran attack bonus",game.selection_detail.text.contains("老兵") and game.selection_detail.text.contains("攻擊 +1"))
 check("combat progression does not create resources",game.economy.audit().ok)
 game._test_reset()
 check("new match clears all ranks",game.combat_veterancy.kills.is_empty() and game.combat_veterancy.settled_through==0)
 game.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"combat_veterancy_contract","checks":checks,"failed":failed,"scope":"Native controlled combat and settled event accounting, not natural campaign or phone evidence"}))
 quit(1 if failed else 0)
