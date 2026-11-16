extends SceneTree
const Policy=preload("res://scripts/ai_infrastructure_repair.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var tower={"id":1,"owned":true,"alive":true,"remembered":false,"team":1,"category":"building","kind":"tower","built":true,"hp":300,"max_hp":600,"last_damage_tick":0,"pos":Vector3.ZERO}
 var barracks=tower.duplicate(true);barracks.id=2;barracks.kind="barracks";barracks.hp=100
 check("tower defense restored before production",Policy.target([barracks,tower],100).get("id",-1)==1)
 check("ordinary five second lockout",Policy.target([tower],99).is_empty())
 var before=tower.duplicate(true);Policy.target([tower],100)
 check("pure observation not changed",tower==before)
 tower.hp=451
 check("light damage not priority",Policy.target([tower],100).is_empty())
 tower.hp=300;tower.remembered=true
 check("remembered building not selected",Policy.target([tower],100).is_empty())
 tower.remembered=false
 var e={"id":3,"alive":true,"remembered":false,"team":0,"category":"unit","pos":Vector3(10,0,0)}
 check("visible threat prevents repair expedition",Policy.target([tower,e],100).is_empty())
 e.remembered=true
 check("hidden enemy not consulted",not Policy.target([tower,e],100).is_empty())
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 var home=g._first(1,"town_center");var building=g._spawn("tower",1,home.pos+Vector3(-8,0,-1));building.hp=300;building.last_damage_tick=-1000
 var workers=[]
 for w in g.entities:
  if w.team==1 and w.kind=="villager":workers.append(w)
 for i in 2:g._order(workers[i],"gather",g._nearest_resource(workers[i].pos,"food",1).id)
 workers[2].pos=building.pos+Vector3(-2,0,0);g._set_stance(workers[2],"STOP")
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g.ai_claimed_workers={};g.ai_budget=g.economy.bank_milli(1).duplicate()
 check("keep repair retains first priority",not g._ai_infrastructure_repair(g._ai_records(),true) and g.commands.is_empty())
 g.ai_budget.wood=80000
 check("eighty wood reserve protected",not g._ai_infrastructure_repair(g._ai_records()) and g.commands.is_empty())
 g.ai_budget=g.economy.bank_milli(1).duplicate()
 var bank=g.economy.bank_milli(1).wood
 g.ai_opening_assigned=true;g._ai_update()
 check("full AI turn queues damaged tower repair",g.commands.any(func(c):return c.type=="order" and c.target==building.id))
 var orders=g.commands.filter(func(c):return c.type=="order" and c.target==building.id)
 check("nearest empty nonfood worker selected",orders.size()==1 and orders[0].ids==[workers[2].id])
 check("later strategic decisions preserve repair worker",g.commands.filter(func(c):return c.type=="order" and workers[2].id in c.get("ids",[])).size()==1)
 check("request is not free healing",building.hp==300 and g.economy.bank_milli(1).wood==bank)
 g.commands=orders.duplicate(true)
 for i in 200:
  g._tick(.05)
  if building.hp>300:break
 check("real repair increases HP and pays wood",building.hp>300 and g.economy.bank_milli(1).wood<bank)
 g._publish_faction_views();g.commands.clear();g.ai_claimed_workers={};g.ai_budget=g.economy.bank_milli(1).duplicate()
 g._ai_infrastructure_repair(g._ai_records())
 check("active repair protected from economy reassignment",g.ai_claimed_workers.get(workers[2].id,"")=="repair" and g.commands.is_empty())
 var reduced=g._ai_records().filter(func(r):return r.id not in [workers[0].id,workers[1].id])
 g._ai_infrastructure_repair(reduced)
 check("food and workforce collapse retires discretionary repair",g.commands.any(func(c):return c.type=="stop" and workers[2].id in c.ids))
 g.commands.clear()
 g.ai_budget.wood=80000;g._ai_infrastructure_repair(g._ai_records())
 check("reserve exhaustion requests ordinary stop",g.commands.any(func(c):return c.type=="stop" and workers[2].id in c.ids))
 g._tick(.05)
 check("stop actually retires repair job",workers[2].state!="repair")
 check("ledger remains conserved",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_infrastructure_repair_contract","checks":checks,"failed":failed,"scope":"Controlled damaged building and real paid repair; not natural-match balance"}));g.queue_free();quit(1 if failed else 0)
