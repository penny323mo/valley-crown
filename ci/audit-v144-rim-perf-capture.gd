extends SceneTree
func _initialize():call_deferred("run")
func settle(n):
 for i in n:await process_frame
func run():
 var a=OS.get_cmdline_user_args();assert(a.size()==5)
 var size=Vector2i(int(a[1]),int(a[2]));root.size=size
 RenderingServer.render_loop_enabled=false
 var g=load("res://main.tscn").instantiate()
 g.layout_id="valley";g.skirmish_mode="standard";g.qa_mode=true
 root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle(5)
 assert(root.size==size and g._snapshot().build==a[3])
 g.camera_focus=Vector3(-35,0,35) if size.x>size.y else Vector3(-25,0,24)
 g.camera_zoom=42 if size.x>size.y else 30
 g._camera_update();g._refresh_fog();g._update_visuals(0.0);g._update_hud()
 var old=g.camera_ground.material_override
 var scene_shader=old.shader
 var candidate_shader=load("res://assets/mature/terrain/rim-alternative.gdshader")
 assert(candidate_shader is Shader and scene_shader.code!=candidate_shader.code)
 var candidate=ShaderMaterial.new();candidate.shader=candidate_shader
 for key in ["map_size","public_home_a","public_home_b","grass_map","earth_map","public_corridor_mask"]:
  candidate.set_shader_parameter(key,old.get_shader_parameter(key))
  assert(old.get_shader_parameter(key)==candidate.get_shader_parameter(key))
 var results=[]
 RenderingServer.render_loop_enabled=true
 for role in ["baseline","candidate","candidate","baseline"]:
  g.camera_ground.material_override=old if role=="baseline" else candidate
  for i in range(2): await RenderingServer.frame_post_draw
  var timings=[]
  for i in range(4):
   var us=Time.get_ticks_usec()
   await RenderingServer.frame_post_draw
   timings.append((Time.get_ticks_usec()-us)/1000.0)
  results.append({"role":role,"samples_ms":timings})
 RenderingServer.render_loop_enabled=false
 var j={"build":g._snapshot().build,"scope":"same-host ABBA warmed actual engine softpipe; not phone/GPU-specific","size":[size.x,size.y],"camera":{"focus":str(g.camera_focus),"zoom":g.camera.size},"variants":results,"tick":g.tick_count}
 DirAccess.make_dir_recursive_absolute(a[0])
 FileAccess.open(a[0]+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(j))
 print(JSON.stringify(j))
 g.queue_free();quit()
