extends SceneTree
const Layout=preload("res://scripts/battlefield_layout.gd")
const River=preload("res://scripts/river_terrain.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
var images={}
var g
var shell
var out=""
var realsize=Vector2i(390,844)
var scout=-1
var traveled={}
var strategic_sight={}
func _initialize():call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func settle():
 for i in 4:await process_frame
func tap(screen:Vector2):
 for pressed in [true,false]:
  var e=InputEventScreenTouch.new();e.position=screen;e.index=7;e.pressed=pressed
  root.push_input(e);await process_frame
 await settle()
func press_menu(control:String):
 var button=shell.buttons.get_node_or_null(control)
 if button==null:
  check("visible menu "+control,false);return
 var n=button.get_parent()
 while n!=null:
  if n is ScrollContainer:
   n.ensure_control_visible(button);await settle();break
  n=n.get_parent()
 check("touch menu "+control,button.is_visible_in_tree() and button.size.y>=44 and root.get_visible_rect().encloses(button.get_global_rect()))
 await tap(button.get_global_rect().get_center())
func frame(key):
 if out.is_empty():return
 RenderingServer.render_loop_enabled=true
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 RenderingServer.render_loop_enabled=false
 DirAccess.make_dir_recursive_absolute(out)
 var path=out+"/"+key+".png"
 check("real rendered "+key,im.save_png(path)==OK and im.get_size()==realsize)
 images[key]={"size":[im.get_width(),im.get_height()],"sha256":FileAccess.get_sha256(path)}
func point_camera(location):
 g.camera_focus=location;g._camera_update();g._update_visuals(0.0);g._refresh_fog();g._update_hud()
 await settle()
func send_scout(target):
 await point_camera(target)
 var xy=g.camera.unproject_position(target)
 check("normal camera target reachable by direct tap",g._box_point_in_world(xy))
 var before=g.command_sequence
 await tap(xy)
 return g.command_sequence==before+1
func observed_targets():
 var wood=[]
 var iron=[]
 for r in g.faction_views[0].records().values():
  if r.category!="resource" or r.remembered or not r.alive:continue
  if r.kind in ["pine","oak"] and r.pos.x<-18 and r.pos.z>9 and r.pos.z<15:wood.append([r.id,str(r.pos)])
  if r.kind=="iron" and r.pos.x>18 and r.pos.z>6 and r.pos.z<11:iron.append([r.id,str(r.pos)])
 return {"wood":wood,"iron":iron}
func actual_walk(target,stage,expected):
 if not await send_scout(target):
  check("actual normal move "+stage,false);return false
 var snapshots=[]
 var crossed=0
 var forbidden=0
 for i in range(700):
  g._tick(.05)
  var actor=g._get_entity(scout)
  if actor.is_empty() or not actor.alive:break
  var surface=River.surface_at(g.layout_id,g._cell(actor.pos))
  if surface==River.WATER:forbidden+=1
  if surface==expected and expected!=River.DRY:
   crossed+=1
   if crossed==8:
    await point_camera(Vector3(target.x,0,0))
    await frame(stage)
  if i%25==0:snapshots.append([g.tick_count,str(actor.pos),actor.get("path_status",""),actor.get("path_reason","")])
  if actor.pos.distance_to(target)<0.9:
   traveled[stage]={"cross_ticks":crossed,"wet_steps":forbidden,"finished":g.tick_count,"samples":snapshots}
   check("actual walk reaches destination without entering water "+stage,forbidden==0 and (expected==River.DRY or crossed>0))
   return forbidden==0 and (expected==River.DRY or crossed>0)
 traveled[stage]={"cross_ticks":crossed,"wet_steps":forbidden,"finished":-1,"samples":snapshots}
 check("actual travel completed "+stage,false)
 return false
func run():
 var args=OS.get_cmdline_user_args()
 if args.size()>=3:
  realsize=Vector2i(int(args[1]),int(args[2]))
  if DisplayServer.get_name()!="headless":out=args[0];RenderingServer.render_loop_enabled=false
 root.size=realsize
 shell=load("res://main_menu.tscn").instantiate()
 root.add_child(shell)
 await settle()
 for name in ["StartMatchButton","BattleGroup0","ChooseBattle_standard","ChooseLayoutButton","LayoutRiverCrossingsButton"]:await press_menu(name)
 check("normal selectable fourth optional layout landed in setup",shell.selected_layout==River.ID and shell.page=="setup")
 await frame("layout-overview")
 await press_menu("LaunchMatchButton")
 g=shell.match_node
 assert(is_instance_valid(g) and g.layout_id==River.ID)
 g.history_path="/tmp/isolated-river-pilot-no-write.json"
 g.set_process(false);g.test_mode=true
 var actor=g._first(0,"scout")
 scout=actor.id
 await point_camera(actor.pos)
 var start=g.camera.unproject_position(actor.pos+Vector3(0,0.6,0))
 await tap(start)
 check("normal world tap selects the actual original scout",g.selected==[scout])
 strategic_sight["initial"]=observed_targets()
 var moved=await actual_walk(Vector3(-13.5,0,8.5),"bridge-bank",River.DRY)
 strategic_sight["bridge_bank"]=observed_targets()
 if moved:moved=await actual_walk(Vector3(-13.5,0,-8.5),"bridge-crossing",River.BRIDGE)
 if moved:moved=await actual_walk(Vector3(13.5,0,-8.5),"ford-bank",River.DRY)
 if moved:moved=await actual_walk(Vector3(13.5,0,8.5),"ford-crossing",River.FORD)
 strategic_sight["ford_bank"]=observed_targets()
 check("both ordinary actual scout crossings are completed",moved)
 var extra_wood=strategic_sight.bridge_bank.wood.filter(func(row):return not row in strategic_sight.initial.wood)
 check("near bridge exposes at least two additional actual trees absent from opening view",extra_wood.size()>=2)
 check("ford arrival opens different visible iron away from starting keep",strategic_sight.bridge_bank.iron.is_empty() and not strategic_sight.ford_bank.iron.is_empty())
 var capture=Codec.capture_result(g)
 check("new layout exact-build save format still compatible",capture.ok)
 if capture.ok:
  var data=capture.data
  var damaged=data.duplicate(true)
  var water=g.public_terrain.keys()[0]
  damaged.work_memory[0].grid_solids.erase(water)
  check("checkpoint with suppressed static water rejected",Codec.validation_result(damaged).get("reason")=="PUBLIC_TERRAIN_OMITTED")
  var restored=load("res://main.tscn").instantiate()
  restored.layout_id=River.ID;restored.skirmish_mode="standard"
  root.add_child(restored);restored.set_process(false)
  check("checkpoint loads identical layout with immutable terrain and exact scout cell",Restore.apply(restored,data) and restored.work_memory[0].grid.is_point_solid(water) and restored._get_entity(scout).pos==g._get_entity(scout).pos)
  restored.queue_free()
 check("normal AI stayed activated and actual ledger conserved",g.ai_enabled and g.economy.audit().ok)
 var n=checks.filter(func(row):return not row.passed).size()
 var report={"checks":checks,"failed":n,"size":[realsize.x,realsize.y],"images":images,"layout":g.layout_id,"paths":traveled,"resources_by_approach":strategic_sight,"build":g._snapshot().build,"scope":"native actual menu/direct touch player reconnaissance and same-build terrain checkpoint; not complete gameplay or device acceptance"}
 if not out.is_empty():
  var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
  if f!=null:f.store_string(JSON.stringify(report));f.close()
 print("RIVER_MOBILE_PROOF "+JSON.stringify(report))
 print(JSON.stringify({"suite":"river_touch_crossing_contract","checks":checks,"failed":n,"scope":"Ordinary portrait-size native menu/direct touch reconnaissance and same-build terrain checkpoint; not whole gameplay, browser or device acceptance."}))
 g.queue_free();quit(0 if n==0 else 1)
