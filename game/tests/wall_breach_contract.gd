extends SceneTree
const Policy=preload("res://scripts/wall_breach_policy.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func attacker(kind="siege"):
 return {"id":1,"owned":true,"alive":true,"remembered":false,"team":1,"category":"unit","kind":kind,"pos":Vector3(0,0,-2),"state":"move","target":-1}
func wall():return {"id":2,"owned":false,"alive":true,"remembered":false,"team":0,"category":"building","kind":"wall","pos":Vector3.ZERO,"built":true}
func keep():return {"id":3,"owned":false,"alive":true,"remembered":true,"team":0,"category":"building","kind":"town_center","pos":Vector3(0,0,10)}
func run():
 var a=attacker();var w=wall();var k=keep()
 check("contact forward wall chosen",Policy.choose(a,[w],k).get("id",-1)==2)
 for kind in ["spearman","cavalry","siege"]:check(kind+" can breach at contact",Policy.choose(attacker(kind),[w],k).get("id",-1)==2)
 for kind in ["villager","scout","archer"]:check(kind+" retains original task",Policy.choose(attacker(kind),[w],k).is_empty())
 for field in ["remembered","alive","owned","team","category","kind"]:
  var bad=w.duplicate(true)
  bad[field]={"remembered":true,"alive":false,"owned":true,"team":1,"category":"unit","kind":"house"}[field]
  check("wall guard "+field,Policy.choose(a,[bad],k).is_empty())
 for field in ["remembered","alive","owned","team","category"]:
  var bad=a.duplicate(true)
  bad[field]={"remembered":true,"alive":false,"owned":false,"team":0,"category":"building"}[field]
  check("attacker guard "+field,Policy.choose(bad,[w],k).is_empty())
 var distant=w.duplicate(true);distant.pos=Vector3(0,0,2)
 check("distant wall never triggers path search",Policy.choose(a,[distant],k).is_empty())
 var side=w.duplicate(true);side.pos=Vector3(2,0,-2)
 check("in reach side wall does not distract",Policy.choose(a,[side],k).is_empty())
 var rear=w.duplicate(true);rear.pos=Vector3(0,0,-4)
 check("in reach rear wall does not distract",Policy.choose(a,[rear],k).is_empty())
 var unfinished=w.duplicate(true);unfinished.built=false
 check("unfinished physical wall can be breached",Policy.choose(a,[unfinished],k).id==2)
 var nearby=k.duplicate(true);nearby.pos=Vector3(0,0,0.5);nearby.remembered=false
 check("attackable keep retains priority",Policy.choose(a,[w],nearby).is_empty())
 check("no known keep means no invented goal",Policy.choose(a,[w],{}).is_empty())
 check("wall ray crossing is geometric not center proximity",Policy.blocks_forward(Vector3(-3,0,-3),Vector3(3,0,3),Vector3.ZERO))
 check("parallel clear corridor remains clear",not Policy.blocks_forward(Vector3(2,0,-3),Vector3(2,0,3),Vector3.ZERO))
 var old=a.duplicate(true);old.state="attack";old.target=4
 var second=w.duplicate(true);second.id=4
 check("existing equivalent wall target stable",Policy.choose(old,[w,second],k).id==4)
 check("deterministic id tie break",Policy.choose(a,[second,w],k).id==2)
 # Controlled integration fixture is not a claim of normal economic play.
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.history_path="/tmp/wall-breach-"+str(Time.get_ticks_usec());root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 var unit=g._spawn("siege",1,Vector3(0,0,-2),true);var site=g._spawn("wall",0,Vector3.ZERO,true)
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 var record=g.faction_views[1].get_record(unit.id);var observed=g.faction_views[1].get_record(site.id)
 check("true faction observation exposes wall shape",not observed.is_empty() and observed.kind=="wall" and not observed.get("remembered",true))
 var records=g.faction_views[1].records().values();var goal=k.duplicate(true)
 g.commands.clear();g._ai_raid_order(record,records,goal)
 check("actual raid submits ordinary wall attack",g.commands.size()==1 and g.commands[0].type=="order" and g.commands[0].target==site.id)
 if not g.commands.is_empty():g._execute(g.commands.pop_front())
 g._publish_faction_views();record=g.faction_views[1].get_record(unit.id)
 g.commands.clear();g._ai_raid_order(record,g.faction_views[1].records().values(),goal)
 check("same wall target does not renew command epoch",g.commands.is_empty())
 var hp=site.hp
 unit.cooldown_ticks=0;var outcome=g._release_attack(unit,site)
 check("ordinary siege wall release uses building bonus",outcome.get("applied",false))
 # The attack ledger applies damage only on regular ticks.
 for i in 10:g._tick(g.Rules.TICK)
 check("normal attack damages wall",site.hp<hp)
 var guard=g._spawn("spearman",0,Vector3(-1.8,0,-2),true)
 g._update_vision(false);g._publish_faction_views()
 var horse=g._spawn("cavalry",1,Vector3(0,0,-2),true)
 g._update_vision(false);g._publish_faction_views();g.commands.clear()
 g._ai_raid_order(g.faction_views[1].get_record(horse.id),g.faction_views[1].records().values(),goal)
 check("visible defender retains priority before contact wall",g.commands.size()==1 and g.commands[0].target==guard.id)
 var fake=g.faction_views[1].get_record(unit.id).duplicate(true);fake.state="attack";fake.target=site.id
 var hidden_site=g.faction_views[1].get_record(site.id).duplicate(true);hidden_site.remembered=true
 g.commands.clear();g._ai_raid_order(fake,[hidden_site],goal)
 check("hidden old wall is not renewed and ground goal resumes",g.commands.size()==1 and g.commands[0].target==-1)
 var dead_site=hidden_site.duplicate(true);dead_site.remembered=false;dead_site.alive=false
 g.commands.clear();g._ai_raid_order(fake,[dead_site],goal)
 check("destroyed old wall is not renewed and ground goal resumes",g.commands.size()==1 and g.commands[0].target==-1)
 var archer=attacker("archer");archer.id=unit.id;archer.state="idle"
 g.commands.clear();g._ai_raid_order(archer,[],goal);var baseline=g.commands.duplicate(true)
 g.commands.clear();g._ai_raid_order(archer,[observed],goal)
 check("archer original target unchanged by contact wall",g.commands.size()==baseline.size() and g.commands[0].target==baseline[0].target and g.commands[0].position==baseline[0].position)
 check("controlled integration never writes history",g.test_mode and not FileAccess.file_exists(g.history_path))
 g.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"wall_breach_contract","checks":checks,"failed":failed,"scope":"Pure current-visible contact policy and controlled real raid integration; not a natural battle or global wall-routing solver"}));quit(1 if failed else 0)
