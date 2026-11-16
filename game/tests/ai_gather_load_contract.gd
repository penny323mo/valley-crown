extends SceneTree
const Policy=preload("res://scripts/ai_gather_load.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var w={"id":1,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"villager","state":"gather","target":10}
 var d=w.duplicate();d.id=2;d.state="deliver";d.target=99;d.resource_target=10
 var r={1:w,2:d};var snapshot=r.duplicate(true)
 check("gathering and returning workers retain resource load",Policy.assignments(r,[],1,-1)=={10:2})
 check("requesting worker excluded",Policy.assignments(r,[],1,1)=={10:1})
 check("latest pending order replaces existing job once",Policy.assignments(r,[{"team":1,"type":"order","ids":[1],"target":11},{"team":1,"type":"order","ids":[1],"target":12}],1,-1)=={10:1,12:1})
 check("pending stop retires resource load",Policy.assignments(r,[{"team":1,"type":"stop","ids":[1,2]}],1,-1).is_empty())
 check("other team cannot claim workers",Policy.assignments(r,[{"team":0,"type":"stop","ids":[1,2]}],1,-1)=={10:2})
 for patch in [{"owned":false},{"remembered":true},{"alive":false},{"team":0},{"kind":"archer"}]:
  var x=w.duplicate();x.merge(patch,true);check("excluded observation "+str(patch),Policy.assignments({1:x},[],1,-1).is_empty())
 check("pending paid construction removes old load",Policy.assignments(r,[{"team":1,"type":"build","builder":1}],1,-1)=={10:1})
 check("pure planning preserves records",r==snapshot)
 var near={"id":10,"pos":Vector3(3,0,0)};var alternate={"id":11,"pos":Vector3(4,0,0)};var far={"id":12,"pos":Vector3(30,0,0)}
 check("nearby empty alternative beats crowded node",Policy.score(Vector3.ZERO,alternate,{10:3})<Policy.score(Vector3.ZERO,near,{10:3}))
 check("crowding penalty bounded not remote diversion",Policy.score(Vector3.ZERO,near,{10:100})<Policy.score(Vector3.ZERO,far,{}))
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false;g.commands.clear()
 var workers=[]
 for e in g.entities:
  if e.alive and e.team==1 and e.kind=="villager" and workers.size()<3:workers.append(e)
 for i in workers.size():workers[i].pos=Vector3(i-1,0,0);g._set_stance(workers[i],"STOP")
 var a=g._spawn("pine",-1,Vector3(-1.5,0,3.5));var b=g._spawn("pine",-1,Vector3(1.5,0,3.5));g._spawn("storehouse",1,Vector3(0,0,-5),true)
 g._update_vision(false);g._publish_faction_views();var before=g.economy.bank_milli(1).duplicate()
 for worker in workers:g._assign_worker(g.faction_views[1].get_record(worker.id),"wood")
 var targets={}
 for c in g.commands:targets[c.target]=true
 check("actual sequential AI dispatch spreads nearby nodes",g.commands.size()==3 and targets.has(a.id) and targets.has(b.id))
 check("planning cannot credit resources",g.economy.bank_milli(1)==before)
 for i in 1400:
  g._tick(.05)
  if g.economy.bank_milli(1).wood>before.wood:break
 check("ordinary movement harvest and deposit earns wood",g.economy.bank_milli(1).wood>before.wood)
 check("owned observation exposes return resource only",g.faction_views[1].get_record(workers[0].id).has("resource_target") and not g.faction_views[0].get_record(workers[0].id).has("resource_target"))
 var worker=workers[0]
 g.commands.clear();worker.path_status="LIMIT_REACHED";g._publish_faction_views()
 check("terminal budget cannot be restarted by new load choice",not g._assign_worker(g.faction_views[1].get_record(worker.id),"wood") and g.commands.is_empty())
 worker.path_status="IDLE"
 # Earn real wood first, then ask for food with normal foreign-cargo handoff.
 g._order(worker,"gather",a.id);g._publish_faction_views()
 for i in 1000:
  g._tick(.05)
  if g._cargo_amount(worker)>0:break
 var cargo=g._cargo_amount(worker);var berry=g._spawn("berry",-1,Vector3(0,0,5.5));g._update_vision(false);g._publish_faction_views()
 check("native cargo available before resource switch",cargo>0 and g._cargo_type(worker)=="wood")
 check("AI accepts ordinary foreign cargo assignment",g._assign_worker(g.faction_views[1].get_record(worker.id),"food"))
 while not g.commands.is_empty():g._execute(g.commands.pop_front())
 check("resource switch preserves wood and enters delivery",g._cargo_amount(worker)==cargo and g._cargo_type(worker)=="wood" and worker.state=="deliver" and worker.gather_type=="food")
 check("ledger conserved",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_gather_load_contract","checks":checks,"failed":failed,"scope":"Controlled native AI dispatch and ordinary harvest/deposit; advisory load only, not throughput or route guarantee; no saves"}));g.queue_free();quit(1 if failed else 0)
