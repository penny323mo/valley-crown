extends SceneTree
const Game=preload("res://scripts/game.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
func check(label,ok):checks.append({"name":label,"ok":bool(ok)})
func _initialize():call_deferred("run")
func run():
 var g=Game.new();g.test_mode=true;g.skirmish_mode="standard";root.add_child(g);g.set_process(false);await process_frame
 var worker={};var resource={};var point=Vector3.INF
 for e in g.faction_views[1].records().values():
  if e.get("owned",false) and e.get("kind","")=="villager":worker=e.duplicate(true);break
 for r in g.faction_views[1].records().values():
  if r.get("category","")!="resource" or r.get("remembered",true):continue
  var p=g._free_adjacent(r,worker.pos,false,1,worker)
  if p!=Vector3.INF:resource=r.duplicate(true);point=p;break
 check("fresh ordinary map provides known legal contact",not resource.is_empty() and point!=Vector3.INF)
 if resource.is_empty():print(JSON.stringify(checks));quit(1);return
 worker.pos=point
 var before=Codec.capture_result(g);var ws=worker.duplicate(true);var rs=resource.duplicate(true)
 check("safe actual contact is allowed",g._ai_gather_contact_safe(worker,resource,{}))
 var direction=(point-resource.pos).normalized()
 var enemy={"id":999,"kind":"spearman","team":0,"category":"unit","alive":true,"remembered":false,"pos":point+direction*5.9,"built":true}
 check("resource center can be safe while contact is unsafe",g.WorkerSafety.threats({999:enemy},1,resource.pos).is_empty() and not g._ai_gather_contact_safe(worker,resource,{999:enemy}))
 var hidden=enemy.duplicate(true);hidden.remembered=true
 check("remembered enemy cannot reject contact",g._ai_gather_contact_safe(worker,resource,{999:hidden}))
 check("absent hidden enemy cannot reject contact",g._ai_gather_contact_safe(worker,resource,{}))
 var dead=enemy.duplicate(true);dead.alive=false
 check("dead enemy cannot reject contact",g._ai_gather_contact_safe(worker,resource,{999:dead}))
 var friendly=enemy.duplicate(true);friendly.team=1
 check("own unit does not become threat",g._ai_gather_contact_safe(worker,resource,{999:friendly}))
 var remembered=resource.duplicate(true);remembered.remembered=true
 check("safe remembered exploration retains existing center policy",g._ai_gather_contact_safe(worker,remembered,{999:enemy}))
 enemy.pos=point+direction*6.01
 check("beyond existing six meter policy remains legal",g._ai_gather_contact_safe(worker,resource,{999:enemy}))
 enemy.kind="tower";enemy.category="building";enemy.pos=point+direction*7.0
 check("built tower uses existing seven point five margin",not g._ai_gather_contact_safe(worker,resource,{999:enemy}))
 enemy.built=false
 check("unfinished tower is not attack threat",g._ai_gather_contact_safe(worker,resource,{999:enemy}))
 var farworker=worker.duplicate(true);farworker.pos=worker.pos+Vector3(1.3,0,0)
 var ordinary=g._free_adjacent(resource,farworker.pos,false,1,farworker)
 check("unoccupied travel advisory delegates ordinary nearest slot",g._ai_gather_contact_safe(farworker,resource,{})==(ordinary!=Vector3.INF))
 check("policy preserves observation inputs",worker==ws and resource==rs)
 var after=Codec.capture_result(g)
 check("policy preserves complete authority and save schema",before.ok and after.ok and before.data==after.data)
 var grid=g._route_grid(worker);var original=[]
 for cell in g._perimeter_cells(resource):
  original.append({"cell":cell,"solid":grid.is_point_solid(cell)});grid.set_point_solid(cell,true)
 check("standing point cannot bypass all unavailable known slots",not g._ai_gather_contact_safe(worker,resource,{}))
 for entry in original:grid.set_point_solid(entry.cell,entry.solid)
 check("restored known slots allow same contact again",g._ai_gather_contact_safe(worker,resource,{}))
 var failed=checks.filter(func(c):return not c.ok).size()
 print(JSON.stringify({"suite":"ai_gather_contact_contract","checks":checks,"failed":failed,"scope":"Observation-only advisory contact risk; no new slot routing or global safe route guarantee"}));g.free();quit(1 if failed else 0)
