extends SceneTree
## Read-only-to-gameplay external Web audit. Stock exported WASM/PCK and
## ordinary Survival at tick zero; only set the identical native diagnostic camera.
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const SIZE=Vector2i(568,320)
var checks=[]
var audit_started=0
# Both channels survive a later stalled await. No application-state mutation.
func phase(name,details={}):
 var v={"phase":name,"elapsed_ms":Time.get_ticks_msec()-audit_started,"details":details}
 var encoded=JSON.stringify(v)
 print("VC_WEB_EDGE "+encoded)
 if OS.has_feature("web"):
  JavaScriptBridge.eval("window.vcEdgePhase="+encoded+";(window.vcEdgePhases ||= []).push(window.vcEdgePhase);void 0;",true)
func _initialize():
 audit_started=Time.get_ticks_msec()
 phase("gdscript_initialize",{"web":OS.has_feature("web")})
 call_deferred("run")
func observe(n,ok):
 checks.append({"name":n,"passed":bool(ok)})
 if not ok:push_error(n)
func frames(n,name):
 phase(name+"_await",{"expected_frames":n})
 for i in n:
  await process_frame
  if i==0:phase(name+"_first_process_frame")
 phase(name+"_settled",{"viewport":[root.size.x,root.size.y]})
func vec(v:Vector3):
 return [v.x,v.y,v.z]
func rr(c):
 var r=c.get_global_rect()
 return [r.position.x,r.position.y,r.size.x,r.size.y]
func ground(c,p,y):
 var o=c.project_ray_origin(p);var d=c.project_ray_normal(p)
 return o+d*((y-o.y)/d.y)
