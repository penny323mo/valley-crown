extends SceneTree
var g
var output:String
var draws:=[]
var viewport_size: Vector2i
var stone_visual: MeshInstance3D
func _initialize():call_deferred("run")
func screenshot(stage:int):
 if DisplayServer.get_name()=="headless":return
 if stage not in [0,2,3]:return
 RenderingServer.render_loop_enabled=true
 for i in 6:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 assert(image.get_size()==viewport_size)
 var filename:=output+"/stage-%d.png"%stage
 assert(image.save_png(filename)==OK)
 var ndc_min:=Vector2(INF,INF)
 var ndc_max:=Vector2(-INF,-INF)
 var bounds:=stone_visual.get_aabb()
 for i in range(8):
  var point: Vector2=g.camera.unproject_position(stone_visual.to_global(bounds.get_endpoint(i)))
  ndc_min=ndc_min.min(point);ndc_max=ndc_max.max(point)
 var roi=[floori(ndc_min.x)-3,floori(ndc_min.y)-3,ceili(ndc_max.x)+4,ceili(ndc_max.y)+4]
 draws.append({"stage":stage,"sha256":FileAccess.get_sha256(filename),"roi":roi,"draws":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
 RenderingServer.render_loop_enabled=false
func run():
 var args=OS.get_cmdline_user_args()
 output=args[0]
 DirAccess.make_dir_recursive_absolute(output)
 viewport_size=Vector2i(int(args[1]),int(args[2]))
 root.size=viewport_size
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var worker=g._first(0,"villager");worker.pos=Vector3(-2,0,0);g._set_stance(worker,"STOP")
 var stone=g._spawn("stone",-1,Vector3(0,0,0));g._spawn("storehouse",0,Vector3(-5,0,0),true)
 g.camera_focus=Vector3.ZERO;g.camera_zoom=30.0;g._camera_update()
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0);g._refresh_fog();g._update_hud()
 var route=[]
 var start_seq=g.command_sequence
 g._order(worker,"gather",stone.id)
 for stage in range(4):
  for i in range(6000):
   if stone.hp<=[400,300,200,100][stage]:break
   g._tick(.05)
   if i%500==499:print("STONE_PROGRESS ",stage," ",i," ",stone.hp," ",worker.pos," ",worker.state)
  assert(stone.hp<=[400,300,200,100][stage])
  g._update_vision(false);g._publish_faction_views();g._update_visuals(0);g._refresh_fog();g._update_hud()
  var proxy=g.presentation_nodes[stone.id].body.get_node("ResourceVisual_stone")
  stone_visual=proxy
  assert(proxy.get_meta("depletion_stage",-1)==stage)
  var target=g.camera.unproject_position(stone.pos+Vector3(0,.25,0))
  route.append({"stage":stage,"tick":g.tick_count,"hp":stone.hp,"bank":g.economy.bank_milli(0),"actor_pos":str(worker.pos),"target_id":worker.target,"pick":g._pick(target),"stone_id":stone.id,"nav_solid":g.navigation.is_point_solid(g._cell(stone.pos)),"audit":g.economy.audit().ok})
  await screenshot(stage)
 assert(g.economy.audit().ok and g.command_sequence==start_seq)
 var f=FileAccess.open(output+"/journey.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"stages":route,"renders":draws,"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"size":[viewport_size.x,viewport_size.y]}));f.close()
 g.queue_free();quit(0)
