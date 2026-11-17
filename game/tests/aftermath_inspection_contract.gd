extends SceneTree
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():await process_frame;await process_frame
func mouse(pos,button,down):
 var e=InputEventMouseButton.new();e.position=pos;e.button_index=button;e.pressed=down;root.push_input(e);await process_frame
func touch(pos,id,down,cancel=false):
 var e=InputEventScreenTouch.new();e.position=pos;e.index=id;e.pressed=down;e.canceled=cancel;root.push_input(e);await process_frame
func drag(pos,id,relative):
 var e=InputEventScreenDrag.new();e.position=pos;e.index=id;e.relative=relative;root.push_input(e);await process_frame
func key(code,down,ctrl=false):
 var e=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=down;e.ctrl_pressed=ctrl;Input.parse_input_event(e);await process_frame
func run():
 root.size=Vector2i(960,640)
 var shell=load("res://main_menu.tscn").instantiate();shell.auto_checkpoint_path="/tmp/v91-auto-"+str(Time.get_ticks_usec());root.add_child(shell);await settle()
 shell._choose_battle("standard");shell.selected_difficulty="easy";shell.selected_layout="woodland";shell._start_match();await settle()
 var g=shell.match_node
 if not is_instance_valid(g) or not is_instance_valid(g.camera):push_error("incomplete game initialization");quit(2);return
 shell.auto_checkpoint_enabled=true
 g.set_process(false);g.ai_enabled=false;g.history_path="/tmp/v91-history-"+str(Time.get_ticks_usec())
 g._select([g._first(0,"villager").id]);g._start_build("house");g._submit("surrender",{},0);g._tick(g.Rules.TICK)
 check("ordinary settled surrender produces frozen report",g.game_over and g.outcome=="defeat" and not g.last_match_report.is_empty())
 var history_hash=FileAccess.get_sha256(g.history_path);var report=g.last_match_report.duplicate(true);var tick=g.tick_count;var bank=g.economy.bank_milli(0).duplicate(true);var commands=g.commands.duplicate(true);var selected=g.selected.duplicate();var groups=g.groups.duplicate(true)
 var visible=g.visible_cells[0].duplicate();var explored=g.explored_cells[0].duplicate();var observations=g.faction_views[0].records().duplicate(true)
 g._show_match_report_page("units");g.end_actions.get_node("InspectBattlefieldButton").pressed.emit();await settle()
 check("inspection hides report and command HUD not simulation guard",g.aftermath_view and not g.end_panel.visible and g.aftermath_bar.visible and not g.hud_top.visible and not g.hud_bottom.visible and g.game_over and g.minimap.visible)
 check("inspection clears unpaid ghost without authority changes",g.build_mode.is_empty() and not is_instance_valid(g.ghost) and g.commands==commands and g.economy.bank_milli(0)==bank)
 var p=Vector2(500,280);var before=g.camera_focus
 await mouse(p,MOUSE_BUTTON_MIDDLE,true)
 var motion=InputEventMouseMotion.new();motion.position=p+Vector2(50,0);motion.relative=Vector2(50,0);motion.button_mask=MOUSE_BUTTON_MASK_MIDDLE;root.push_input(motion);await process_frame
 await mouse(p+Vector2(50,0),MOUSE_BUTTON_MIDDLE,false)
 check("middle mouse pans inspection",g.camera_focus!=before)
 var zoom=g.camera_zoom;await mouse(p,MOUSE_BUTTON_WHEEL_UP,true)
 check("wheel zoom works in inspection",g.camera_zoom<zoom)
 before=g.camera_focus;zoom=g.camera_zoom
 await touch(p,10,true);await touch(p+Vector2(80,0),11,true)
 # Small staggered pan must move the camera without accidental span zoom.
 await drag(p+Vector2(4,0),10,Vector2(4,0))
 await drag(p+Vector2(85,0),11,Vector2(5,0))
 var pan_without_zoom=g.camera_focus!=before and is_equal_approx(g.camera_zoom,zoom) and not g.touch_pinch_active
 # Crossing the intent gate rebases; only subsequent deliberate pinch zooms.
 await drag(p+Vector2(110,0),11,Vector2(25,0))
 var activation_without_jump=g.touch_pinch_active and is_equal_approx(g.camera_zoom,zoom)
 await drag(p+Vector2(130,0),11,Vector2(20,0))
 var deliberate_zoom=g.camera_zoom<zoom and is_equal_approx(g.camera_zoom,zoom*106.0/126.0)
 await touch(p+Vector2(4,0),10,false);await touch(p+Vector2(130,0),11,false)
 check("two finger pan and pinch work",pan_without_zoom and activation_without_jump and deliberate_zoom and g.camera_focus!=before and g.commands==commands and g.selected==selected)
 before=g.camera_focus
 var mp=g.minimap.get_global_rect().get_center()+Vector2(24,8)
 await mouse(mp,MOUSE_BUTTON_LEFT,true);await mouse(mp,MOUSE_BUTTON_LEFT,false)
 check("minimap works after ended match",g.camera_focus!=before)
 await mouse(p,MOUSE_BUTTON_MIDDLE,true);await mouse(p,MOUSE_BUTTON_MIDDLE,false)
 before=g.camera_focus;await key(KEY_D,true);g._process(0.1);await key(KEY_D,false)
 check("fresh keyboard pan works after minimap and world focus",g.camera_focus!=before)
 await touch(p,20,true);await touch(p+Vector2(80,0),21,true);await mouse(p,MOUSE_BUTTON_MIDDLE,true)
 g._notification(NOTIFICATION_APPLICATION_FOCUS_OUT);g._notification(NOTIFICATION_APPLICATION_PAUSED)
 before=g.camera_focus;g._notification(NOTIFICATION_APPLICATION_FOCUS_IN);g._notification(NOTIFICATION_APPLICATION_RESUMED)
 await drag(p+Vector2(40,0),20,Vector2(40,0));await touch(p,20,false);await touch(p+Vector2(80,0),21,false);await mouse(p,MOUSE_BUTTON_MIDDLE,false)
 check("focus suspend cancels held camera streams without autosave",g.camera_focus==before and g.touch_points.is_empty() and not g.middle_drag and g.game_over and shell.auto_checkpoint_writes==0)

 await mouse(p,MOUSE_BUTTON_LEFT,true);await mouse(p,MOUSE_BUTTON_LEFT,false);await mouse(p,MOUSE_BUTTON_RIGHT,true);await mouse(p,MOUSE_BUTTON_RIGHT,false)
 await key(KEY_SPACE,true);await key(KEY_SPACE,false)
 check("home shortcut only moves camera",g.camera_focus==g.MapRoutes.home(0) and g.selected==selected)
 await key(KEY_1,true,true);await key(KEY_1,false,true);await key(KEY_X,true);await key(KEY_X,false)
 check("world selection group assignment and orders blocked",g.selected==selected and g.groups==groups and g.commands==commands)
 g._tick(g.Rules.TICK);g._process(0.1);g.set_process(false)
 check("inspection does not advance authority or reveal fog",g.tick_count==tick and g.economy.bank_milli(0)==bank and g.visible_cells[0]==visible and g.explored_cells[0]==explored and g.faction_views[0].records()==observations)
 check("report history and autosave untouched",g.last_match_report==report and FileAccess.get_sha256(g.history_path)==history_hash and shell.auto_checkpoint_writes==0 and not FileAccess.file_exists(shell.auto_checkpoint_path))
 await touch(p,12,true);g._set_aftermath_view(false);before=g.camera_focus;await drag(p+Vector2(70,0),12,Vector2(70,0));await touch(p+Vector2(70,0),12,false)
 check("return cleans held gestures and retains selected report page",not g.aftermath_view and g.end_panel.visible and g.end_report_page=="units" and g.camera_focus==before and g.touch_points.is_empty())
 g._set_aftermath_view(true);await key(KEY_ESCAPE,true);await key(KEY_ESCAPE,false)
 check("escape returns same report without pause or resume",not g.aftermath_view and g.game_over and g.last_match_report==report)
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await settle()
  var fit=true
  for button in g.end_actions.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("four report actions fit "+str(size),fit and g.end_scroll.size.y>=80)
  g._set_aftermath_view(true);await settle()
  var bar_children=true
  for child in g.aftermath_bar.get_child(0).get_children():bar_children=bar_children and g.aftermath_bar.get_global_rect().encloses(child.get_global_rect())
  check("inspection bar and minimap fit "+str(size),bar_children and not g.aftermath_bar.get_global_rect().intersects(g.minimap.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(size)).encloses(g.aftermath_bar.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(size)).encloses(g.minimap.get_global_rect()))
  g._set_aftermath_view(false)
 g.end_actions.get_node("ReplayMatchButton").pressed.emit();await settle()
 var replay=shell.match_node;replay.set_process(false);replay.test_mode=true
 check("replay creates fresh same configuration not inspection",replay!=g and not replay.game_over and not replay.aftermath_view and replay.ai_difficulty=="easy" and replay.layout_id=="woodland" and replay.skirmish_mode=="standard")
 replay.ai_enabled=false;replay._submit("surrender",{},1);replay._tick(replay.Rules.TICK)
 replay._set_aftermath_view(true)
 check("ordinary enemy surrender victory supports inspection",replay.outcome=="victory" and replay.aftermath_view and replay.game_over)
 replay._set_aftermath_view(false);replay._test_reset();replay.set_process(false);replay.ai_enabled=false
 replay._submit("surrender",{},0);replay._submit("surrender",{},1);replay._tick(replay.Rules.TICK);replay._set_aftermath_view(true)
 check("simultaneous surrender draw supports inspection",replay.outcome=="draw" and replay.aftermath_view and replay.game_over)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"aftermath_inspection_contract","checks":checks,"failed":failed,"scope":"Native ordinary surrender, routed camera gestures and frozen authority/history/file invariants. Not natural battle victory, browser or physical phone proof."}))
 quit(1 if failed else 0)
