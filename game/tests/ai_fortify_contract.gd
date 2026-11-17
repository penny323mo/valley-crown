extends SceneTree
const Policy=preload("res://scripts/ai_fortify.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func base():
 var rs=[{"id":50,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"town_center","category":"building","built":true,"pos":Vector3(20,0,-20)},{"id":51,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"tower","category":"building","built":true,"pos":Vector3(20,0,-10)}]
 for i in 8:rs.append({"id":i,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"villager","category":"unit","state":"gather" if i<2 else "idle","gather_type":"food" if i<2 else "wood","pos":Vector3(20+i,0,-10),"cargo_milli":0})
 return rs
func _initialize():call_deferred("run")
func run():
 var rs=base();var before=rs.duplicate(true);var p=Policy.plan(rs,{},[],230000,{},100)
 check("surplus tower plans one flank",not p.is_empty() and p.tower==51 and p.side==0)
 check("policy observations unchanged",rs==before)
 check("preserve two hundred wood reserve",Policy.plan(rs,{},[],229999,{},100).is_empty())
 check("five second deterministic cadence",Policy.plan(rs,{},[],230000,{},101).is_empty())
 check("one pending build prevents another",Policy.plan(rs,{},[{"team":1,"type":"build","kind":"house"}],230000,{},100).is_empty())
 var q=Policy.plan(rs,{},[],230000,{51:1},100)
 check("opposite slot follows first lifetime attempt",not q.is_empty() and q.side==1 and absf(q.position.x-p.position.x)==8)
 check("completed tower lifetime cannot repeat",Policy.plan(rs,{},[],230000,{51:3},100).is_empty())
 check("global four submissions cap",Policy.plan(rs,{},[],230000,{51:3,99:3},100).is_empty())
 check("illegal first slot can skip to other side",Policy.plan(rs,{},[],230000,{},100,{51:1}).side==1)
 check("claimed and pending workers excluded",Policy.plan(rs,{2:true,3:true,4:true,5:true,6:true},[{"team":1,"type":"order","ids":[7]}],230000,{},100).is_empty())
 var bad=rs.duplicate(true);bad[2].gather_type="wood"
 check("two food workers protected",Policy.plan(bad,{},[],230000,{},100).is_empty())
 bad=rs.duplicate(true);bad.pop_back()
 check("eight worker economy required",Policy.plan(bad,{},[],230000,{},100).is_empty())
 bad=rs.duplicate(true);bad[1].built=false
 check("active construction preempts shields",Policy.plan(bad,{},[],230000,{},100).is_empty())
 bad=rs.duplicate(true);bad[1].remembered=true
 check("remembered tower cannot authorize",Policy.plan(bad,{},[],230000,{},100).is_empty())
 bad=rs.duplicate(true);bad.append({"alive":true,"remembered":false,"team":0,"category":"unit","pos":p.position})
 check("near visible threat blocks building",Policy.plan(bad,{},[],230000,{},100).is_empty())
 bad[-1].remembered=true
 check("hidden enemy not consulted",not Policy.plan(bad,{},[],230000,{},100).is_empty())
 for state in ["build","repair","deliver"]:
  bad=rs.duplicate(true)
  for i in range(4,bad.size()):bad[i].state=state
  check("do not borrow active "+state,Policy.plan(bad,{},[],230000,{},100).is_empty())
 bad=rs.duplicate(true)
 for i in range(4,bad.size()):bad[i].cargo_milli=1
 check("carried resources preserved",Policy.plan(bad,{},[],230000,{},100).is_empty())
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true
 var stocks=g.INITIAL_STOCKS.duplicate(true);stocks[1].wood=500;g._test_reset(stocks);g.set_process(false);g.ai_enabled=false
 await process_frame
 var ws=[]
 for e in g.entities:
  if e.team==1 and e.kind=="villager":ws.append(e)
 while ws.size()<8:ws.append(g._spawn("villager",1,Vector3(8+ws.size(),0,-12)))
 var tower=g._spawn("tower",1,Vector3(10,0,-10))
 for i in ws.size():
  ws[i].pos=Vector3(12+i,0,-12)
  if i<2:
   var berry=g._nearest_resource(ws[i].pos,"food",1);g._order(ws[i],"gather",berry.id)
  else:g._set_stance(ws[i],"STOP")
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory();g.tick_count=100
 g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_claimed_workers={};g.ai_build_submitted=false
 var legal=false;var chosen={}
 for x in range(-12,25,6):
  for z in range(-24,13,6):
   tower.pos=Vector3(x,0,z)
   g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
   var plan=Policy.plan(g._ai_records(),{},[],500000,{},100)
   var opposite=Policy.plan(g._ai_records(),{},[],500000,{},100,{tower.id:1})
   if not plan.is_empty() and not opposite.is_empty() and g._placement_reason("wall",plan.position,1,plan.builder).is_empty() and g._placement_reason("wall",opposite.position,1,opposite.builder).is_empty() and g._ai_fortify_lane(plan,g._ai_records()):legal=true;chosen=plan;break
  if legal:break
 check("controlled tower has visible legal open flank",legal)
 var accepted=g._ai_fortify(g._ai_records())
 check("real integration submits ordinary wall",accepted)
 var builds=g.commands.filter(func(c):return c.type=="build" and c.kind=="wall")
 check("submission no free wall or debit",g._count(1,"wall")==0 and g.economy.bank_milli(1).wood==500000)
 check("same turn duplicate prevented",not g._ai_fortify(g._ai_records()) and builds.size()==1)
 var snap=Codec.capture(g);check("pending attempt checkpoint valid",Codec.validate(snap))
 for mask in [0,4,-1,"1"]:
  var changed=snap.duplicate(true);changed.game.ai_fortify_attempts[tower.id]=mask
  check("reject malformed attempt "+str(mask),not Codec.validate(changed))
 var wrong=snap.duplicate(true);wrong.game.ai_fortify_attempts[ws[0].id]=1
 check("reject non tower identity",not Codec.validate(wrong))
 var h=load("res://main.tscn").instantiate();root.add_child(h);h.set_process(false);h.test_mode=true
 check("restore pending attempt state",Restore.apply(h,snap) and h.ai_fortify_attempts==g.ai_fortify_attempts)
 h.paused=false;h.ai_enabled=false
 if accepted:
  g._tick(.05);h._tick(.05)
  check("ordinary thirty wood debit",g.economy.bank_milli(1).wood==470000 and g._count(1,"wall")==1)
  check("restore retains one payment",h.economy.bank_milli(1).wood==470000 and h._count(1,"wall")==1)
  var wall=g._first(1,"wall")
  for i in 1600:
   if wall.built:break
   g._tick(.05)
  check("real builder travels and finishes wall",wall.built and wall.hp==250)
  check("lifetime mask retained after completion",g.ai_fortify_attempts.get(tower.id,0)==1)
  while g.tick_count%100!=0:g._tick(.05)
  g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
  g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_claimed_workers={};g.ai_build_submitted=false
  check("second flank submitted without repeating first",g._ai_fortify(g._ai_records()) and g.ai_fortify_attempts.get(tower.id,0)==3)
  g._tick(.05)
  check("second flank paid thirty wood",g.economy.bank_milli(1).wood==440000 and g._count(1,"wall")==2)
  for i in 1600:
   var unfinished=g.entities.filter(func(e):return e.alive and e.team==1 and e.kind=="wall" and not e.built)
   if unfinished.is_empty():break
   g._tick(.05)
  var walls=g.entities.filter(func(e):return e.alive and e.team==1 and e.kind=="wall" and e.built and e.hp==250)
  check("both paid walls completed at full constructed health",walls.size()==2)
  var keep=g._first(1,"town_center");var forward=(Vector3.ZERO-keep.pos).normalized()
  var front=Vector3.FORWARD if absf(forward.z)>=absf(forward.x) else Vector3.LEFT
  if front.dot(forward)<0:front=-front
  var lateral=Vector3.RIGHT if absf(forward.z)>=absf(forward.x) else Vector3.BACK
  for kind in ["cavalry","siege"]:
   var offset=-1.0 if kind=="cavalry" else 1.0
   var start=tower.pos+front*7+lateral*offset;var goal=tower.pos+front*2+lateral*offset
   var unit=g._spawn(kind,1,start);var initial_hp=unit.hp
   g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
   g._submit("order",{"ids":[unit.id],"target":-1,"position":goal},1)
   for i in 500:
    g._tick(.05)
    if unit.pos.distance_to(goal)<0.8:break
   check(kind+" ordinary move crosses central lane",unit.pos.distance_to(goal)<0.8 and unit.hp==initial_hp)
   print("LANE_TRACE "+JSON.stringify({"kind":kind,"start":str(start),"goal":str(goal),"end":str(unit.pos),"status":unit.get("path_status","")}))
 check("conserved paid economy",g.economy.audit().ok)
 g.queue_free();h.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_fortify_contract","checks":checks,"failed":failed,"scope":"Observation policy and controlled paid native tower-flank construction/checkpoint. Not natural-match balance or rendered phone validation."}))
 quit(1 if failed else 0)
