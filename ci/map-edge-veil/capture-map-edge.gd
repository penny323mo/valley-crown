extends SceneTree
## Unmodified-size Godot viewport capture of the normal Survival match at
## tick zero; camera-only fixed edge probes. No commands/grants or fake pixels.
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
var captures=[]
var metadata_only=false
var output=""
func _initialize():call_deferred("run")
func c(name,passed):
 checks.append({"name":name,"passed":bool(passed)})
 if not passed:push_error(name)
 return passed
func frames():
 for j in 6:await process_frame
func rect(ob):
 var r=ob.get_global_rect()
 return [r.position.x,r.position.y,r.size.x,r.size.y]
func vec(v:Vector3):
 return [v.x,v.y,v.z]
func to_ground(camera,screen:Vector2,height:float):
 var o=camera.project_ray_origin(screen)
 var v=camera.project_ray_normal(screen)
 return o+v*((height-o.y)/v.y)
func render(g, item):
 var events=[0]
 var marker=func():events[0]+=1
 RenderingServer.frame_post_draw.connect(marker)
 RenderingServer.render_loop_enabled=true
 var start=Time.get_ticks_msec()
 while events[0]<4 and Time.get_ticks_msec()-start<30000:await process_frame
 RenderingServer.render_loop_enabled=false
 RenderingServer.frame_post_draw.disconnect(marker)
 if not c(item.name+" warmed renderer and four actual draw completions",events[0]>=4):return
 var image=root.get_texture().get_image()
 if not c(item.name+" native non-empty dimensions",image!=null and not image.is_empty() and image.get_size()==root.size):return
 var palette={}
 for x in range(3,root.size.x,13):
  for y in range(3,root.size.y,13):palette[image.get_pixel(x,y).to_rgba32()]=true
 if not c(item.name+" original viewport not a blank or dummy frame",palette.size()>24):return
 item.draw_calls=root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
 item.primitives=root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
 item.file=item.name+".png"
 var path=output+"/"+item.file
 if not c(item.name+" native frame saved unmodified",image.save_png(path)==OK):return
 item.sha256=FileAccess.get_sha256(path)
func capture(g, label,focus,zoom,size, expected_candidate):
 root.size=size
 await frames()
 g.camera_focus=focus;g.camera_zoom=zoom
 g._camera_update();g._layout_ui();g._update_hud();g._update_visuals(0.0)
 await frames()
 var ext=(g.camera_ground.mesh as PlaneMesh).size*Vector2(g.camera_ground.scale.x,g.camera_ground.scale.z)*0.5
 var fil=g.fog_inward_edge
 var fog=(fil.mesh as PlaneMesh).size*Vector2(fil.scale.x,fil.scale.z)*0.5
 var baseline_grid=Vector2.ONE*Rules.MAP_HALF
 c(label+" camera state exact",g.camera_focus==focus and g.camera_zoom==zoom and root.size==size)
 c(label+" veil presentation only, exact role footprint",fog.is_equal_approx(ext if expected_candidate else baseline_grid) and (fil.mesh as PlaneMesh).size==baseline_grid*2.0 and is_equal_approx(fil.position.y,0.115))
 var maximum:=Vector2.ZERO
 for at in [Vector2.ZERO,Vector2(size.x,0),Vector2(0,size.y),Vector2(size)]:
  var wp=to_ground(g.camera,at,fil.position.y)
  maximum=maximum.max(Vector2(absf(wp.x),absf(wp.z)))
 if expected_candidate:c(label+" extended plane spans every viewport corner",maximum.x<=fog.x and maximum.y<=fog.y)
 c(label+" fog source arrays and original 1x1 planes remain on map",g.visible_cells[0].size()==6400 and g.explored_cells[0].size()==6400 and g.fog.multimesh.instance_count==6400 and (g.fog.multimesh.mesh as PlaneMesh).size==Vector2.ONE and fil.last_states==g.fog_render_state)
 var before=Codec.capture_result(g)
 var hud=g._qa_hud_snapshot()
 var visibility=[g.visible_cells.duplicate(true),g.explored_cells.duplicate(true),g.fog_render_state.duplicate()]
 var samples=[]
 for y in range(5,size.y-5,15):
  for x in range(5,size.x-5,15):
   var screen=Vector2(x,y)
   samples.append([x,y,g._box_point_in_world(screen),g._pick(screen),vec(g._world_at(screen))])
 for j in 3:g._cover_camera_ground();g._refresh_fog()
 var after=Codec.capture_result(g)
 c(label+" complete valid match state unchanged by repeated veil update",before.ok and after.ok and before.data==after.data)
 c(label+" actor/ground projection and HUD observations stable",hud==g._qa_hud_snapshot() and visibility==[g.visible_cells,g.explored_cells,g.fog_render_state] and g.tick_count==0)
 var a=to_ground(g.camera,Vector2(.5,.5),fil.position.y)
 var b=to_ground(g.camera,Vector2(1.5,.5),fil.position.y)-a
 var d=to_ground(g.camera,Vector2(.5,1.5),fil.position.y)-a
 var item={"name":label,"size":[size.x,size.y],"focus":vec(g.camera_focus),"zoom":g.camera_zoom,"ground_extents":[ext.x,ext.y],"veil_extents":[fog.x,fog.y],"map_half":Rules.MAP_HALF,"projection":[vec(a),vec(b),vec(d)],"authority_sha":JSON.stringify(before.get("data",{})).sha256_text(),"hud":hud,"input_grid":samples,"top":rect(g.hud_top),"bottom":rect(g.hud_bottom),"minimap":rect(g.minimap) if g.minimap.is_visible_in_tree() else [],"visibility_sha":JSON.stringify(visibility).sha256_text(),"shots_in_scope":"Actual native tick-zero Survival with explicit camera-only fixture; no ordinary played-match claim."}
 if not metadata_only:await render(g,item)
 captures.append(item)
 print("EDGE_QA_CASE "+label)
