extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Product fortress scenario existing units, controlled ordinary orders for both sides with AI scheduling disabled. Actual enemy attacks and ordinary travel/paid repairs; no extra spawns, position/HP/resource/fog overrides or save operations. Not natural full-match or physical-phone validation."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"passed":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func tap(p):
 var e=InputEventScreenTouch.new();e.position=p;e.index=20;e.pressed=true;root.push_input(e,false);await process_frame
 e=InputEventScreenTouch.new();e.position=p;e.index=20;e.pressed=false;root.push_input(e,false);await settle()
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await settle()
 var row={"name":name,"tick":g.tick_count,"selected":g.selected.duplicate(),"title":g.selection_title.text,"summary":g.selection_summary.text,"summary_visible":g.selection_summary.is_visible_in_tree(),"zoom":g.camera_zoom,"camera":str(g.camera_focus),"metadata_only":metadata_only,"bank":g.economy.bank_milli(0),"siege":g.entities.filter(func(u):return u.team==0 and u.kind=="siege").map(func(u):return {"id":u.id,"hp":u.hp,"position":str(u.pos),"state":u.state})}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(c):return not c.passed).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func tick():g._tick(Rules.TICK);g._update_visuals(Rules.TICK)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/siege-service-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(640,360);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path);report.game_sha256=FileAccess.get_sha256("res://scripts/game.gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="fortress";root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 var cars=[]
 for u in g.entities:
  if u.team==0 and u.kind=="siege":cars.append(u)
 var foe=g._first(1,"archer");report.initial_count=g.entities.size()
 if not check("two original scenario siege and enemy archer",cars.size()==2 and not foe.is_empty()):finish();return
 for i in 2:g._submit("order",{"ids":[cars[i].id],"target":-1,"position":Vector3(-6-i*3,0,8)})
 g._submit("order",{"ids":[foe.id],"target":-1,"position":Vector3(-3,0,8)},1)
 for i in 600:tick()
 report.approach=cars.map(func(u):return {"id":u.id,"pos":str(u.pos),"hp":u.hp})
 g._submit("stop",{"ids":cars.map(func(u):return u.id)});tick()
 for target in cars:
  g._submit("order",{"ids":[foe.id],"target":target.id,"position":target.pos},1)
  for i in 350:
   tick()
   if target.hp<target.max_hp:break
 if not check("ordinary enemy attacks damaged both original siege",cars.all(func(u):return u.alive and u.hp<u.max_hp)):finish();return
 g._select([cars[1].id]);g.camera_focus=(cars[0].pos+cars[1].pos)*.5;g.camera_zoom=20;g._camera_update();g._layout_ui();await settle()
 check("damaged selected car HP visible in native HUD",g.selection_summary.is_visible_in_tree() and g.selection_summary.text.contains("138 / 140"))
 await shot("01-damaged-scenario-siege")
 g._submit("order",{"ids":[foe.id],"target":-1,"position":Vector3(15,0,-5)},1)
 for i in 500:tick()
 g._submit("stop",{"ids":cars.map(func(u):return u.id)});tick();g._publish_faction_views()
 g.compact_menu_button.pressed.emit();await settle();g.shortcut_category_buttons.economy.pressed.emit();await settle()
 g._refresh_idle_dispatch_buttons();var action=g.batch_repair_button;g.shortcut_scroll.ensure_control_visible(action);await settle()
 if not check("real economy menu offers both damaged siege",action.is_visible_in_tree() and not action.disabled and action.get_meta("squad_ids",[]).size()==2 and g.shortcut_scroll.get_global_rect().encloses(action.get_global_rect())):finish();return
 report.service_text=action.text
 report.service_plan=action.get_meta("squad_ids",[])
 await shot("02-economy-batch-service")
 var hp=cars.map(func(u):return u.hp);var wood=g.economy.bank_milli(0).wood
 action.pressed.emit();await settle()
 for i in 1500:
  tick()
  if cars.all(func(u):return u.hp==u.max_hp):break
 var cost=0
 for i in 2:cost+=ceili(float(cars[i].max_hp-hp[i])/5.0)*1000
 check("normal travelling workers repair both with exact wood debit",cars.all(func(u):return u.hp==u.max_hp) and cost>0 and g.economy.bank_milli(0).wood==wood-cost)
 check("enemy remains alive and economy reconciles",foe.alive and g.economy.audit().ok)
 report.workers=g.entities.filter(func(u):return u.team==0 and u.kind=="villager").map(func(u):return {"id":u.id,"pos":str(u.pos),"state":u.state,"target":u.target,"work_epoch":u.get("work_epoch",-1),"path_pending":u.get("path_pending",false),"path":str(u.path)})
 check("original scenario roster retained",g.entities.size()==report.initial_count)
 report.service={"hp_before":hp,"hp_after":cars.map(func(u):return u.hp),"wood_before":wood,"wood_after":g.economy.bank_milli(0).wood,"cost":cost,"enemy_alive":foe.alive,"enemy_position":str(foe.pos)}
 g.compact_menu.hide();g.compact_menu_dismiss.hide();g._select([cars[1].id]);await settle()
 check("repaired selected car HP visible in native HUD",g.selection_summary.is_visible_in_tree() and g.selection_summary.text.contains("140 / 140"))
 await shot("03-paid-fleet-repaired")
 finish()
