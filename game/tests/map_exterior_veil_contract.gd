extends SceneTree
## Permanent runtime contract, independent of campaign, screenshot pins, or CI fixture.
## Safe headless. Renderer pixels and timing must be validated separately.
const Rules=preload("res://scripts/rules.gd")
const Edge=preload("res://scripts/fog_inward_edge.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const River=preload("res://scripts/river_terrain.gd")
var checks=[]
var pick_probes=0
func _initialize(): call_deferred("run")
func check(label,result):
 checks.append({"name":label,"passed":bool(result)})
 if not result:push_error(label)
func half_extents(layer):
 var p=layer.mesh as PlaneMesh
 return p.size*Vector2(layer.scale.x,layer.scale.z)*0.5
func world_on(camera,screen,height):
 var o=camera.project_ray_origin(screen)
 var ray=camera.project_ray_normal(screen)
 return o+ray*((height-o.y)/ray.y)
func probes(g,width,height):
 var a=[]
 for ix in range(1,10):
  for iy in range(1,6):
   var screen=Vector2(float(ix)/10.0*width,float(iy)/6.0*height)
   a.append([g._box_point_in_world(screen),g._pick(screen),g._world_at(screen)])
 return a
func cases(g,layout):
 var helper=g.fog_inward_edge
 var ground=g.camera_ground
 var original_ground_mesh=ground.mesh
 var original_size=(original_ground_mesh as PlaneMesh).size
 var original_ground_material=ground.material_override
 var original_helper_mesh=helper.mesh
 var original_texture=helper.state_texture
 var cell_count=Rules.MAP_SIZE*Rules.MAP_SIZE
 check(layout+" unchanged authoritative fog grid",Rules.MAP_SIZE==80 and Rules.MAP_HALF==40 and g.fog.multimesh.instance_count==cell_count and (g.fog.multimesh.mesh as PlaneMesh).size==Vector2.ONE and Vector2i(helper.state_texture.get_size())==Vector2i(80,80))
 check(layout+" stable depth separation and single depth-read-only helper",Edge.BASE_TILE_Y==0.11 and Edge.INWARD_LAYER_Y==0.115 and is_equal_approx(helper.position.y,0.115) and helper.mesh.get_surface_count()==1 and helper.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
 check(layout+" shader bound to base plane and bounded guard",is_equal_approx(helper.material_override.get_shader_parameter("base_height_delta"),-0.005) and is_equal_approx(helper.material_override.get_shader_parameter("join_rounding_guard"),0.0015) and Edge.EDGE_WIDTH==0.65)
 if DisplayServer.get_name()!="headless":
  check(layout+" actual uploaded tile has shared base height",is_equal_approx(g.fog.multimesh.get_instance_transform(0).origin.y,Edge.BASE_TILE_Y))
 var center_limit=Rules.CAMERA_LIMIT
 var table=[
  ["west",Vector2i(568,320),Vector3(-center_limit,0,0),30.0,Vector2i(1,0)],
  ["east",Vector2i(568,320),Vector3(center_limit,0,0),30.0,Vector2i(1,0)],
  ["north",Vector2i(568,320),Vector3(0,0,-center_limit),30.0,Vector2i(0,1)],
  ["south",Vector2i(568,320),Vector3(0,0,center_limit),30.0,Vector2i(0,1)],
  ["wide restricted corner",Vector2i(844,390),Vector3(-center_limit-30,0,center_limit+30),46.0,Vector2i(1,1)],
  ["portrait centre after zoom out",Vector2i(390,844),Vector3.ZERO,15.0,Vector2i(0,0)],
 ]
 for row in table:
  var tag=layout+" "+row[0]
  var size=row[1]
  var wanted=row[2]
  root.size=size
  for n in 4:await process_frame
  g.camera_focus=wanted;g.camera_zoom=row[3]
  g._camera_update();g._layout_ui();g._update_hud()
  var clamped=Vector3(clampf(wanted.x,-center_limit,center_limit),wanted.y,clampf(wanted.z,-center_limit,center_limit))
  check(tag+" normal camera focus limits/zoom unchanged",g.camera_focus==clamped and g.camera.size==row[3] and g.camera.projection==Camera3D.PROJECTION_ORTHOGONAL)
  var world_half=half_extents(ground)
  var helper_half=half_extents(helper)
  var extremes=Vector2.ZERO
  for screen in [Vector2.ZERO,Vector2(size.x,0),Vector2(0,size.y),Vector2(size)]:
   var point=world_on(g.camera,screen,Edge.INWARD_LAYER_Y)
   extremes=extremes.max(Vector2(absf(point.x),absf(point.z)))
  var basic=original_size*0.5
  var axes=Vector2i(1 if world_half.x>basic.x+.1 else 0,1 if world_half.y>basic.y+.1 else 0)
  check(tag+" single veil shares existing visual ground extent",world_half.is_equal_approx(helper_half) and world_half.x>=extremes.x and world_half.y>=extremes.y and axes==row[4])
  var prior=Codec.capture_result(g)
  var fog=[g.visible_cells.duplicate(true),g.explored_cells.duplicate(true),g.fog_render_state.duplicate()]
  var routed=probes(g,size.x,size.y)
  pick_probes+=routed.size()
  var hud=g._qa_hud_snapshot()
  for n in 3:g._cover_camera_ground();g._refresh_fog()
  var after=Codec.capture_result(g)
  check(tag+" authority and both teams' fog identical through presentation refresh",prior.ok and after.ok and prior.data==after.data and fog==[g.visible_cells,g.explored_cells,g.fog_render_state])
  check(tag+" stable input/ground projection and complete touch HUD",routed==probes(g,size.x,size.y) and hud==g._qa_hud_snapshot() and not hud.is_empty())
  check(tag+" original ground mesh/material and veil resources unchanged",ground.mesh==original_ground_mesh and (ground.mesh as PlaneMesh).size==original_size and ground.material_override==original_ground_material and helper.mesh==original_helper_mesh and helper.state_texture==original_texture and helper.last_states==g.fog_render_state)
func run():
 for layout in ["valley",River.ID]:
  root.size=Vector2i(568,320)
  for n in 4:await process_frame
  var g=load("res://main.tscn").instantiate()
  g.layout_id=layout;g.qa_mode=true;root.add_child(g);g.set_process(false)
  check(layout+" test uses actual normal map",g.layout_id==layout and not g.test_mode)
  await cases(g,layout)
  g.free()
 check("all twelve normal-camera cases executed",pick_probes==540 and checks.size()>60)
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"map_exterior_veil_contract","checks":checks,"failure_count":failed,"pick_probes":pick_probes,"scope":"Native world extent, state and input parity; no GPU or browser pixel claim."}))
 quit(1 if failed else 0)
