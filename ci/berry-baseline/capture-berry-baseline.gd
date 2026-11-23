extends SceneTree
## Exact asset lab only. All stock changes are normal harvest; shortened fixed
## scene is an explicit fixture, not a replay of a user match.
const Model=preload("res://scripts/resource_visuals.gd")
var g
var frames=[]
var output:String
var size:Vector2i
var render:bool
func _initialize():call_deferred("run")
func update_world():
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0);g._refresh_fog();g._update_hud()
 await process_frame
func buffer_hash(v:Variant)->String:
 return Marshalls.raw_to_base64(var_to_bytes(v)).sha256_text()
func scene_state(berry,stone,iron,stage):
 await update_world()
 var center=g.camera.unproject_position(berry.pos+Vector3(0,.25,0))
 var stone_at=g.camera.unproject_position(stone.pos+Vector3(0,.25,0))
 var iron_at=g.camera.unproject_position(iron.pos+Vector3(0,.25,0))
 assert(g.presentation_nodes.has(stone.id) and g.presentation_nodes.has(iron.id))
 assert(g.presentation_nodes[stone.id].node.is_visible_in_tree() and g.presentation_nodes[iron.id].node.is_visible_in_tree())
 var result={"stage":stage,"hp":berry.hp,"tick":g.tick_count,"stone_untouched":stone.hp==400,"stone_id":stone.id,"stone_center":[stone_at.x,stone_at.y],"iron_id":iron.id,"iron_center":[iron_at.x,iron_at.y],"iron_untouched":iron.hp==400,"berry_id":berry.id,"berry_alive":berry.alive,"proxy_cached":g.presentation_nodes.has(berry.id),"present":g.presentation_nodes.has(berry.id) and g.presentation_nodes[berry.id].node.is_visible_in_tree(),"bank":g.economy.bank_milli(0),"audit":g.economy.audit().ok,"center":[center.x,center.y],"center_pick":g._pick(center)}
 assert(result.audit and result.stone_untouched)
 if stage<4:
  var node=g.presentation_nodes[berry.id].body.get_node("ResourceVisual_berry")
  assert(result.present and berry.alive and node.get_meta("depletion_stage",-1)==stage and node.mesh.get_surface_count()==2)
  var a=node.mesh.surface_get_arrays(0)
  var second=node.mesh.surface_get_arrays(1)
  result.foliage_hash=buffer_hash(a);result.fruit_hash=buffer_hash(second)
  result.pick_samples=[]
  var record=g.faction_views[0].get_record(berry.id)
  for dx in range(-12,13,3):
   for dy in range(-9,10,3):
    var p=center+Vector2(dx,dy);var who=g._pick(p)
    var ray=g._resource_ray_distance(record,g.camera.project_ray_origin(p),g.camera.project_ray_normal(p))
    result.pick_samples.append([dx,dy,who,is_finite(ray)])
  assert(result.pick_samples.any(func(p):return p[2]==berry.id and p[3]))
 else:
  assert(not berry.alive and not result.present and result.center_pick!=berry.id)
 if render and stage in [0,3,4]:
  RenderingServer.render_loop_enabled=true
  for i in 6:await process_frame
  await RenderingServer.frame_post_draw
  var img=root.get_texture().get_image()
  assert(img.get_size()==size)
  var file=output+"/baseline-stage-"+str(stage)+".png";assert(img.save_png(file)==OK)
  result.png={"filename":file.get_file(),"sha256":FileAccess.get_sha256(file),"draws":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
  RenderingServer.render_loop_enabled=false
 frames.append(result)
 print("BERRY_STAGE ",stage," hp=",berry.hp," bank=",result.bank.food," tick=",g.tick_count," pick=",result.center_pick)
func run():
 var args:=OS.get_cmdline_user_args()
 assert(args.size()==3)
 output=args[0];size=Vector2i(int(args[1]),int(args[2]));root.size=size
 render=DisplayServer.get_name()!="headless";RenderingServer.render_loop_enabled=false
 DirAccess.make_dir_recursive_absolute(output)
 g=load("res://main.tscn").instantiate();g.layout_id="valley";g.skirmish_mode="standard"
 root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 assert(g._snapshot().build=="vc-ec0980cd3908")
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var berry=g._spawn("berry",-1,Vector3(.5,0,.5))
 var stone=g._spawn("stone",-1,Vector3(2.5,0,.5))
 var iron=g._spawn("iron",-1,Vector3(4.5,0,.5))
 g._spawn("storehouse",0,Vector3(-4.5,0,.5),true)
 var workers=[]
 for site in [Vector3(-1.5,0,0.5),Vector3(-.5,0,2.5),Vector3(-.5,0,-1.5)]:
  var worker=g._spawn("villager",0,site)
  workers.append(worker)
 g.camera_focus=Vector3(.5,0,.5);g.camera_zoom=30.0;g._camera_update()
 await scene_state(berry,stone,iron,0)
 for w in workers:g._order(w,"gather",berry.id)
 for stage in [1,2,3,4]:
  for i in range(7500):
   if berry.hp<=[200,150,100,50,0][stage]:break
   g._tick(.05)
   if (i+1)%500==0:print("BERRY_PROGRESS ",stage," ",i+1," ",berry.hp)
  assert(berry.hp<=[200,150,100,50,0][stage])
  await scene_state(berry,stone,iron,stage)
  assert(iron.hp==400)
 for t in range(240):
  if g.economy.bank_milli(0).food==350000:break
  g._tick(.05)
 assert(g.economy.bank_milli(0).food==350000 and g.economy.audit().ok)
 assert(frames.size()==5, "All five actual phases required")
 var f=FileAccess.open(output+"/receipt.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"build":g._snapshot().build,"viewport":[size.x,size.y],"camera":str(g.camera.global_transform),"zoom":g.camera_zoom,"frames":frames,"final_bank":g.economy.bank_milli(0),"display":DisplayServer.get_name(),"engine":Engine.get_version_info(),"rendering_method":RenderingServer.get_current_rendering_method(),"renderer":RenderingServer.get_video_adapter_name(),"rendered":render,"scope":"Controlled world fixture. Actual ordinary gather order, no HP or bank injection after creation; renderer absent when headless."}));f.close()
 g.queue_free();quit(0)
