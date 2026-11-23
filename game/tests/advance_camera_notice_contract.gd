extends SceneTree
## Focused actual viewport streams on controlled owned army; a separate
## external fixture checks naturally paid post-defense inputs end-to-end.
var game
var checks=[]
var rows={}
var tag=""
const PLAIN="警戒前進已取消。請重選。"
func _initialize():call_deferred("run")
func ck(n,v):
	checks.append({"name":tag+n,"passed":bool(v)})
	if not v:push_error(tag+n)
	return bool(v)
func frames(n=4):
	for i in n:await process_frame
func settle():
	game._process(0);game._update_hud();game._layout_ui();await frames()
func touch(p,down,index=0,canceled=false):
	var e=InputEventScreenTouch.new();e.position=p;e.index=index;e.pressed=down;e.canceled=canceled;root.push_input(e)
func tap(p):
	touch(p,true);await process_frame;touch(p,false);await settle()
func drag(p,index,relative):
	var e=InputEventScreenDrag.new();e.position=p;e.relative=relative;e.index=index;root.push_input(e)
func prestate():
	return [game.commands.duplicate(true),game.command_sequence,game.selected.duplicate(),game.economy.bank_milli(0)]
func world_pair():
	var delta=Vector2(32,0)
	for y in range(125,int(root.size.y*.73),8):
		for x in range(120,int(root.size.x)-128,12):
			var a=Vector2(x,y);var b=a+Vector2(60,0)
			if [a,b,a+delta,b+delta].all(game._box_point_in_world):return [a,b]
	return []
func move_pair(p):
	touch(p[0],true,0);await process_frame
	touch(p[1],true,1);await process_frame
	for i in 8:
		var offset=Vector2(4*(i+1),0)
		drag(p[0]+offset,0,Vector2(4,0));drag(p[1]+offset,1,Vector2(4,0));await process_frame
func physical_ground():
	for y in range(126,int(root.size.y*.73),9):
		for x in range(40,root.size.x-40,11):
			var p=Vector2(x,y)
			var w=game._world_at(p);var c=game._cell(w)
			if game._box_point_in_world(p) and game._pick(p,true)<0 and game.work_memory[0].grid.region.has_point(c) and not game.work_memory[0].grid.is_point_solid(c) and game.visible_cells[0][game._cell_index(w)]>0:return p
	return Vector2.INF
func arm():
	var b=game.actions.get_node_or_null("PrimaryTacticalAdvance")
	if not is_instance_valid(b) or not game.action_scroll.get_global_rect().encloses(b.get_global_rect()):return false
	await tap(b.get_global_rect().get_center())
	return game.touch_command and game.unit_command_kind=="advance" and game.toast_label.is_visible_in_tree()
