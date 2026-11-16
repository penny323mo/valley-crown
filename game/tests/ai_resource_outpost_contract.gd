extends SceneTree
const Policy=preload("res://scripts/ai_resource_outpost.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var records=[]
 for i in 5:records.append({"id":i,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"villager","category":"unit","state":"gather" if i<4 else "idle","gather_type":"food" if i<2 else "wood","target":11 if i<2 else 10,"pos":Vector3(i,0,0),"cargo_milli":0})
 records.append({"id":10,"alive":true,"remembered":false,"team":-1,"kind":"pine","category":"resource","hp":200,"pos":Vector3.ZERO})
 records.append({"id":20,"owned":true,"alive":true,"team":1,"kind":"town_center","built":true,"pos":Vector3(20,0,20)})
 var before=records.duplicate(true);var plan=Policy.plan(records,{},[],200000)
 check("remote active cluster gets bounded plan",not plan.is_empty() and plan.plots.size()==8 and plan.builder==4)
 check("policy leaves observations unchanged",records==before)
 check("reserve prevents spending last eighty wood",Policy.plan(records,{},[],159999).is_empty())
 check("pending storehouse blocks duplicate",Policy.plan(records,{},[{"team":1,"type":"build","kind":"storehouse"}],200000).is_empty())
 var near=records.duplicate(true);near[-1].pos=Vector3(5,0,0)
 check("near existing dropoff no outpost",Policy.plan(near,{},[],200000).is_empty())
 near[-1].built=false;near[-1].kind="storehouse"
 check("unfinished nearby dropoff prevents duplicate",Policy.plan(near,{},[],200000).is_empty())
 var nofood=records.duplicate(true);nofood[0].gather_type="wood"
 check("two food workers protected",Policy.plan(nofood,{},[],200000).is_empty())
 var hidden=records.duplicate(true);hidden[5].remembered=true
 check("hidden cluster never planned",Policy.plan(hidden,{},[],200000).is_empty())
 hidden[5].remembered=false;hidden[5].hp=0
 check("depleted cluster never planned",Policy.plan(hidden,{},[],200000).is_empty())
 var threatened=records.duplicate(true);threatened.append({"id":90,"alive":true,"team":0,"category":"unit","pos":Vector3(4,0,0)})
 check("visible enemy prevents supply expansion",Policy.plan(threatened,{},[],200000).is_empty())
 threatened[-1].pos=Vector3(13,0,0)
 check("candidate point also checks closer threat",not Policy.threatened(threatened,Vector3.ZERO) and Policy.threatened(threatened,Vector3(4,0,0)))
 check("pending miners do not justify new outpost",Policy.plan(records,{},[{"team":1,"type":"order","ids":[2,3],"target":-1}],200000).is_empty())
 check("claimed workers not borrowed",Policy.plan(records,{2:true,3:true,4:true},[],200000).is_empty())
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 var workers=[]
 for e in g.entities:
  if e.team==1 and e.kind=="villager":workers.append(e)
 var pine1=g._spawn("pine",-1,Vector3(7.5,0,-7.5));var pine2=g._spawn("pine",-1,Vector3(9.5,0,-7.5))
 for i in 2:
  var berry=g._nearest_resource(workers[i].pos,"food",1);g._order(workers[i],"gather",berry.id)
 workers[2].pos=Vector3(7.5,0,-10.5);workers[3].pos=Vector3(9.5,0,-10.5);workers[4].pos=Vector3(10.5,0,-10.5)
 g._order(workers[2],"gather",pine1.id);g._order(workers[3],"gather",pine2.id);g._set_stance(workers[4],"STOP")
 g._first(1,"scout").pos=Vector3(9.5,0,-5.5)
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_claimed_workers={};g.ai_build_submitted=true
 check("higher priority construction wins",not g._ai_resource_outpost(g._ai_records()) and g.commands.is_empty())
 g.ai_build_submitted=false;var bank=g.economy.bank_milli(1).wood
 g.ai_opening_assigned=true;g._ai_update()
 var builds=g.commands.filter(func(c):return c.type=="build" and c.kind=="storehouse")
 var accepted=builds.size()==1
 check("full AI turn submits one ordinary outpost build",accepted)
 if accepted:check("later economy decisions preserve chosen builder",g.commands.filter(func(c):return c.type=="order" and builds[0].builder in c.get("ids",[])).is_empty() and g.ai_claimed_workers.get(builds[0].builder,"")=="build")
 check("no free building or resource before command",g._count(1,"storehouse")==0 and g.economy.bank_milli(1).wood==bank)
 check("same turn second outpost prevented",not g._ai_resource_outpost(g._ai_records()) and g.commands.filter(func(c):return c.type=="build" and c.kind=="storehouse").size()==1)
 var site={}
 if accepted:
  var command=builds[0];g.commands.erase(command);g._execute(command)
  site=g._first(1,"storehouse")
  check("ordinary eighty wood charged",not site.is_empty() and g.economy.bank_milli(1).wood==bank-80000 and not site.built)
  for i in 2000:
   g._tick(.05)
   if not site.is_empty() and site.built:break
  check("real builder completes paid outpost",not site.is_empty() and site.built)
  g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
  var used_new_dropoff=false
  for i in 2400:
   for w in [workers[2],workers[3]]:
    if w.state=="deliver" and w.target==site.id:used_new_dropoff=true
   if used_new_dropoff:break
   g._tick(.05)
  check("nearby miner chooses actual new dropoff",used_new_dropoff)
  g.ai_build_submitted=false;g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_claimed_workers={}
  check("finished outpost prevents duplicate plan",not g._ai_resource_outpost(g._ai_records()))
 check("actual economy remains conserved",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_resource_outpost_contract","checks":checks,"failed":failed,"scope":"Observed cluster policy and controlled real paid AI construction/dropoff; not natural-match balance or rendering acceptance"}))
 g.queue_free();quit(1 if failed else 0)
