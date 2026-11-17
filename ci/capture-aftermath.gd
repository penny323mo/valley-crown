extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var menu
var g
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Actual ordinary player surrender (defeat), not natural victory or full-battle replay. Real product inspection and routed camera/minimap input. No health, damage, economy, fog or result assignment. No physical phone/browser acceptance."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"pass":bool(b)});return bool(b)
func settle():await process_frame;await process_frame
func press(id):
 var b=menu.find_child(id,true,false)
 if not check("button "+id,b is Button and b.is_visible_in_tree()):return false
 b.pressed.emit();await settle();return true
func mouse(p,b,down):
 var e=InputEventMouseButton.new();e.position=p;e.button_index=b;e.pressed=down;root.push_input(e);await process_frame
func shot(name):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await settle()
 var row={"name":name,"tick":g.tick_count,"outcome":g.outcome,"game_over":g.game_over,"inspection":g.aftermath_view,"camera":str(g.camera_focus),"bank":g.economy.bank_milli(0),"report_page":g.end_report_page,"bar_visible":g.aftermath_bar.is_visible_in_tree(),"minimap_visible":g.minimap.is_visible_in_tree(),"report_visible":g.end_panel.is_visible_in_tree(),"metadata_only":metadata_only}
 if g.aftermath_view:
  var view=Rect2(Vector2.ZERO,Vector2(root.size))
  check(name+" bar and minimap fit",view.encloses(g.aftermath_bar.get_global_rect()) and view.encloses(g.minimap.get_global_rect()) and not g.aftermath_bar.get_global_rect().intersects(g.minimap.get_global_rect()))
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" png",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func finish():
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"checks":checks.size(),"failed":report.failed}));quit(1 if report.failed else 0)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v91-aftermath-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["main_menu","game","minimap","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 root.size=Vector2i(960,540);menu=load("res://main_menu.tscn").instantiate();menu.auto_checkpoint_path=out+"/auto.bin";root.add_child(menu);await settle()
 for id in ["StartMatchButton","BattleGroup0","ChooseBattle_standard","LaunchMatchButton"]:
  if not await press(id):finish();return
 g=menu.match_node;g.set_process(false);g.history_path=out+"/history.json"
 for i in 100:g._tick(Rules.TICK)
 g.compact_menu_button.pressed.emit();await settle();g.shortcut_category_buttons.settings.pressed.emit();await settle()
 var surrender=null
 for b in g.compact_menu.find_children("*","Button",true,false):
  if b.text=="投降":surrender=b;break
 if not check("product surrender available",surrender!=null and surrender.is_visible_in_tree()):finish();return
 surrender.pressed.emit();await settle()
 var dialog=null
 for n in g.find_children("*","ConfirmationDialog",true,false):
  if n.visible:dialog=n;break
 if not check("product surrender confirmation",dialog!=null):finish();return
 dialog.confirmed.emit();dialog.hide();g._tick(Rules.TICK);await settle()
 check("ordinary surrender settled",g.game_over and g.outcome=="defeat")
 var original=g.last_match_report.duplicate(true);var page=g.end_report_page;var tick=g.tick_count;var bank=g.economy.bank_milli(0).duplicate(true);var visible=g.visible_cells[0].duplicate();var explored=g.explored_cells[0].duplicate();var selected=g.selected.duplicate();var commands=g.commands.duplicate(true)
 await shot("01-ordinary-surrender-report")
 if not await press("InspectBattlefieldButton"):finish();return
 await shot("02-read-only-battlefield")
 var before=g.camera_focus;var p=Vector2(500,280)
 await mouse(p,MOUSE_BUTTON_MIDDLE,true)
 var motion=InputEventMouseMotion.new();motion.position=p+Vector2(70,0);motion.relative=Vector2(70,0);motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE;root.push_input(motion);await process_frame
 await mouse(p+Vector2(70,0),MOUSE_BUTTON_MIDDLE,false)
 check("routed middle pan changed camera",g.camera_focus!=before)
 before=g.camera_focus
 var mp=g.minimap.get_global_rect().get_center()+Vector2(-24,24)
 await mouse(mp,MOUSE_BUTTON_LEFT,true);await mouse(mp,MOUSE_BUTTON_LEFT,false)
 check("routed minimap changed camera",g.camera_focus!=before)
 await shot("03-minimap-inspected")
 if not await press("ReturnMatchReportButton"):finish();return
 await shot("04-same-report-returned")
 check("same report and selected tab",g.last_match_report==original and g.end_report_page==page and g.end_panel.visible)
 check("frozen terminal authority",g.tick_count==tick and g.economy.bank_milli(0)==bank and g.visible_cells[0]==visible and g.explored_cells[0]==explored and g.selected==selected and g.commands==commands and g.game_over)
 finish()
