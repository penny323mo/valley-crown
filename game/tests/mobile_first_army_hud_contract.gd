extends SceneTree
## Fast native HUD contract. Controlled selection/opening only; separate
## external journey covers untouched initial stock and purely routed play.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
var rows={}
func _initialize():call_deferred("run")
func check(label:String,value:bool)->bool:
	checks.append({"name":label,"passed":value})
	if not value:push_error(label)
	return value
func frames():
	for i in 5:await process_frame
func settle():
	game._process(0);game._update_hud();game._layout_ui()
	await frames()
func touch(p:Vector2,down:bool,index=0):
	var e=InputEventScreenTouch.new();e.index=index;e.pressed=down;e.position=p
	root.push_input(e);await process_frame
func tap(p:Vector2):
	await touch(p,true);await touch(p,false);await settle()
func pair_drag() -> void:
	var starts=[Vector2(250,156),Vector2(340,156)]
	await touch(starts[0],true,0);await touch(starts[1],true,1)
	for i in 6:
		for j in 2:
			var e=InputEventScreenDrag.new();e.index=j;e.relative=Vector2(0,4)
			e.position=starts[j]+Vector2(0,4*(i+1));root.push_input(e)
		await process_frame
	await touch(starts[0]+Vector2(0,24),false,0);await touch(starts[1]+Vector2(0,24),false,1)
	await settle()
func fits(b:Button,owner:Control)->bool:
	if not is_instance_valid(b) or not b.is_visible_in_tree():return false
	var r=b.get_global_rect()
	return r.size.x>=44 and r.size.y>=44 and owner.get_global_rect().encloses(r) and root.get_visible_rect().encloses(r)
func longest_world_band()->int:
	var largest=0;var run_length=0
	for y in root.size.y:
		if game._box_point_in_world(Vector2(root.size.x*0.5,y)):
			run_length+=1;largest=maxi(largest,run_length)
		else:run_length=0
	return largest
func snapshot():
	return [game.command_sequence,game.economy.bank_milli(0).duplicate(true),game.camera.global_transform,game.selected.duplicate()]
func printed_width(control:Label)->float:
	return control.get_theme_font("font").get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,control.get_theme_font_size("font_size")).x
func find_cancel()->Button:
	for b in game.actions.get_children():
		if b is Button and b.text=="取消建造":return b
	return null
func start(size:Vector2i):
	root.size=size;await frames()
	game=load("res://main.tscn").instantiate();game.skirmish_mode="practice"
	root.add_child(game);game.set_process(false);game.ai_enabled=false
	# Same landscape zoom that the ordinary shell applies on fresh start.
	if size.y<560:game.camera_zoom=22
	await settle()
func finish_case():
	if is_instance_valid(game):game.free()
	await frames()
