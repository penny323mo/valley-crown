extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Ordinary practice seed with ordinary queued worker movement if initial positions lack overlap. Camera zoom/frame chosen to expose a real own-unit/building selection overlap. Actual root viewport synthetic touch; no extra spawning, position/HP/stock/fog edits, save operations or physical-phone acceptance. AI scheduling disabled during demonstration."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"passed":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func tap(p):
 var e=InputEventScreenTouch.new();e.position=p;e.index=20;e.pressed=true;root.push_input(e,false);await process_frame
 e=InputEventScreenTouch.new();e.position=p;e.index=20;e.pressed=false;root.push_input(e,false);await settle()
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await settle()
 var row={"name":name,"tick":g.tick_count,"selected":g.selected.duplicate(),"title":g.selection_title.text,"zoom":g.camera_zoom,"camera":str(g.camera_focus),"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(c):return not c.passed).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/pick-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(390,844);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path);report.game_sha256=FileAccess.get_sha256("res://scripts/game.gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 var positions={}
 for u in g.entities:positions[str(u.id)]=str(u.pos)
 var keep=g._first(0,"town_center");g.camera_focus=keep.pos;g._layout_ui();g._select([]);await settle()
 var chosen=await find_overlap(keep)
 var worker=g._first(0,"villager")
 report.ordinary_move_attempts=[]
 if chosen.is_empty():
  for offset in [Vector3(3,0,0),Vector3(-3,0,0),Vector3(0,0,3),Vector3(0,0,-3)]:
   var target=keep.pos+offset
   g._submit("order",{"ids":[worker.id],"target":-1,"position":target})
   for i in 150:g._tick(Rules.TICK);g._update_visuals(Rules.TICK)
   report.ordinary_move_attempts.append({"target":str(target),"actual":str(worker.pos),"tick":g.tick_count})
   g._select([]);await settle()
   chosen=await find_overlap(keep)
   if not chosen.is_empty():break
 if not check("ordinary units have real nearer-worker building overlap",not chosen.is_empty()):finish();return
 report.target={"screen":str(chosen.point),"unit_center":str(chosen.unit_center),"building_center":str(chosen.building_center),"unit_distance":chosen.point.distance_to(chosen.unit_center),"building_distance":chosen.point.distance_to(chosen.building_center),"unit_id":chosen.worker,"legacy_building_id":chosen.legacy,"zoom":g.camera_zoom}
 await shot("01-ordinary-worker-building-overlap")
 var count=g.commands.size();await tap(chosen.point)
 check("routed touch selects nearer worker without order",g.selected==[chosen.worker] and g.commands.size()==count)
 await shot("02-nearer-worker-selected")
 var center=chosen.building_center
 check("building center still has building priority",g._friendly_unit_pick(center,g._pick(center))==keep.id)
 await tap(center)
 check("routed building center selects building without order",g.selected==[keep.id] and g.commands.size()==count)
 await shot("03-building-center-still-selectable")
 check("original entity roster retained, no fixture spawns",g.entities.size()==positions.size())
 check("building position unchanged",positions[str(keep.id)]==str(keep.pos))
 finish()

func find_overlap(keep):
 var chosen={}
 for zoom in [22.0,30.0,38.0,46.0]:
  g.camera_zoom=zoom;g._camera_update();await settle()
  for u in g.faction_views[0].records().values():
   if not u.owned or not u.alive or u.kind!="villager":continue
   var center=g.camera.unproject_position(u.pos+Vector3(0,.6,0))
   for dy in range(-14,15,2):
    for dx in range(-14,15,2):
     var p=center+Vector2(dx,dy)
     if not g._box_point_in_world(p):continue
     var winner=g._pick(p);var nearer=g._friendly_unit_pick(p,winner)
     if winner==keep.id and nearer==u.id:
      chosen={"point":p,"worker":u.id,"legacy":winner,"unit_center":center,"building_center":g.camera.unproject_position(keep.pos+Vector3(0,1,0))};break
    if not chosen.is_empty():break
   if not chosen.is_empty():break
  if not chosen.is_empty():break
 return chosen
