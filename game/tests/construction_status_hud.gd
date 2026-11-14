extends SceneTree
## Controlled actual-game HUD transitions. Not natural play or phone acceptance.
var game
var checks=[]
func _initialize(): call_deferred("run")
func check(name: String, passed: bool):
	checks.append({"name":name,"pass":passed})
	if not passed: push_error(name)
func publish():
	game._publish_faction_views(); game._update_hud()
func site_plot(worker: Dictionary) -> Vector3:
	# Existing public placement validation; no gifts or arbitrary paid-site data.
	for z in range(-6,7):
		for x in range(-6,7):
			var point=game._snap_build_position("house",game.MapRoutes.PLAYER_HOME+Vector3(x,0,z))
			if game._placement_reason("house",point,0,worker.id).is_empty(): return point
	return Vector3.INF
func run():
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game.paused=false; game.application_focused=true; game.application_suspended=false
	var worker: Dictionary=game._first(0,"villager")
	var plot=site_plot(worker)
	check("valid opening house plot",plot!=Vector3.INF)
	if plot==Vector3.INF: finish(); return
	var site: Dictionary=game._place_building("house",plot,worker.id,0)
	check("normal house purchase assigns builder",not site.is_empty() and worker.state=="build" and worker.target==site.get("id",-1))
	if site.is_empty(): finish(); return
	game.selected=[site.id]; publish()
	check("selected unfinished site shows assigned not active",game.selection_detail.text.contains("等候施工") and not game.selection_detail.text.contains("建造中"))
	# A controlled published route isolates wording from pathfinding acceptance.
	worker.path=PackedVector3Array([worker.pos+Vector3.ONE]); publish()
	check("portrait HUD shows walking to the selected site",game.compact_ui and game.selection_detail.text.contains("村民移動到工地"))
	worker.path=PackedVector3Array(); worker.path_pending=true; publish()
	check("pending route is reported without claiming arrival",game.selection_detail.text.contains("尋路中"))
	worker.path_pending=false
	game._path_stop(worker,game.BoundedPath.NO_PATH,"controlled_test"); publish()
	check("terminal route has manual resume directions",game.selection_detail.text.contains("尋路停止") and game.selection_detail.text.contains("選村民後直接點工地"))
	# Place the controlled worker on a real legal approach, then perform an actual
	# construction update. The status must follow the resulting successful cue.
	game._path_new_command(worker); game._order(worker,"build",site.id)
	var approach=game._free_adjacent(site,worker.pos,false,0,worker)
	check("site has a legal construction approach",approach!=Vector3.INF)
	if approach==Vector3.INF: finish(); return
	worker.pos=approach; worker.path=PackedVector3Array()
	var before_ticks=site.build_ticks
	game._update_unit(worker,game.Rules.TICK); publish()
	check("successful work tick alone shows active construction",site.build_ticks==before_ticks+1 and game.selection_detail.text.contains("建造中"))
	game.paused=true; game._update_hud()
	check("pause overrides frozen successful work cue",game.selection_detail.text.contains("已暫停") and not game.selection_detail.text.contains("建造中"))
	game.paused=false
	game._submit("stop",{"ids":[worker.id]}); game._update_hud()
	check("pending stop is not displayed as continuing work",game.selection_detail.text.contains("指令等待中") and not game.selection_detail.text.contains("建造中"))
	game._execute(game.commands.pop_front()); publish()
	check("actual stop explains missing builder despite old work cue",game.selection_detail.text.contains("無施工村民") and game.selection_detail.text.contains("派閒置村民續建"))
	game._order(worker,"build",site.id); game._update_unit(worker,game.Rules.TICK); publish()
	check("explicit reassignment resumes actual work feedback",game.selection_detail.text.contains("建造中"))
	game._order_move(worker,worker.pos+Vector3(3,0,0)); publish()
	check("actual move reassignment leaves site visibly without builder",game.selection_detail.text.contains("無施工村民"))
	game._order(worker,"build",site.id)
	var another: Dictionary=game._spawn("house",0,plot+Vector3(6,0,0),false)
	game._order(worker,"build",another.id); publish()
	check("builder on another site cannot satisfy selected site",game.selection_detail.text.contains("無施工村民"))
	game._order(worker,"build",site.id); game._kill(worker); publish()
	check("actual builder death requires manual recovery",game.selection_detail.text.contains("無施工村民") and not game.selection_detail.text.contains("抵達後"))
	var replacement: Dictionary=game._first(0,"villager")
	game._order(replacement,"build",site.id); publish()
	check("live replacement clears missing builder warning",game.selection_detail.text.contains("等候施工") and not game.selection_detail.text.contains("無施工村民"))
	var bank=game.economy.bank_milli(0).duplicate(); var rng_state=game.rng.state; var progress=site.progress
	for i in 8: game._update_hud()
	check("HUD refresh cannot build charge or change randomness",site.progress==progress and game.economy.bank_milli(0)==bank and game.rng.state==rng_state)
	# Rotation uses the same status, without requiring portrait-only presentation.
	root.size=Vector2i(844,390); await process_frame; game._layout_ui(); game._update_hud()
	check("landscape retains construction assignment feedback",game.selection_detail.text.contains("等候施工"))
	site.built=true; site.progress=1.0; publish()
	check("completion removes unfinished-site recovery directions",not game.selection_detail.text.contains("施工") and not game.selection_detail.text.contains("工地"))
	await telemetry_contract(site)
	game._test_reset(); game._update_hud()
	check("restart clears construction recovery directions",not game.selection_detail.text.contains("工地"))
	finish()
