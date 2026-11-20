extends SceneTree
var checks=[]
var images={}
var g
var out=""
var size=Vector2i(390,844)
func _initialize():call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func settle():
 for i in 5:await process_frame
func tap(point):
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.index=13;e.position=point;e.pressed=down;root.push_input(e);await process_frame
 await settle()
func frame(name,zoom):
 g.camera_zoom=zoom
 g._camera_update();g._refresh_fog();g._update_visuals(0.0);g._update_hud()
 if out.is_empty():return
 RenderingServer.render_loop_enabled=true
 await settle()
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 DirAccess.make_dir_recursive_absolute(out)
 var path=out+"/"+name+".png"
 check("actual renderer captured "+name,image.save_png(path)==OK and image.get_size()==size)
 images[name]={"size":[size.x,size.y],"sha256":FileAccess.get_sha256(path)}
 RenderingServer.render_loop_enabled=false
func run():
 var a=OS.get_cmdline_user_args();assert(a.size()==5)
 size=Vector2i(int(a[1]),int(a[2]));root.size=size
 if DisplayServer.get_name()!="headless":out=a[0];RenderingServer.render_loop_enabled=false
 g=load("res://main.tscn").instantiate();g.layout_id="valley";g.skirmish_mode="standard";g.qa_mode=true
 root.add_child(g);g.set_process(false);await settle()
 check("exact normal Classic source opening",g._snapshot().build==a[3] and g._population(0)==6 and g.tick_count<=2)
 var original_stock=g.economy.bank_milli(0).duplicate()
 var scout=g._first(0,"scout")
 var initial_scout=scout.pos
 g.camera_focus=Vector3(-25.5,0,25.5);g.camera_zoom=30;g._camera_update();await settle()
 var on_screen=g.camera.unproject_position(scout.pos+Vector3(0,0.6,0))
 check("actual scout selectable on public ground",g._pick(on_screen)==scout.id and g._box_point_in_world(on_screen))
 await tap(on_screen)
 check("ordinary unit selection",g.selected==[scout.id])
 var before=g.command_sequence
 for p in g._qa_hud_snapshot().ground_points:
  if Vector2(p[0],p[1]).distance_to(on_screen)<65:continue
  await tap(Vector2(p[0],p[1]))
  if g.command_sequence>before:break
 check("ordinary contextual ground click sends one direct order",g.command_sequence==before+1 and not g.touch_command)
 for i in range(20):g._tick(0.05)
 check("selected actor actually moved and ledger unchanged",scout.pos.distance_to(initial_scout)>.50 and g.economy.bank_milli(0)==original_stock and g.economy.audit().ok)
 await frame("courtyard-normal",30.0)
 await frame("courtyard-distant",42.0)
 var failed=checks.filter(func(c):return not c.passed).size()
 var j={"build":g._snapshot().build,"role":a[4],"checks":checks,"failed":failed,"images":images,"size":[size.x,size.y],"world":{"tick":g.tick_count,"bank":g.economy.bank_milli(0),"scout":str(scout.pos),"camera":str(g.camera_focus),"selected":g.selected}}
 print(JSON.stringify(j))
 if not out.is_empty():
  var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
  f.store_string(JSON.stringify(j))
 g.queue_free();quit(1 if failed else 0)