func test_price():
	await start(Vector2i(568,320))
	var worker=game._first(0,"villager")
	game._select([worker.id]);game._start_build("range");await settle()
	var band=longest_world_band();var cost=game.queue_label
	rows.preview_world_rows=band
	rows.price_width=cost.size.x
	var price_ok=check("568 Range price text gets its real one-line width",cost.text=="木 120" and cost.size.x>=printed_width(cost) and cost.size.y<=26)
	check("568 Range keeps at least 64 consecutive central world rows",band>=64)
	var cancel=find_cancel()
	var targets_ok=check("both Range Confirm and Cancel are separate 44px targets",fits(game.build_confirm,game.action_scroll) and fits(cancel,game.action_scroll))
	if not price_ok or not targets_ok:await finish_case();return
	var state=snapshot()
	var center=game.camera.unproject_position(game._first(0,"town_center").pos)
	if check("occupied keep ground is routable in Range preview",game._box_point_in_world(center)):
		await tap(center)
		var reason=game._build_preview_reason()
		check("actual invalid tap retains honest reason and cannot confirm",not reason.is_empty() and game.build_preview_held and game.build_confirm.disabled and game.selection_summary.text.contains("不可建造") and snapshot()==state)
		var detail=game.context_detail_button
		if check("build Details remains reachable",fits(detail,game.action_scroll)):
			await tap(detail.get_global_rect().get_center())
			check("blocking reason accessible in actual Details",game.context_details.visible and game.selection_detail.text.contains(reason) and snapshot()==state)
			var detail_rect=game.context_details.get_global_rect()
			await tap(detail_rect.get_center())
			check("modal body does not replace preview or issue world command",game.context_details.visible and game.build_preview_held and snapshot()==state)
			await tap(game.find_child("CloseBattleDetails",true,false).get_global_rect().get_center())
		await tap(game.build_confirm.get_global_rect().get_center())
		check("disabled Confirm is still a UI-owned no-op",game.build_mode=="range" and snapshot()==state)
	await tap(cancel.get_global_rect().get_center())
	check("Cancel keeps builder and balance and never orders",game.build_mode.is_empty() and snapshot()==state)
	game._start_build("range");await settle()
	var pan_state=snapshot();var zoom=game.camera_zoom
	await pair_drag()
	check("actual two-finger drag can pan within preview without placement, mode loss or payment",game.camera.global_transform!=pan_state[2] and game.camera_zoom==zoom and game.build_mode=="range" and not game.build_preview_held and game.commands.is_empty() and game.economy.bank_milli(0)==pan_state[1] and game.selected==pan_state[3])
	game._cancel_mode()
	game._start_build("farm");await settle()
	check("ordinary Farm keeps full 60 wood price with working controls",game.queue_label.text=="木 60" and game.queue_label.size.x>=printed_width(game.queue_label) and fits(game.build_confirm,game.action_scroll) and fits(find_cancel(),game.action_scroll))
	game._cancel_mode()
	var workers=game.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager")
	game._select([workers[0].id,workers[1].id]);game._start_build("wall");game._cycle_wall_line_count();await settle()
	check("two-segment Wall keeps exact total and sufficient battlefield",game.wall_line_count==2 and game.queue_label.text=="2段 · 木60" and game.queue_label.size.x>=printed_width(game.queue_label) and longest_world_band()>=64)
	var before_wall=snapshot()
	game._rotate_wall_line();await settle()
	check("wall direction keeps exact displayed total, preview and economy",game.wall_line_vertical and game.queue_label.text=="2段 · 木60" and not game.build_preview_held and snapshot()==before_wall)
	game._cancel_mode()
	# Controlled independent low-bank opening (presentation only). The
	# separate ordinary journeys have no test-resource mutations.
	game._test_reset([{"food":150,"wood":50,"stone":100,"iron":0},{"food":150,"wood":200,"stone":100,"iron":0}])
	game.set_process(false)
	var crew=game.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager")
	game._select([crew[0].id,crew[1].id,crew[2].id]);game._start_build("wall")
	game._cycle_wall_line_count();game._cycle_wall_line_count();await settle()
	check("three Wall segments still show full 90 wood with only 50 in stock",game.wall_line_count==3 and game.queue_label.text=="3段 · 木90" and game.queue_label.size.x>=printed_width(game.queue_label) and game.build_confirm.disabled and longest_world_band()>=64)
	var poor_before=snapshot()
	if check("insufficient wall Details remains a true 44px control",fits(game.context_detail_button,game.action_scroll)):
		await tap(game.context_detail_button.get_global_rect().get_center())
		rows.wall_detail={"actual":game.selection_detail.text,"owner":game.context_detail_kind,"visible":game.context_details.visible,"same":snapshot()==poor_before}
		check("wall row Details exposes three, full cost, one worker each and 40 wood shortage",game.context_details.visible and game.selection_detail.text.contains("3 段木柵") and game.selection_detail.text.contains("木材 90") and game.selection_detail.text.contains("每段一人") and game.selection_detail.text.contains("缺木40") and snapshot()==poor_before)
	await finish_case()