func telemetry_contract(site: Dictionary):
	# The Web observer is gated even when called directly. Never execute JS here.
	game.qa_mode=false
	check("QA HUD is absent without opt in",game._qa_hud_snapshot().is_empty())
	game._web_snapshot([])
	game.qa_mode=true
	await process_frame
	game._layout_ui(); game._update_hud()
	await process_frame
	var before=game._snapshot().duplicate(true)
	var before_commands=game.commands.duplicate(true)
	var rng_state=game.rng.state
	var hud=game._qa_hud_snapshot()
	var size=root.get_visible_rect().size
	check("QA schema reports logical viewport and visible detail",hud.schema==2 and hud.viewport==[size.x,size.y] and hud.selection_detail==game.selection_detail.text)
	var keys=hud.keys(); keys.sort()
	check("QA exact public schema",keys==["action_scroll","buttons","camera","context_targets","ground_points","own_targets","preview","schema","selected_own","selection_detail","viewport"])
	check("QA visible camera values only",hud.camera.size()==2 and hud.camera.focus==[game.camera_focus.x,game.camera_focus.y,game.camera_focus.z] and hud.camera.zoom==game.camera.size)
	var safe_context=true
	for target in hud.context_targets:
		var record=game.faction_views[0].get_record(target.id)
		var point=Vector2(target.screen[0],target.screen[1])
		safe_context=safe_context and target.size()==5 and record.alive and not record.remembered and (record.team==1 or record.category=="resource") and game._box_point_in_world(point) and game._pick(point)==record.id
	check("QA context targets contain only currently visible tappable records",safe_context)
	var safe_ground=hud.ground_points.size()<=9
	for values in hud.ground_points:
		var point=Vector2(values[0],values[1]); var world=game._world_at(point)
		safe_ground=safe_ground and values.size()==2 and game._box_point_in_world(point) and game.visible_cells[0][game._cell_index(world)]!=0 and game._pick(point)<0
	check("QA ground samples are bounded visible empty screen points",safe_ground)
	check("QA selected site includes completion from public projection",hud.selected_own.size()==1 and hud.selected_own[0].id==site.id and hud.selected_own[0].built and hud.selected_own[0].progress==1.0 and hud.selected_own[0].size()==5)
	var safe_targets=true
	for target in hud.own_targets:
		var record=game.faction_views[0].get_record(target.id)
		var point=Vector2(target.screen[0],target.screen[1])
		safe_targets=safe_targets and record.owned and record.alive and not record.remembered and record.team==0 and (record.kind=="villager" or (record.category=="building" and not record.built)) and target.size()==6 and game._box_point_in_world(point) and game._pick(point,false)==target.id
	check("QA targets are only current own tappable public projections",safe_targets)
	var safe_buttons=true
	for button in hud.buttons:
		var rect=Rect2(button.rect[0],button.rect[1],button.rect[2],button.rect[3])
		safe_buttons=safe_buttons and rect.has_area() and root.get_visible_rect().encloses(rect) and button.size()==4
		if button.in_action_scroll: safe_buttons=safe_buttons and game.action_scroll.get_global_rect().encloses(rect)
	check("QA button rectangles are clipped visible viewport observations",safe_buttons and not hud.buttons.is_empty())
	check("QA preview is absent when no ghost is displayed",hud.preview==null)
	for i in 8: game._qa_hud_snapshot()
	check("QA observation cannot advance or change game state",game._snapshot()==before and game.commands==before_commands and game.rng.state==rng_state)
	# Pure UI fixture for clipping/hidden controls, with no simulation mutation.
	var clip=Control.new(); clip.position=Vector2(5,200); clip.size=Vector2(40,50); clip.clip_contents=true; game.ui.add_child(clip)
	var button=Button.new(); button.text="QA clip"; button.position=Vector2(20,0); button.size=Vector2(90,46); clip.add_child(button)
	var clipped=game._qa_visible_rect(button)
	check("QA clips button to its actual clipping ancestor",clipped.position==Vector2(25,200) and clipped.size==Vector2(20,46))
	button.hide()
	check("QA excludes hidden button",game._qa_visible_rect(button)==Rect2())
	button.show(); button.position.x=50
	check("QA excludes fully clipped button",not game._qa_visible_rect(button).has_area())
	clip.free(); game.qa_mode=false
func finish():
	var failed=checks.filter(func(c): return not c.pass).size()
	var hashes={}
	for path in ["scripts/game.gd","scripts/construction_status.gd","tests/construction_status_hud.gd"]: hashes[path]=FileAccess.get_sha256("res://"+path)
	print(JSON.stringify({"contract":"construction_status_hud","build":game.Rules.BUILD_ID,"passed":checks.size()-failed,"failed":failed,"checks":checks,"source_sha256":hashes,"scope":"Controlled actual game/HUD transitions at portrait and landscape logical sizes; route fixture and approach relocation are synthetic. Not natural play, pixels or physical-phone acceptance."}))
	game.free(); quit(1 if failed else 0)