func run():
 if not OS.has_feature("web"):
  push_error("The Web witness must run in the stock Web export")
  quit(2);return
 var args=OS.get_cmdline_user_args()
 phase("deferred_run",{"user_args":args,"actual_build":Rules.BUILD_ID})
 if args.size()!=2 or args[0] not in ["baseline","candidate"] or args[1]!=Rules.BUILD_ID:
  JavaScriptBridge.eval("window.vcEdgeFailure='External role/build argument mismatch';void 0;",true);return
 var candidate=args[0]=="candidate"
 await frames(6,"boot")
 phase("load_main_begin")
 var scene=load("res://main.tscn")
 phase("load_main_end",{"valid":scene is PackedScene})
 if not scene is PackedScene:
  JavaScriptBridge.eval("window.vcEdgeFailure='Exported main.tscn unavailable';void 0;",true);return
 phase("instantiate_begin")
 var g=scene.instantiate()
 phase("instantiate_end",{"valid":is_instance_valid(g)})
 if not is_instance_valid(g):
  JavaScriptBridge.eval("window.vcEdgeFailure='Exported scene did not instantiate';void 0;",true);return
 g.skirmish_mode="survival";g.qa_mode=true
 phase("add_child_begin")
 root.add_child(g);g.set_process(false)
 phase("add_child_end",{"tick":g.tick_count,"entities":g.entities.size(),"loop":RenderingServer.render_loop_enabled})
 g.toast_time=0.0;g.toast_label.visible=false
 await frames(6,"scene")
 phase("camera_update_begin")
 g.camera_focus=Vector3(-25,0,11);g.camera_zoom=22.0
 g._camera_update();g._layout_ui();g._update_hud();g._update_visuals(0.0)
 await frames(6,"camera")
 var draws=[0]
 var marker=func():draws[0]+=1
 RenderingServer.frame_post_draw.connect(marker)
 var begin=Time.get_ticks_msec()
 phase("post_draw_await",{"loop":RenderingServer.render_loop_enabled})
 var processes=0
 while draws[0]<4 and Time.get_ticks_msec()-begin<25000:
  await process_frame
  processes+=1
  if processes in [1,10,60]:phase("post_draw_poll",{"processes":processes,"draws":draws[0]})
 RenderingServer.frame_post_draw.disconnect(marker)
 phase("post_draw_end",{"draws":draws[0],"processes":processes})
 observe("stock Web Compatibility has at least four actual post-draw events",draws[0]>=4 and RenderingServer.get_current_rendering_method()=="gl_compatibility")
 observe("exact real test camera/view and initial match—not test_mode",root.size==SIZE and g.camera_focus==Vector3(-25,0,11) and g.camera_zoom==22.0 and g.tick_count==0 and g.skirmish_mode=="survival" and not g.test_mode and g.entities.size()>30)
 var h=g.fog.multimesh.get_instance_transform(0).origin.y
 var f=g.fog_inward_edge
 var ext=(g.camera_ground.mesh as PlaneMesh).size*Vector2(g.camera_ground.scale.x,g.camera_ground.scale.z)*0.5
 var actual=(f.mesh as PlaneMesh).size*Vector2(f.scale.x,f.scale.z)*0.5
 var code=f.material_override.shader.code
 observe("actual selected role's material and presentation-only footprint",
  code.contains("state_mask") and code.contains("join_rounding_guard")==candidate and
  actual.is_equal_approx(ext if candidate else Vector2.ONE*Rules.MAP_HALF))
 observe("original exact 6400 cell fog and 5mm depth offset still in use",
  g.visible_cells[0].size()==6400 and g.explored_cells[0].size()==6400 and g.fog.multimesh.instance_count==6400 and
  (g.fog.multimesh.mesh as PlaneMesh).size==Vector2.ONE and f.last_states==g.fog_render_state and
  is_equal_approx(h,.11) and is_equal_approx(f.position.y-h,.005))
 if candidate:
  observe("the seam parameters are exact on the actual drawable",is_equal_approx(f.material_override.get_shader_parameter("base_height_delta"),-.005) and is_equal_approx(f.material_override.get_shader_parameter("join_rounding_guard"),.0015))
 phase("authority_capture_begin")
 var st=Codec.capture_result(g);var hud=g._qa_hud_snapshot()
 phase("authority_capture_end",{"ok":st.ok})
 var visibility=[g.visible_cells.duplicate(true),g.explored_cells.duplicate(true),g.fog_render_state.duplicate()]
 var samples=[]
 for y in range(5,SIZE.y-5,15):
  for x in range(5,SIZE.x-5,15):
   var p=Vector2(x,y);samples.append([x,y,g._box_point_in_world(p),g._pick(p),vec(g._world_at(p))])
 phase("world_probe_end",{"count":samples.size()})
 for j in 3:g._cover_camera_ground();g._refresh_fog()
 var after=Codec.capture_result(g)
 observe("exact match authority/HUD/visibility unchanged by repeated render update",st.ok and after.ok and st.data==after.data and
  hud==g._qa_hud_snapshot() and visibility==[g.visible_cells,g.explored_cells,g.fog_render_state] and g.tick_count==0)
 var a=ground(g.camera,Vector2(.5,.5),h)
 var b=ground(g.camera,Vector2(1.5,.5),h)-a
 var d=ground(g.camera,Vector2(.5,1.5),h)-a
 # The checkpoint top-level build is deliberately different across arms.
 # Compare arbitrary match authority after removing only that identity field.
 var authority=st.get("data",{}).duplicate(true)
 authority.erase("build")
 var result={"role":args[0],"build":Rules.BUILD_ID,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),
  "camera":vec(g.camera_focus),"zoom":g.camera_zoom,"size":[root.size.x,root.size.y],"map_half":Rules.MAP_HALF,
  "authority_sha":JSON.stringify(authority).sha256_text(),"input_grid":samples,"hud":hud,"checks":checks,
  "visibility_sha":JSON.stringify(visibility).sha256_text(),"projection":[vec(a),vec(b),vec(d)],"shader_source_sha":code.sha256_text(),
  "top":rr(g.hud_top),"bottom":rr(g.hud_bottom),"minimap":rr(g.minimap) if g.minimap.is_visible_in_tree() else [],
  "frame_post_draws":draws[0],"draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
 result.failed=checks.filter(func(x):return not x.passed).size()
 phase("witness_publishing",{"size":[root.size.x,root.size.y],"failed":result.failed})
 var w=JavaScriptBridge.eval("(function(){window.vcEdgeWitness="+JSON.stringify(result)+";return typeof window.vcEdgeWitness==='object';})();",true)
 phase("witness_ack",{"global":w==true})
