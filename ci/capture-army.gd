extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var worker
var troops=[]
var out=""
var checks=[]
var metadata_only=false
var report={"captures":[],"scope":"Controlled spawned five military types alongside ordinary starting villager with normal queued gather intent. Real product action and root-dispatched touch drag/primary click. No troop production claim, health/resource/fog edits or physical phone/browser acceptance."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"pass":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func touch(p,down):
 var e=InputEventScreenTouch.new();e.position=p;e.index=10;e.pressed=down;root.push_input(e);await process_frame
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await settle()
 var units=[]
 for u in [worker]+troops:units.append({"id":u.id,"kind":u.kind,"position":str(u.pos),"state":u.state,"target":u.target,"work_epoch":u.get("work_epoch",-1)})
 var row={"name":name,"tick":g.tick_count,"selected":g.selected.duplicate(),"title":g.selection_title.text,"summary":g.selection_summary.text,"box_mode":g.box_select_mode,"military_only":g.box_select_military_only,"units":units,"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v95-army-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(960,640);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 report.game_sha256=FileAccess.get_sha256("res://scripts/game.gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 worker=g._first(0,"villager");var resource={};var best=INF
 for r in g.faction_views[0].records().values():
  if r.kind=="berry" and not r.remembered and r.pos.distance_to(worker.pos)<best:best=r.pos.distance_to(worker.pos);resource=r
 if not check("normal visible gather target",not resource.is_empty()):finish();return
 g._submit("order",{"ids":[worker.id],"target":resource.id,"position":resource.pos});g._tick(Rules.TICK)
 report.original_spawn_diagnostic=[]
 for i in 5:
  var old=worker.pos+Vector3(2+i*1.4,0,0)
  report.original_spawn_diagnostic.append({"position":str(old),"nav_solid":g.navigation.is_point_solid(g._cell(old))})
 var sites=[]
 for z in range(-7,8):
  for x in range(-7,8):
   var pos=g._point(g._cell(worker.pos+Vector3(x,0,z)))
   var clear=true
   for dz in range(-1,2):
    for dx in range(-1,2):
     var cell=g._cell(pos)+Vector2i(dx,dz)
     if not g.navigation.region.has_point(cell) or g.navigation.is_point_solid(cell):clear=false
   for u in g.entities:
    if u.alive and u.category=="unit" and u.pos.distance_to(pos)<1.8:clear=false
   if clear:sites.append(pos)
 sites.sort_custom(func(a,b):return a.distance_squared_to(worker.pos)<b.distance_squared_to(worker.pos))
 var chosen=[]
 for pos in sites:
  if chosen.any(func(q):return q.distance_to(pos)<2.0):continue
  chosen.append(pos)
  if chosen.size()==5:break
 if not check("five legal separated fixture sites",chosen.size()==5):finish();return
 for i in 5:troops.append(g._spawn(["scout","spearman","archer","cavalry","siege"][i],0,chosen[i]))
 for i in 5:
  var old=worker.pos+Vector3(2+i*1.4,0,0)
  var overlap=[]
  for other in g.entities:
   if other.alive and other.category=="unit" and not other in troops and old.distance_to(other.pos)<troops[i].radius+other.radius:overlap.append({"id":other.id,"kind":other.kind,"pos":str(other.pos)})
  report.original_spawn_diagnostic[i].overlap_existing_units=overlap
  report.original_spawn_diagnostic[i].route_solid=g._route_grid(troops[i]).is_point_solid(g._cell(old))
 check("all starts navigable",troops.all(func(u):return not g._route_grid(u).is_point_solid(g._cell(u.pos))))
 report.fixture_sites=chosen.map(func(p):return str(p))
 g._update_vision();g._publish_faction_views();g.camera_focus=worker.pos+Vector3(4,0,0);g.camera_zoom=22;g._camera_update();g._layout_ui();await settle()
 var rect=Rect2(g.camera.unproject_position(worker.pos+Vector3(0,.6,0)),Vector2.ZERO)
 for u in troops:rect=rect.expand(g.camera.unproject_position(u.pos+Vector3(0,.6,0)))
 rect=rect.grow(12)
 if not check("box entirely in world",g._box_point_in_world(rect.position) and g._box_point_in_world(rect.end)):finish();return
 var epoch=worker.work_epoch;var target=worker.target
 g.compact_menu_button.pressed.emit();await settle();g.shortcut_category_buttons.army.pressed.emit();await settle()
 var b=g.find_child("ArmyBoxSelect",true,false);g.shortcut_scroll.ensure_control_visible(b);await settle()
 check("visible army action",b.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(b.get_global_rect()))
 await shot("01-army-box-action")
 b.pressed.emit();await settle()
 await touch(rect.position,true)
 var drag=InputEventScreenDrag.new();drag.position=rect.end;drag.index=10;drag.relative=rect.size;root.push_input(drag);await process_frame
 await shot("02-military-box-drag")
 await touch(rect.end,false)
 check("five military types selected not villager",g.selected.size()==5 and worker.id not in g.selected and troops.all(func(u):return u.id in g.selected))
 check("one shot filter cleared",not g.box_select_mode and not g.box_select_military_only)
 await shot("03-selected-five-types")
 var starts=troops.map(func(u):return u.pos)
 var p=g.camera.unproject_position(worker.pos+Vector3(0,0,5))
 for down in [true,false]:
  var e=InputEventMouseButton.new();e.position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e);await process_frame
 check("ordinary troop-only order",g.commands.any(func(c):return c.get("type","")=="order" and worker.id not in c.get("ids",[])))
 for i in 80:g._tick(Rules.TICK)
 check("all five selected troops actually move",range(5).all(func(i):return troops[i].pos.distance_to(starts[i])>1.0))
 check("villager retains gathering intent",worker.work_epoch==epoch and worker.target==target and worker.state in ["move","gather","deliver"])
 await shot("04-troops-move-worker-continues")
 finish()
