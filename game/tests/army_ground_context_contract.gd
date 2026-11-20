extends SceneTree
## Real InputEventScreenTouch on imported game scene, fixed camera witness.
var g
var checks=[]
func _initialize():call_deferred("run")
func ck(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func frames():
 for _i in 4:await process_frame
func tap(p):
 var before=g.command_sequence
 for press in [true,false]:
  var event=InputEventScreenTouch.new()
  event.position=p;event.index=3;event.pressed=press
  root.push_input(event);await process_frame
 await frames()
 return g.command_sequence-before
func focus(position):
 g.camera_focus=position;g.camera_zoom=30
 g._camera_update();g._update_visuals(0);g._refresh_fog();g._update_hud();await frames()
func any_resource_geometry(at):
 var ray_origin=g.camera.project_ray_origin(at);var direction=g.camera.project_ray_normal(at)
 return g.faction_views[0].records().values().any(func(r):return is_finite(g._resource_ray_distance(r,ray_origin,direction)))
func run():
 root.size=Vector2i(844,390)
 g=load("res://main.tscn").instantiate()
 g.skirmish_mode="standard";g.layout_id="valley";g.qa_mode=true
 root.add_child(g);g.set_process(false);g.ai_enabled=false;await frames()
 var scout=g._first(0,"scout");var worker=g._first(0,"villager")
 await focus(scout.pos)
 await tap(g.camera.unproject_position(scout.pos+Vector3(0,.6,0)))
 ck("ordinary scout touch selects actual own unit",g.selected==[scout.id])
 var destination=Vector3.ZERO;var start=scout.pos
 for size in [Vector2i(844,390),Vector2i(390,844)]:
  root.size=size;await frames()
  await focus(Vector3(-30.5,0,22.5))
  var landscape=size.x>size.y
  var tree=g.faction_views[0].get_record(9)
  var open=Vector2(496.593292236328,174.925018310547) if landscape else Vector2(355.771148681641,376.586456298828)
  var blocked=Vector2(496.593292236328,178.925018310547) if landscape else Vector2(351.771148681641,376.586456298828)
  var real=Vector2(484.593292236328,146.925018310547) if landscape else Vector2(331.771148681641,324.586456298828)
  var tag=" "+str(size)
  destination=g._world_at(open)
  var cell=g._cell(destination)
  var solid=g._cell(g._world_at(blocked))
  var grid=g.work_memory[0].grid
  ck("actual open grass has a misleading visible resource anchor but no triangle"+tag,tree.kind=="pine" and g._box_point_in_world(open) and g._pick(open)==tree.id and not any_resource_geometry(open) and cell==Vector2i(12,56) and g.visible_cells[0][g._cell_index(destination)]!=0 and not grid.is_point_solid(cell))
  var accepted=await tap(open)
  var last=g.commands.back() if accepted==1 else {}
  ck("scout open-ground tap queues one untargeted move and preserves selection"+tag,accepted==1 and last.get("ids",[])==[scout.id] and last.get("target",-2)==-1 and last.get("position",Vector3.INF).is_equal_approx(destination) and g.selected==[scout.id])
  ck("known solid resource halo without a mesh still does not move soldiers"+tag,g._box_point_in_world(blocked) and g._pick(blocked)==tree.id and solid==Vector2i(12,57) and grid.is_point_solid(solid) and not any_resource_geometry(blocked) and await tap(blocked)==0)
  ck("true visible resource geometry still does not move soldiers"+tag,g._box_point_in_world(real) and g._pick(real)==tree.id and any_resource_geometry(real) and await tap(real)==0)
  # Controlled presentational memberships; each target uses genuine input path.
  g._select([worker.id])
  accepted=await tap(open)
  last=g.commands.back() if accepted==1 else {}
  ck("worker-only same point still orders actual tree harvest"+tag,accepted==1 and last.get("ids",[])==[worker.id] and last.get("target",-2)==tree.id)
  g._select([scout.id,worker.id])
  accepted=await tap(open)
  last=g.commands.back() if accepted==1 else {}
  ck("mixed worker and scout preserve the exact worker-only harvest order"+tag,accepted==1 and last.get("ids",[])==[worker.id] and last.get("target",-2)==tree.id)
  g._select([scout.id])
 for _i in 295:g._tick(.05)
 var arrived=g._get_entity(scout.id).pos
 ck("existing route moves scout more than seven metres to intended ordinary grass",start.distance_to(arrived)>7.0 and arrived.distance_to(destination)<0.7)
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"army_ground_context_contract","scope":"real native touches, controlled camera and mixed membership, exact ordinary commands and arrival; not browser or physical device","checks":checks,"failed":failed}))
 g.queue_free();quit(0 if failed==0 else 1)