func run():
 var args=OS.get_cmdline_user_args()
 if args.size() not in [2,3] or args[1] not in ["baseline","candidate"] or (args.size()==3 and args[2]!="--metadata-only"):quit(2);return
 metadata_only=args.size()==3;output=args[0]
 if output.is_empty() or not output.begins_with("/") or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(2);return
 RenderingServer.render_loop_enabled=false
 var runtime=Engine.get_version_info()
 var display=DisplayServer.get_name()
 var renderer=RenderingServer.get_current_rendering_method()
 var adapter=RenderingServer.get_video_adapter_name()
 if not c("exact Godot native version and actual software renderer when pixel capture enabled",runtime.hex==0x040603 and (metadata_only or (display!="headless" and renderer=="gl_compatibility" and "llvmpipe" in adapter.to_lower()))):quit(2);return
 root.size=Vector2i(568,320);await frames()
 var g=load("res://main.tscn").instantiate()
 g.skirmish_mode="survival";g.qa_mode=true;root.add_child(g);g.set_process(false)
 g.toast_time=0.0;g.toast_label.visible=false;await frames()
 c("ordinary initialized non-null Survival tick-zero combat",g.skirmish_mode=="survival" and g.tick_count==0 and g.entities.size()>30)
 var candidate=args[1]=="candidate"
 await capture(g,"survival-reproduced-camera",Vector3(-25,0,11),22.0,Vector2i(568,320),candidate)
 await capture(g,"west",Vector3(-35,0,0),30.0,Vector2i(568,320),candidate)
 await capture(g,"east",Vector3(35,0,0),30.0,Vector2i(568,320),candidate)
 await capture(g,"north",Vector3(0,0,-35),30.0,Vector2i(568,320),candidate)
 await capture(g,"south",Vector3(0,0,35),30.0,Vector2i(568,320),candidate)
 await capture(g,"wide-zoomed-corner",Vector3(-35,0,35),46.0,Vector2i(844,390),candidate)
 var failed=checks.filter(func(e):return not e.passed).size()
 var filenames=captures.filter(func(e):return e.has("file")).size()
 var result="FAILED" if failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
 var report={"failed":failed,"result":result,"role":args[1],"display":display,"renderer":renderer,"adapter":adapter,"runtime":runtime,"reported_build":Rules.BUILD_ID,"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"fog_sha":FileAccess.get_sha256("res://scripts/fog_inward_edge.gd"),"checks":checks,"frames":captures,"png_count":filenames}
 var f=FileAccess.open(output+"/report.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(report));f.close()
 print("EDGE_QA_SUM "+JSON.stringify({"status":result,"failed":failed,"checks":checks.size(),"png":filenames}))
 g.free()
 quit(1 if failed else 0)
