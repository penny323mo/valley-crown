extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Product fortress existing units, controlled normal movement/attacks for both factions with AI scheduling disabled. Two real own-damage alerts; no fixture spawns, HP/stock/fog changes, artificial alert insertion or save operations. Native synthetic viewport touch, not physical phone or autonomous full-match proof."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"passed":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func tick():g._tick(Rules.TICK);g._update_visuals(Rules.TICK)
func tap(p):
 var e=InputEventScreenTouch.new();e.position=p;e.index=55;e.pressed=true;root.push_input(e,false);await process_frame
 e=InputEventScreenTouch.new();e.position=p;e.index=55;e.pressed=false;root.push_input(e,false);await settle()
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();g.minimap.queue_redraw();await settle()
 var alerts=g.battle_alerts.pending(g.tick_count);var markers=[]
 for a in alerts:
  var local=Vector2(9,9)+Vector2((a.position.x+40)/80,(a.position.z+40)/80)*(g.minimap.size-Vector2(18,18))
  markers.append({"sequence":a.sequence,"world":str(a.position),"screen":str(g.minimap.global_position+local),"radius":5})
 var row={"name":name,"tick":g.tick_count,"selected":g.selected.duplicate(),"camera":str(g.camera_focus),"zoom":g.camera_zoom,"alert_text":g.battle_jump_button.text,"alert_visible":g.battle_jump_button.is_visible_in_tree(),"alert_rect":str(g.battle_jump_button.get_global_rect()),"map_rect":str(g.minimap.get_global_rect()),"markers":markers,"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(c):return not c.passed).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/battle-alert-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(844,390);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for file in ["game","battle_alerts","minimap"]:report[file+"_sha256"]=FileAccess.get_sha256("res://scripts/"+file+".gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="fortress";root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 var cars=[];var foes=[]
 for u in g.entities:
  if u.kind=="siege" and u.team==0:cars.append(u)
  if u.kind=="archer" and u.team==1:foes.append(u)
 report.initial_count=g.entities.size()
 if not check("existing scenario actors available",cars.size()==2 and foes.size()>=2):finish();return
 for i in 2:
  g._submit("order",{"ids":[cars[i].id],"target":-1,"position":Vector3(0,0,8-i*14)})
  g._submit("order",{"ids":[foes[i].id],"target":-1,"position":Vector3(4,0,8-i*14)},1)
 for i in 700:tick()
 report.approach=cars.map(func(u):return {"id":u.id,"pos":str(u.pos),"hp":u.hp})
 g._submit("stop",{"ids":cars.map(func(u):return u.id)});tick()
 for i in 2:g._submit("order",{"ids":[foes[i].id],"target":cars[i].id,"position":cars[i].pos},1)
 for i in 350:
  tick()
  if g.battle_alerts.pending(g.tick_count).size()==2:break
 if not check("two simultaneous actual settled damage locations",g.battle_alerts.pending(g.tick_count).size()==2 and cars.all(func(u):return u.alive and u.hp<u.max_hp)):finish();return
 g._submit("stop",{"ids":[foes[0].id,foes[1].id]},1);tick()
 g._select([g._first(0,"town_center").id]);g.camera_focus=g._first(0,"town_center").pos;g.camera_zoom=22;g.compact_map_choice=1;g._camera_update();g._layout_ui();g._update_hud();await settle()
 var alerts=g.battle_alerts.pending(g.tick_count);var first=alerts[0].position;var second=alerts[1].position
 var span=Vector2(first.x-second.x,first.z-second.z).length()/80*(g.minimap.size.x-18)
 check("map markers visually separated beyond diameters",span>12 and g.minimap.is_visible_in_tree())
 check("top two-alert action visible without overlap",g.battle_jump_button.is_visible_in_tree() and g.battle_jump_button.text.contains("2") and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(g.battle_jump_button.get_global_rect()))
 await shot("01-two-battle-locations")
 var selected=g.selected.duplicate();var commands=g.commands.duplicate(true);var visible=g.visible_cells[0].duplicate();var explored=g.explored_cells[0].duplicate();var now=g.tick_count
 await tap(g.battle_jump_button.get_global_rect().get_center())
 check("routed tap focuses first and acknowledges one",g.camera_focus==first and g.battle_alerts.pending(g.tick_count).size()==1 and not g.compact_menu.visible)
 await shot("02-first-battle-focused")
 await tap(g.battle_jump_button.get_global_rect().get_center())
 check("routed second tap focuses second and clears alerts",g.camera_focus==second and g.battle_alerts.pending(g.tick_count).is_empty() and not g.battle_jump_button.visible)
 await shot("03-second-battle-acknowledged")
 check("navigation leaves authority fog and selected orders untouched",g.tick_count==now and g.commands==commands and g.selected==selected and g.visible_cells[0]==visible and g.explored_cells[0]==explored)
 check("original roster retained",g.entities.size()==report.initial_count)
 report.damaged_hp=cars.map(func(u):return u.hp)
 finish()
