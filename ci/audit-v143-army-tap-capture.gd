extends SceneTree
var g
var notes=[]
func _initialize():call_deferred("run")
func frames():
 for _i in 4:await process_frame
func tap(point):
 var before=g.command_sequence
 for press in [true,false]:
  var event=InputEventScreenTouch.new()
  event.position=point;event.index=3;event.pressed=press
  root.push_input(event);await process_frame
 await frames()
 return g.command_sequence-before
func focus(position):
 g.camera_focus=position;g.camera_zoom=30
 g._camera_update();g._update_visuals(0);g._refresh_fog();g._update_hud()
 await frames()
func store_png(file:String,sz:Vector2i)->String:
 RenderingServer.render_loop_enabled=true
 await frames()
 await RenderingServer.frame_post_draw
 var texture=root.get_texture().get_image()
 assert(texture.get_size()==sz)
 assert(texture.save_png(file)==OK)
 return FileAccess.get_sha256(file)
func run():
 var arg=OS.get_cmdline_user_args()
 assert(arg.size()==5)
 var out=arg[0];var size=Vector2i(int(arg[1]),int(arg[2]))
 var expected_build=arg[3];var intent=arg[4]
 assert(intent in ["baseline","candidate"])
 root.size=size
 RenderingServer.render_loop_enabled=false
 g=load("res://main.tscn").instantiate();g.skirmish_mode="standard";g.layout_id="valley";g.qa_mode=true
 root.add_child(g);g.set_process(false);g.ai_enabled=false;await frames()
 assert(g._snapshot().build==expected_build and root.size==size)
 var scout=g._first(0,"scout")
 await focus(scout.pos)
 var select_at=g.camera.unproject_position(scout.pos+Vector3(0,.6,0))
 assert(g._pick(select_at)==scout.id)
 await tap(select_at);assert(g.selected==[scout.id])
 await focus(Vector3(-30.5,0,22.5))
 var ring=g.faction_views[0].get_record(9)
 assert(ring.kind=="pine" and ring.alive and not ring.remembered)
 var center=g.camera.unproject_position(ring.pos+Vector3(0,1,0))
 var delta=Vector2(-12,-4) if size.x>size.y else Vector2(-24,-8)
 var p=center+delta;var chosen=g._world_at(p)
 assert(g._box_point_in_world(p) and g._pick(p)==ring.id and g._cell(chosen)==Vector2i(12,56))
 assert(not g.navigation.is_point_solid(g._cell(chosen)) and g.visible_cells[0][g._cell_index(chosen)]!=0)
 for resource in g.faction_views[0].records().values():
  assert(not is_finite(g._resource_ray_distance(resource,g.camera.project_ray_origin(p),g.camera.project_ray_normal(p))))
 var sequence_delta=await tap(p)
 var queued=g.commands.back() if sequence_delta==1 else {}
 var start=scout.pos
 for i in 295:g._tick(0.05)
 var finish=g._get_entity(scout.id).pos
 assert((sequence_delta==0 and finish.is_equal_approx(start)) if intent=="baseline" else (sequence_delta==1 and queued.target==-1 and queued.ids==[scout.id] and finish.distance_to(chosen)<0.7))
 await focus(Vector3(-30.5,0,22.5))
 assert(g.selected==[scout.id] and g.tick_count==295)
 DirAccess.make_dir_recursive_absolute(out)
 var f=out+"/scout-result.png"
 var sha=await store_png(f,size)
 var receipt={"role":intent,"build":expected_build,"size":[size.x,size.y],"clicked":[p.x,p.y],"cell":str(g._cell(chosen)),"resource_id":9,"mesh_hits":0,"start":str(start),"finish":str(finish),"distance_to_tap":finish.distance_to(chosen),"delta_commands":sequence_delta,"selected":g.selected,"sha256":sha,"tick":g.tick_count}
 print(JSON.stringify(receipt))
 FileAccess.open(out+"/report.json",FileAccess.WRITE).store_line(JSON.stringify(receipt))
 g.queue_free();quit()
