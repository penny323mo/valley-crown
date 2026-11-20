extends SceneTree
var checks=[]
var images={}
var g
var out=""
var sz=Vector2i(390,844)
var evidence={}
func _initialize():call_deferred("run")
func note(label,condition):
 checks.append({"name":label,"passed":bool(condition)})
 if not condition:push_error(label)
func settle():
 for i in 5:await process_frame
func tap_xy(p):
 for press in [true,false]:
  var e=InputEventScreenTouch.new();e.position=p;e.index=5;e.pressed=press;root.push_input(e);await process_frame
 await settle()
func focus(center):
 g.camera_focus=center;g.camera_zoom=30.0
 g._camera_update();g._update_visuals(0);g._refresh_fog();g._update_hud()
 await settle()
func actor_touch(id):
 var ent=g._get_entity(id)
 await focus(ent.pos)
 var at=g.camera.unproject_position(ent.pos+Vector3(0,.6,0))
 for delta in [Vector2.ZERO,Vector2(0,4),Vector2(3,0),Vector2(-3,0),Vector2(0,-4),Vector2(0,9)]:
  var p=at+delta
  if not g._box_point_in_world(p) or g._pick(p)!=id:continue
  await tap_xy(p)
  if g.selected==[id]:return true
 print("ACTOR_DIAGNOSTIC ",id," ",at," picked=",g._pick(at)," selected=",g.selected)
 return false
func frame(name):
 if out.is_empty():return
 RenderingServer.render_loop_enabled=true
 await settle()
 await RenderingServer.frame_post_draw
 var bitmap=root.get_texture().get_image()
 DirAccess.make_dir_recursive_absolute(out)
 var f=out+"/"+name+".png"
 note("authentic rendered game "+name,bitmap.save_png(f)==OK and bitmap.get_size()==sz)
 images[name]={"size":[sz.x,sz.y],"sha256":FileAccess.get_sha256(f)}
 RenderingServer.render_loop_enabled=false
func gather(kind,stock_name,unit,center):
 await focus(center)
 var row={}
 for t in g._qa_hud_snapshot().context_targets:
  if t.kind==kind:row=t;break
 if row.is_empty():
  note("visible actual resource "+kind,false);return false
 var before=g.economy.bank_milli(0)[stock_name]
 var p=Vector2(row.screen[0],row.screen[1])
 var before_cmd=g.command_sequence
 await tap_xy(p)
 for n in 35:g._tick(.05)
 var worker=g._get_entity(unit)
 note("normal direct "+kind+" touch submitted intended resource",g.command_sequence==before_cmd+1 and worker.get("target",-1)==row.id and worker.state in ["gather","deliver"])
 await focus(center)
 await frame(kind)
 for n in 1200:
  g._tick(.05)
  if g.economy.bank_milli(0)[stock_name]>before:break
 var del=g.economy.bank_milli(0)[stock_name]-before
 note("paid stock credits from genuine "+kind+" harvest",del>0 and g.economy.audit().ok)
 var resource=g._get_entity(row.id)
 evidence[kind]={"id":row.id,"credit_milli":del,"remaining":resource.hp,"tick":g.tick_count,"worker":unit,"scout":str(g._first(0,"scout").pos)}
 return del>0
func run():
 var args=OS.get_cmdline_user_args()
 assert(args.size()==5)
 sz=Vector2i(int(args[1]),int(args[2]));root.size=sz
 if DisplayServer.get_name()!="headless":out=args[0];RenderingServer.render_loop_enabled=false
 g=load("res://main.tscn").instantiate();g.qa_mode=true;g.layout_id="valley";g.skirmish_mode="standard"
 root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 note("actual exact Classic game baseline",g._snapshot().build==args[3] and g._population(0)==6)
 var worker=g._first(0,"villager").id
 var ok=await actor_touch(worker)
 note("original worker selected by actual touch",ok)
 if ok:ok=await gather("berry","food",worker,Vector3(-29.5,0,25.0))
 # Native viewport rotate witness. Both roles scout using the same ordinary
 # portrait move; resources are then selected and gathered at the tested size.
 root.size=Vector2i(390,844);await settle()
 var scout=g._first(0,"scout").id
 if ok:ok=await actor_touch(scout)
 if ok:
  var dest=Vector3(-31.5,0,22.5)
  await focus(Vector3(-30.5,0,22.5))
  var point=g.camera.unproject_position(dest)
  if g._box_point_in_world(point) and g._pick(point)<0 and g.visible_cells[0][g._cell_index(dest)]!=0 and not g.navigation.is_point_solid(g._cell(dest)):
   var before_nav=g.command_sequence
   await tap_xy(point)
   for n in 240:g._tick(.05)
   print("ORDINARY_SCOUT ",dest," ",g.command_sequence-before_nav," ",g._get_entity(scout).pos)
   ok=g.command_sequence==before_nav+1 and g._get_entity(scout).pos.distance_to(dest)<1.4
  else:ok=false
 root.size=sz;await settle()
 note("ordinary scout order and return to target viewport",ok and root.size==sz)
 if ok:
  ok=await actor_touch(worker)
  note("same original worker remains selectable",ok)
 if ok:ok=await gather("stone","stone",worker,Vector3(-32.5,0,19.0))
 note("both original physical harvest and ledger succeed",ok and evidence.size()==2 and g.economy.audit().ok)
 var f=checks.filter(func(c):return not c.passed)
 var report={"checks":checks,"failed":f.size(),"size":[sz.x,sz.y],"role":args[4],"build":g._snapshot().build,"images":images,"world":evidence}
 print(JSON.stringify(report))
 if not out.is_empty():
  var file=FileAccess.open(out+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report))
 g.queue_free();quit(0 if f.is_empty() else 1)
