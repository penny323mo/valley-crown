extends SceneTree
var details={}
var g
var out=""
var size=Vector2i(390,844)
var snapshots={}
var checks=[]
func _initialize():call_deferred("run")
func ck(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func settle(count=5):
 for i in count:await process_frame
func tap(point):
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.index=13;e.position=point;e.pressed=down;root.push_input(e);await process_frame
 await settle()
func pan():
 var taps=[Vector2(size.x*.45,size.y*.48),Vector2(size.x*.57,size.y*.48)]
 for i in 2:
  var e=InputEventScreenTouch.new();e.index=8+i;e.position=taps[i];e.pressed=true;root.push_input(e)
 await settle()
 for i in 2:
  var e=InputEventScreenDrag.new();e.index=8+i;e.position=taps[i]+Vector2(24,8);e.relative=Vector2(24,8);root.push_input(e)
 await settle()
 for i in 2:
  var e=InputEventScreenTouch.new();e.index=8+i;e.position=taps[i]+Vector2(24,8);e.pressed=false;root.push_input(e)
 await settle()
func world_rays():
 var world=[]
 for xy in [Vector2.ZERO,Vector2(size.x,0),Vector2(0,size.y),Vector2(size)]:
  var origin=g.camera.project_ray_origin(xy);var ray=g.camera.project_ray_normal(xy)
  var p=origin+ray*(-origin.y/ray.y)
  world.append([p.x,p.z])
 return world
func frame(name,zoom,focus):
 g.camera_focus=focus;g.camera_zoom=zoom
 g._camera_update();g._refresh_fog();g._update_visuals(0.0);g._update_hud()
 var sh=HashingContext.new()
 sh.start(HashingContext.HASH_SHA256)
 sh.update(g.visible_cells[0]+g.explored_cells[0])
 var fog=sh.finish().hex_encode()
 var row={"focus":str(g.camera_focus),"zoom":g.camera.size,"bounds":world_rays(),"fog":fog,"tick":g.tick_count,"sel":g.selected.duplicate(),"bank":g.economy.bank_milli(0),"scout":str(g._first(0,"scout").pos)}
 snapshots[name]=row
 if out.is_empty():return
 RenderingServer.render_loop_enabled=true
 await settle(13)
 var times=[]
 for i in range(20):
  var begin=Time.get_ticks_usec()
  await RenderingServer.frame_post_draw
  times.append((Time.get_ticks_usec()-begin)/1000.0)
  await process_frame
 times.sort()
 var image=root.get_texture().get_image()
 DirAccess.make_dir_recursive_absolute(out)
 var path=out+"/"+name+".png"
 ck("actual engine frame "+name,image.save_png(path)==OK and image.get_size()==size)
 details[name]={"size":[size.x,size.y],"sha256":FileAccess.get_sha256(path),"render_wait_ms_p50":times[10],"render_wait_ms_p90":times[18]}
 RenderingServer.render_loop_enabled=false
func make(layout):
 g=load("res://main.tscn").instantiate();g.layout_id=layout;g.skirmish_mode="standard";g.qa_mode=true
 root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 g.camera_zoom=22 if size.x>size.y else 30
 g._camera_update()
 await settle()
func run():
 var a=OS.get_cmdline_user_args();assert(a.size()==5)
 size=Vector2i(int(a[1]),int(a[2]));root.size=size
 if DisplayServer.get_name()!="headless":out=a[0];RenderingServer.render_loop_enabled=false
 await make("valley")
 ck("same exact classic source and populations",g._snapshot().build==a[3] and g._population(0)==6)
 var home=g.camera_focus
 var zoom=g.camera_zoom
 var scout=g._first(0,"scout")
 var point=g.camera.unproject_position(scout.pos+Vector3(0,.6,0))
 await tap(point);ck("actual scout selection",g.selected==[scout.id])
 await frame("classic-opening",zoom,home)
 var seq=g.command_sequence
 await tap(Vector2(472,122) if size.x>size.y else Vector2(263,292))
 for i in 100:g._tick(.05)
 ck("actual narrow scout move survives visual treatment",g.command_sequence==seq+1 and scout.pos.distance_to(Vector3(-21,0,22))>5.0)
 var prev_camera=g.camera_focus
 seq=g.command_sequence
 await pan()
 ck("actual two-touch camera pan still applied without an order",g.camera_focus.distance_to(prev_camera)>.1 and g.command_sequence==seq)
 await frame("classic-corner-wide",42.0,Vector3(-35,0,35))
 ck("economy remains conserved",g.economy.audit().ok)
 g.queue_free();await settle()
 await make("river_crossings")
 ck("actual river route layout retained",g.layout_id=="river_crossings")
 await frame("river-confirmed",zoom,g.camera_focus)
 var failed=checks.filter(func(c):return not c.passed).size()
 var j={"build":g._snapshot().build,"role":a[4],"checks":checks,"failed":failed,"images":details,"size":[size.x,size.y],"world":{"frames":snapshots}}
 print(JSON.stringify(j))
 if not out.is_empty():FileAccess.open(out+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(j))
 g.queue_free();quit(1 if failed else 0)