func test_completion():
	await start(Vector2i(568,320))
	var w=game._first(0,"villager")
	game._select([w.id])
	var site_pos=Vector3.INF
	# Choose a normally legal currently observed point whose completed upper
	# projection really falls underneath the previous full-width notice.
	var guard=Rect2(328,66,216,50)
	for x in range(-30,-12):
		for z in range(12,34):
			var p=game._snap_build_position("barracks",Vector3(x,0,z))
			if guard.has_point(game.camera.unproject_position(p+Vector3.UP)) and game._placement_reason("barracks",p,0,w.id).is_empty():site_pos=p;break
		if site_pos.is_finite():break
	if not check("qualified short landscape paid Barracks overlap fixture exists",site_pos.is_finite()):await finish_case();return
	var bank=game.economy.bank_milli(0).duplicate(true)
	var producer=game._place_building("barracks",site_pos,w.id,0)
	if not check("ordinary paid construction receipt debits actual cost",not producer.is_empty() and game.economy.bank_milli(0).wood==bank.wood-120000):await finish_case();return
	var work_ticks=roundi(Rules.BUILD_TIME.barracks/Rules.TICK)
	for i in 1300:
		if producer.build_ticks==work_ticks-1:break
		game._process(Rules.TICK)
	await settle()
	if not check("real production fixture reaches actual last construction tick",producer.build_ticks==work_ticks-1 and not producer.built and game.tutorial_label.visible):await finish_case();return
	var original_details=game.guidance_detail_button.get_global_rect().get_center()
	await touch(original_details,true)
	game._process(Rules.TICK);await settle()
	var expected=Vector2(568,320);var r=game.tutorial_panel.get_global_rect()
	var anchor=game.camera.unproject_position(producer.pos+Vector3.UP)
	rows.toast={"panel":[r.position.x,r.position.y,r.size.x,r.size.y],"target":[anchor.x,anchor.y]}
	var center_ok=check("a real paid completion moves its own status away from the occluded anchor",producer.built and r.position.x==6 and r.size.x<expected.x*0.5 and not r.has_point(anchor) and game._box_point_in_world(anchor))
	var before_release=snapshot()
	await touch(original_details,false);await settle()
	check("previous held Details release cannot activate the clear map, selection, order or payment",not game.context_details.visible and snapshot()==before_release and producer.queue.is_empty())
	if center_ok:
		var body=Vector2(r.position.x+16,r.get_center().y)
		await tap(body)
		check("shortened completion card remains an intentional world shield",snapshot()==before_release and not game.context_details.visible)
		var detail=game.guidance_detail_button
		if check("short notice is readable and real Details remains 44px or greater",game.toast_label.size.x>=printed_width(game.toast_label) and fits(detail,game.tutorial_panel)):
			await tap(detail.get_global_rect().get_center())
			check("actual Details retains full completion line without ordering",game.context_details.visible and game.guidance_detail.text==game.toast_label.text and snapshot()==before_release)
			await tap(game.find_child("CloseBattleDetails",true,false).get_global_rect().get_center())
		await tap(anchor)
		check("same unassisted world tap selects exact paid Barracks without any order",game.selected==[producer.id] and game.command_sequence==before_release[0] and game.economy.bank_milli(0)==before_release[1] and game.camera.global_transform==before_release[2])
	for i in 125:game._process(Rules.TICK)
	await frames()
	check("expiry restores expanded tutorial without calling layout in the fixture",game.toast_time<=0 and game.tutorial_label.visible and game.tutorial_panel.size.x==556 and game.tutorial_skip.visible and game.tutorial_collapse.visible)
	await finish_case()

func run():
	await test_price()
	await test_completion()
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"mobile_first_army_hud_contract","checks":checks,"failed":failed,"measurements":rows,"scope":"Controlled native 568×320 actual HUD and viewport input, real paid and completed Barracks, no physical-phone/render acceptance."}))
	quit(1 if failed else 0)
