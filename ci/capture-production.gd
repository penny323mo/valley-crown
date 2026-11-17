extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Controlled initial barracks, five houses and exit-blocking scouts on ordinary practice seed. Training uses original available funds, full ordinary train ticks, then actual routed UI locator and clear-exit orders. No training-clock, HP/resource/fog edits or blocker teleport after action. AI scheduling disabled; not natural recruitment/building progression or physical phone acceptance."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"passed":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func tick():g._tick(Rules.TICK);g._update_visuals(Rules.TICK)
func tap(p):
 var e=InputEventScreenTouch.new();e.position=p;e.index=55;e.pressed=true;root.push_input(e,false);await process_frame
 e=InputEventScreenTouch.new();e.position=p;e.index=55;e.pressed=false;root.push_input(e,false);await settle()
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await settle()
 var row={"name":name,"tick":g.tick_count,"selected":g.selected.duplicate(),"camera":str(g.camera_focus),"queue_text":g.queue_label.text,"summary":g.selection_summary.text,"overview":g.production_buttons.barracks.text,"bank":g.economy.bank_milli(0),"trained":g.trained_total[0],"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(c):return not c.passed).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/production-wait-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(390,844);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for file in ["game","production_overview","building_attention"]:report[file+"_sha256"]=FileAccess.get_sha256("res://scripts/"+file+".gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.ai_enabled=false;await settle()
 var home=g._first(0,"town_center");var worker=g._first(0,"villager");var place=Vector3.INF;var distance=INF
 for y in Rules.MAP_SIZE:
  for x in Rules.MAP_SIZE:
   var point=g._point(Vector2i(x,y));var d=point.distance_squared_to(home.pos)
   if d<distance and g._placement_reason("barracks",point,0,worker.id).is_empty():place=point;distance=d
 if not check("legal producer fixture location",place!=Vector3.INF):finish();return
 var producer=g._spawn("barracks",0,place)
 for i in 5:g._spawn("house",0,Vector3(15,0,8+i*3))
 g._navigation_rebuild();var blockers=[]
 for cell in g._production_exit_cells(producer,"spearman"):
  if not g.navigation.is_point_solid(cell):blockers.append(g._spawn("scout",0,g._point(cell)))
 g._update_vision();report.fixture={"producer":str(place),"houses":5,"blockers":blockers.map(func(u):return {"id":u.id,"position":str(u.pos)})}
 if not check("ordinary paid training accepted",g._enqueue_train(producer.id,"spearman",0)):finish();return
 var paid=g.economy.bank_milli(0).duplicate(true);var initial=g._count(0,"spearman")
 for i in Rules.TRAIN_TICKS.spearman+2:tick()
 if not check("actual full training ready but occupied exit blocks birth",producer.queue.size()==1 and producer.queue[0].remaining_ticks==0 and g._count(0,"spearman")==initial):finish();return
 var receipt=producer.queue[0].receipt_id
 g._select([worker.id]);g.camera_focus=producer.pos;g.camera_zoom=20;g._camera_update();g._layout_ui();await settle()
 g.compact_menu_button.pressed.emit();await settle();g.shortcut_category_buttons.production.pressed.emit();await settle();g._refresh_production_buttons()
 var overview=g.production_buttons.barracks;g.shortcut_scroll.ensure_control_visible(overview);await settle()
 check("visible production row distinguishes ready and producing",g.shortcut_scroll.get_global_rect().encloses(overview.get_global_rect()) and overview.text.contains("待出兵1") and overview.text.contains("生產0"))
 await shot("01-production-ready-not-producing")
 var locator=g.building_attention_buttons.waiting;g.shortcut_scroll.ensure_control_visible(locator);await settle()
 if not check("waiting locator visible and binds stalled producer",g.shortcut_scroll.get_global_rect().encloses(locator.get_global_rect()) and locator.get_meta("squad_ids",[])==[producer.id] and not locator.disabled):finish();return
 await tap(locator.get_global_rect().get_center())
 check("routed locator selects and focuses actual stalled producer",g.selected==[producer.id] and g.camera_focus==producer.pos and not g.compact_menu.visible)
 var clear=g.clear_exit_button;g.action_scroll.ensure_control_visible(clear);await settle()
 if not check("actual blocked exit reason and clearing action visible",g.queue_label.text.contains("出口受阻") and clear!=null and not clear.disabled and g.action_scroll.get_global_rect().encloses(clear.get_global_rect())):finish();return
 await shot("02-blocked-producer-clear-exit")
 var starts={}
 for u in blockers:starts[u.id]=u.pos
 await tap(clear.get_global_rect().get_center())
 check("clear request uses ordinary orders preserves paid queue",not g.commands.is_empty() and g.commands.all(func(c):return c.type=="order") and producer.queue[0].receipt_id==receipt and g.economy.bank_milli(0)==paid)
 for i in 600:
  tick()
  if producer.queue.is_empty():break
 check("real blocker movement permits one normal birth",producer.queue.is_empty() and g._count(0,"spearman")==initial+1 and blockers.any(func(u):return u.pos.distance_to(starts[u.id])>.1))
 check("one payment and one birth with conserved economy",g.economy.bank_milli(0)==paid and g.trained_total[0]==1 and g.economy.audit().ok)
 g._update_hud();g._refresh_production_buttons();await settle()
 check("completed queue removes clear action and waiting locator",not is_instance_valid(g.clear_exit_button) and g.building_attention_buttons.waiting.disabled)
 await shot("03-normal-birth-queue-cleared")
 report.final_blockers=blockers.map(func(u):return {"id":u.id,"position":str(u.pos),"moved":u.pos.distance_to(starts[u.id])})
 finish()