func test_base(size):
	root.size=size;tag=str(size)+" ";await frames()
	game=load("res://main.tscn").instantiate();game.skirmish_mode="practice";root.add_child(game)
	game.set_process(false);game.ai_enabled=false;game.camera_zoom=22 if size.y<560 else 30
	var base=game.MapRoutes.home(0)
	var s=game._spawn("spearman",0,base+Vector3(2,0,5))
	var a=game._spawn("archer",0,base+Vector3(4,0,5))
	game._navigation_rebuild();game._update_vision();game._publish_faction_views();game._select([s.id,a.id]);await settle()
	var evidence=prestate()
	if not ck("actual Advance tap arms the previous visible instruction without an order",await arm() and prestate()==evidence):game.free();return
	var p=world_pair()
	if not ck("regular two-finger camera points start and end in world",p.size()==2):game.free();return
	var old=game.toast_label.text;var panel=game.tutorial_panel.get_global_rect();var focus=game.camera_focus;var zoom=game.camera_zoom
	await move_pair(p)
	ck("pair still pans with original toast and unchanged HUD geometry/authority until lifting",game.camera_focus!=focus and game.camera_zoom==zoom and game.toast_label.text==old and game.tutorial_panel.get_global_rect()==panel and prestate()==evidence)
	touch(p[0]+Vector2(32,0),false,0);await process_frame
	drag(p[1]+Vector2(37,0),1,Vector2(5,0));await process_frame
	ck("partial lift and last held drag still quarantined without notice or order",game.toast_label.text==old and prestate()==evidence and game.all_touch_ids.size()==1)
	var began=Time.get_ticks_usec()
	touch(p[1]+Vector2(37,0),false,1)
	rows[str(size)]={"exact_same_dispatch":game.toast_label.text==PLAIN,"max_visible_width":game.toast_label.size.x,"dispatch_usec":Time.get_ticks_usec()-began}
	await settle()
	var f=game.toast_label.get_theme_font("font")
	var line=f.get_string_size(PLAIN,HORIZONTAL_ALIGNMENT_LEFT,-1,game.toast_label.get_theme_font_size("font_size")).x
	ck("exact final lift gives visible truthful readable cancellation, no old touch, no new HUD boundary",rows[str(size)].exact_same_dispatch and not game.touch_command and game.toast_label.is_visible_in_tree() and game.toast_label.size.x>=line and game.tutorial_panel.get_global_rect()==panel and prestate()==evidence and game.all_touch_ids.is_empty())
	var ground=physical_ground()
	if not ck("one actual fresh destination remains usable",ground.is_finite()):game.free();return
	await tap(ground)
	if not ck("ordinary tap after disclosed cancellation retains established Move behavior, no stale Advance",game.commands.size()==1 and game.commands[0].type=="order" and game.commands[0].target==-1):game.free();return
	var next=prestate()
	if not ck("one real tap rearms existing Advance and replaces old cancel copy",await arm() and game.toast_label.text==old and prestate()==next):game.free();return
	await tap(ground)
	ck("fresh destination now submits advance once, no cancellation notice on legitimate target",game.commands.size()==2 and game.commands[1].type=="advance" and game.commands[1].position.is_equal_approx(game.commands[0].position) and game.toast_label.text!=PLAIN)
	game.commands.clear() # Case isolation only; no gameplay is executed between probes.
	if not ck("same button can arm independent newer-feedback protection case",await arm()):game.free();return
	p=world_pair();await move_pair(p)
	game._message("資源已送達。",5) # Controlled presentation witness for a newer gameplay notice.
	touch(p[0]+Vector2(32,0),false,0);await process_frame
	touch(p[1]+Vector2(32,0),false,1);await settle()
	ck("newer unrelated feedback survives both lifts unchanged",game.toast_label.text=="資源已送達。" and game.toast_label.is_visible_in_tree() and game.commands.is_empty())
	for formation in ["line","spread"]:
		game._start_formation_command(formation);await settle() # Controlled arming; gestures fully routed.
		var original=game.toast_label.text
		p=world_pair();await move_pair(p)
		ck("formation "+formation+" keeps old guidance until fingers lift",game.toast_label.text==original and game.commands.is_empty())
		touch(p[0]+Vector2(32,0),false,0);await process_frame
		touch(p[1]+Vector2(32,0),false,1);await settle()
		var expected=("橫列前進" if formation=="line" else "分散前進")+"已取消。請重選。"
		ck("formation "+formation+" gives its own accurate cancel and does not issue orders",not game.touch_command and game.toast_label.text==expected and game.commands.is_empty())
	await arm();p=world_pair()
	old=game.toast_label.text;await move_pair(p)
	touch(p[0]+Vector2(32,0),false,0,true);await process_frame
	touch(p[1]+Vector2(32,0),false,1);await settle()
	ck("OS canceled pointer follows existing path, no camera-cancel message",game.toast_label.text==old and not game.touch_command and game.commands.is_empty())
	await arm();p=world_pair()
	old=game.toast_label.text;var unshifted=game.camera_focus
	touch(p[0],true,0);await process_frame
	var hud=game.pause_button.get_global_rect().get_center()
	touch(hud,true,1);await process_frame
	touch(hud,false,1);await process_frame
	touch(p[0],false,0);await settle()
	ck("mixed GUI/world pair is not mistaken for a camera cancellation or order",game.toast_label.text==old and game.commands.is_empty() and not game.paused and game.camera_focus==unshifted)
	game.free();await frames()
func run():
	for size in [Vector2i(568,320),Vector2i(390,844)]:await test_base(size)
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"advance_camera_notice_contract","checks":checks,"failed":failed,"measurements":rows,"scope":"Actual viewport touch with controlled owned units and notification probe; natural paid defense authoritatively covered separately; not physical device."}))
	quit(1 if failed else 0)
