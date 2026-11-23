extends SceneTree
## Read-only-to-gameplay external Web audit. Stock exported WASM/PCK and
## ordinary Survival at tick zero; only set the identical native diagnostic camera.
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const SIZE=Vector2i(568,320)
var checks=[]
func _initialize():call_deferred("run")
func observe(n,ok):
 checks.append({"name":n,"passed":bool(ok)})
 if not ok:push_error(n)
func frames(n):
 for i in n:await process_frame
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
 if args.size()!=2 or args[0] not in ["baseline","candidate"] or args[1]!=Rules.BUILD_ID:
  JavaScriptBridge.eval("window.vcEdgeFailure='External role/build argument mismatch'");return
 var candidate=args[0]=="candidate"
 await frames(6)
 var g=load("res://main.tscn").instantiate()
 g.skirmish_mode="survival";g.qa_mode=true
 root.add_child(g);g.set_process(false)
 g.toast_time=0.0;g.toast_label.visible=false
 await frames(6)
 g.camera_focus=Vector3(-25,0,11);g.camera_zoom=22.0
 g._camera_update();g._layout_ui();g._update_hud();g._update_visuals(0.0)
 await frames(6)
 var draws=[0]
 var marker=func():draws[0]+=1
 RenderingServer.frame_post_draw.connect(marker)
 var begin=Time.get_ticks_msec()
 while draws[0]<4 and Time.get_ticks_msec()-begin<25000:await process_frame
 RenderingServer.frame_post_draw.disconnect(marker)
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
 var st=Codec.capture_result(g);var hud=g._qa_hud_snapshot()
 var visibility=[g.visible_cells.duplicate(true),g.explored_cells.duplicate(true),g.fog_render_state.duplicate()]
 var samples=[]
 for y in range(5,SIZE.y-5,15):
  for x in range(5,SIZE.x-5,15):
   var p=Vector2(x,y);samples.append([x,y,g._box_point_in_world(p),g._pick(p),vec(g._world_at(p))])
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
 JavaScriptBridge.eval("window.vcEdgeWitness="+JSON.stringify(result)+";",true)
