extends SceneTree
const River=preload("res://scripts/river_terrain.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate()
 g.layout_id=River.ID;g.skirmish_mode="standard";g.history_path="/tmp/v139-river-engine-no-history-persistence.json"
 root.add_child(g);g.set_process(false);g.ai_enabled=false
 await process_frame
 check("new exact engine selectable layout",g.layout_id==River.ID)
 check("six-row immutable water excludes both ten-cell crossings",g.public_terrain.size()==336 and g.public_terrain.is_read_only())
 check("openings use original fair stock and player roster",g._population(0)==6 and g._population(1)==6 and g.economy.bank_milli(0)==g.economy.bank_milli(1))
 check("every fixed solid initialized in all three grids",g.public_terrain.keys().all(func(c):return g.navigation.is_point_solid(c) and g.work_memory[0].grid.is_point_solid(c) and g.work_memory[1].grid.is_point_solid(c)))
 var resources=g.entities.filter(func(e):return e.category=="resource" and e.alive)
 var footprint={}
 var duplicate=false
 for e in resources:
  var c=g._cell(e.pos)
  if footprint.has(c) or River.surface_at(g.layout_id,c)!=River.DRY:duplicate=true
  footprint[c]=true
 check("real seeded resources clear all water and crossings without duplicate cells",not duplicate)
 for x in [-13.5,13.5]:
  for team in 2:
   var y=1-2*team
   var start=g._cell(Vector3(x,0,8.5*y))
   var end=g._cell(Vector3(x,0,-8.5*y))
   var small=g.work_memory[team].grid.get_id_path(start,end)
   var broad=g._route_grid({"radius":0.65,"team":team}).get_id_path(start,end)
   check("faction "+str(team)+" small crossing at "+str(x),not small.is_empty() and small.filter(func(c):return c.y>=37 and c.y<43).all(func(c):return absf(g._point(c).x-x)<5.0))
   check("faction "+str(team)+" siege crossing at "+str(x),not broad.is_empty() and broad.filter(func(c):return c.y>=37 and c.y<43).all(func(c):return absf(g._point(c).x-x)<4.0))
 var worker=g._first(0,"villager")
 check("actual placement gives named water reason",g._placement_reason("farm",Vector3(0,0,0),0,worker.id,false)=="河水阻隔，不可建築")
 check("actual placement gives named bridge reason",g._placement_reason("farm",Vector3(-13.5,0,0.5),0,worker.id,false)=="木橋須留作通行")
 check("solid water cannot be crossed even by small physical steps",not g._path_step_is_free(Vector3(.5,0,3.5),Vector3(.5,0,2.5)))
 var c=g._cell(Vector3(.5,0,.5))
 g.work_memory[0].observe({}, {}, {c:true},1)
 g.work_memory[0].observe({}, {}, {},2)
 check("observation refresh cannot clear public geography",g.work_memory[0].grid.is_point_solid(c))
 check("no false cells added to old layouts",["valley","woodland","iron_crossroads"].all(func(id):return River.blocked(id).is_empty()))
 # Explicit fixture vision is safe for this atomic preview/auth check.
 g.visible_cells[0].fill(1)
 var workers=g.entities.filter(func(e):return e.kind=="villager" and e.team==0).slice(0,2).map(func(e):return e.id)
 g._select(workers)
 var dry_bridge_x=-13.0
 for x in range(-17,-9):
  if g._placement_reason("wall",Vector3(x,0,-4),0,workers[0],false).is_empty():
   dry_bridge_x=float(x);break
 for k in [0.0,dry_bridge_x]:
  g.visible_cells[0].fill(1)
  g._start_build("wall")
  g.wall_line_count=2;g.wall_line_vertical=true;g.pointer_world=Vector3(k,0,-4)
  g.build_preview_held=true
  var bank=g.economy.bank_milli(0).duplicate()
  var sequence=g.command_sequence
  var walls=g.entities.filter(func(e):return e.kind=="wall").size()
  var reason=g._build_preview_reason()
  var expected="河水阻隔" if k==0.0 else "木橋須留作通行"
  print("WALL_PREVIEW ",k," ",reason)
  g._confirm_build();g._tick(.05)
  check("mixed dry/forbidden wall line kept atomic and unpaid "+str(k),reason.begins_with("第2段") and reason.contains(expected) and sequence==g.command_sequence and bank==g.economy.bank_milli(0) and walls==g.entities.filter(func(e):return e.kind=="wall").size())
  g._cancel_mode()
 var f=checks.filter(func(x):return not x.passed)
 print(JSON.stringify({"suite":"river_terrain_contract","scope":"native engine authority, faction grid, initialized scenario only; no normal complete match, render, browser or release claims","checks":checks,"failed":f.size()}))
 g.queue_free();quit(0 if f.is_empty() else 1)
