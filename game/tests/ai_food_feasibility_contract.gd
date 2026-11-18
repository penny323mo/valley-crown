extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func c(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func records():
 var rows=[]
 for i in 4:rows.append({"id":900+i,"team":-1,"category":"resource","kind":"berry","alive":true,"owned":false,"remembered":true,"pos":Vector3(0,0,i*.3)})
 return rows
func run():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="standard";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;await process_frame
 g.ai_budget={"food":0,"wood":20960,"iron":0,"stone":0}
 var r=records();var original=r.duplicate(true)
 c("safe remembered food retains ordinary exploration goal",g._ai_progression_goal(r,8,30,8)=="barracks")
 for item in r:item.remembered=false
 c("safe visible food retains ordinary goal",g._ai_progression_goal(r,8,30,8)=="barracks")
 for item in r:item.alive=false
 c("dead berries do not suppress farm",g._ai_progression_goal(r,8,30,8)=="farm")
 r=records();r.append({"id":950,"team":0,"category":"unit","kind":"spearman","alive":true,"owned":false,"remembered":false,"pos":Vector3.ZERO})
 c("observed hostile threat excludes otherwise known food",g._ai_progression_goal(r,8,30,8)=="farm")
 r[-1].remembered=true
 c("remembered enemy is not a hidden live threat oracle",g._ai_progression_goal(r,8,30,8)=="barracks")
 r[-1].remembered=false;r[-1].alive=false
 c("dead enemy does not block safe food",g._ai_progression_goal(r,8,30,8)=="barracks")
 r=records();var w=g._first(1,"villager");var old=w.get("ai_evacuation",{}).duplicate(true)
 w.ai_evacuation={"origin":Vector3.ZERO}
 c("existing owned danger memory excludes food planning",g._ai_progression_goal(r,8,30,8)=="farm")
 c("farm deficit selects ordinary wood funding",g._ai_resource_gap(r,8,30,8)=="wood" and g.ai_status.resource_goal=="farm")
 c("house priority remains above food fallback",g._ai_progression_goal(r,8,10,8)=="house")
 g.ai_budget.food=50000
 c("affordable minimum workforce priority unchanged",g._ai_progression_goal(r,2,30,2)=="villager")
 g.ai_budget.food=0
 for i in 4:r.append({"id":970+i,"team":1,"category":"building","kind":"farm","alive":true,"owned":true,"built":false,"pos":Vector3(10,0,i*3)})
 c("four unfinished farms still cap farm plan",g._ai_progression_goal(r,8,30,8)=="barracks")
 r.pop_back()
 c("three farms still allow final farm",g._ai_progression_goal(r,8,30,8)=="farm")
 w.erase("ai_evacuation")
 var immutable=records();var saved_observations=immutable.duplicate(true)
 g._ai_progression_goal(immutable,8,30,8)
 c("policy does not mutate observations",immutable==saved_observations)
 g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_claimed_workers.clear();g.ai_build_submitted=false
 var before=g.economy.bank_milli(1).duplicate();var submitted=g._ai_build("farm")
 c("ordinary AI farm uses existing paid build submission",submitted and g.commands.size()>0)
 var pending=Codec.capture_result(g)
 c("pending ordinary farm checkpoint remains strict",pending.ok)
 var clone=load("res://main.tscn").instantiate();root.add_child(clone);clone.set_process(false);clone.test_mode=true;clone.ai_enabled=false
 var restored=pending.ok and Restore.apply(clone,pending.data)
 c("pending farm restores without duplicate commands",restored and clone.commands.size()==g.commands.size())
 clone.free()
 var farm={}
 for i in 1600:
  g._tick(g.Rules.TICK)
  for e in g.entities:
   if e.alive and e.team==1 and e.kind=="farm":farm=e
  if not farm.is_empty() and farm.built:break
 c("ordinary travel and ticks complete paid farm",not farm.is_empty() and farm.built)
 c("farm payment debits exactly sixty wood",g.economy.bank_milli(1).wood==before.wood-60000)
 c("construction preserves economic conservation",g.economy.audit().ok)
 var failed=0
 for row in checks:
  if not row.passed:failed+=1
 print(JSON.stringify({"suite":"ai_food_feasibility_contract","checks":checks,"failed":failed,"scope":"Controlled observed-record planning boundaries and fresh normal-stock paid farm construction; no natural full-match victory claim."}))
 g.free();quit(0 if failed==0 else 1)
