extends SceneTree
# External validation harness. Ordinary economy opening, natural defeat, real end-button keyboard route.
const EXPECTED_BUILD="vc-c7211e1083c8"
const MAX_TICKS=48000
var game
var inputs=[]
var assigned={}
var checkpoints=[]
var invariants=[]
var restarted={}
var reload_events=0
var phase="opening"
func snapshot():
	return {"snapshot":game._snapshot().duplicate(true),"ai_enabled":game.ai_enabled,"records":game.faction_views[0].records().duplicate(true)}
func issue(kind,data,actor,target={}):
	assert(actor.owned and actor.alive and not actor.remembered)
	assert(target.is_empty() or (target.alive and not target.remembered))
	game._submit(kind,data,0)
	inputs.append({"phase":phase,"tick":game.tick_count,"command":game.commands.back().duplicate(true),"actor":actor.duplicate(true),"target":target.duplicate(true)})
func policy():
	var records=game.faction_views[0].records()
	for ent in records.values():
		if not ent.owned: continue
		if ent.kind=="town_center" and game.tick_count==0:
			issue("train",{"building":ent.id,"kind":"villager"},ent)
		if ent.kind!="villager" or assigned.has(ent.id): continue
		var source={}
		for candidate in records.values():
			if candidate.category!="resource" or candidate.remembered or candidate.kind!="berry": continue
			if source.is_empty() or ent.pos.distance_squared_to(candidate.pos)<ent.pos.distance_squared_to(source.pos): source=candidate
		if source.is_empty(): continue
		issue("order",{"ids":[ent.id],"target":source.id,"position":source.pos},ent,source)
		assigned[ent.id]=true
func on_scene_changed():
	reload_events+=1
	game=current_scene
	if game==null: return
	game.set_process(false)
	restarted=snapshot()
	restarted["end_panel_visible"]=game.end_panel.visible
	restarted["scene_file_path"]=game.scene_file_path
	restarted["commands_empty"]=game.commands.is_empty()
	restarted["action_history_empty"]=game.unit_action_cues==[{},{}] and game.pending_visual_deaths.is_empty()
	restarted["corpses_empty"]=game.character_presenter.corpses.is_empty()
func _initialize(): call_deferred("run")
func run():
	var args=OS.get_cmdline_user_args()
	if args.size()!=1: push_error("Expected one absolute output report path."); quit(2); return
	game=load("res://main.tscn").instantiate(); root.add_child(game); current_scene=game; game.set_process(false)
	if game.Rules.BUILD_ID!=EXPECTED_BUILD or not game.ai_enabled or game.test_mode:
		push_error("Wrong identity or non-ordinary startup."); quit(2); return
	var start=Time.get_ticks_msec()
	checkpoints.append(snapshot())
	for i in MAX_TICKS:
		if game.tick_count%20==0: policy()
		game._tick(game.Rules.TICK)
		var snap=game._snapshot()
		if not game.ai_enabled or snap.food<0 or snap.wood<0 or snap.population>game.Rules.POP_LIMIT:
			invariants.append(snap.duplicate(true)); break
		if game.tick_count%1200==0:
			checkpoints.append(snapshot()); print("DEFEAT_PROGRESS ",game.tick_count," ",game.outcome)
		if game.game_over or game.paused: break
	var terminal=snapshot(); var reason=game.end_reason; var audit=game.economy.audit().duplicate(true)
	var natural_defeat=game.game_over and game.outcome=="defeat" and reason in ["keep_destroyed","irrecoverable"]
	var ui={"attempted":false,"route":"focused actual end-panel Button + InputEventKey Enter through root.push_input; no signal emission or direct reload call"}
	var old_ref=weakref(game); var old_id=game.get_instance_id()
	if natural_defeat:
		# Let normal Control layout settle, without advancing simulation.
		for i in 3: await process_frame
		var button=null
		for candidate in game.end_panel.find_children("*","Button",true,false):
			if candidate.text=="再開一局" and candidate.is_visible_in_tree(): button=candidate
		ui["button_found"]=button!=null
		ui["terminal_panel_visible"]=game.end_panel.is_visible_in_tree()
		if button!=null:
			button.grab_focus()
			ui["focus_owned"]=root.gui_get_focus_owner()==button
			ui["button_text"]=button.text
			ui["button_enabled"]=not button.disabled
			if ui.focus_owned and ui.button_enabled:
				scene_changed.connect(on_scene_changed)
				ui["attempted"]=true
				var press=InputEventKey.new(); press.keycode=KEY_ENTER; press.pressed=true
				root.push_input(press,true)
				var release=InputEventKey.new(); release.keycode=KEY_ENTER; release.pressed=false
				root.push_input(release,true)
				for i in 10:
					await process_frame
					if reload_events>0: break
	ui["reload_events"]=reload_events
	ui["old_instance_released"]=old_ref.get_ref()==null
	ui["new_instance"]=current_scene!=null and current_scene.get_instance_id()!=old_id
	var post_restart={}
	if reload_events==1 and not restarted.is_empty():
		# Fresh match receives one current observed worker->berry command, then ordinary ticks.
		phase="restarted"; assigned={}; var before=inputs.size(); policy()
		for i in 40: game._tick(game.Rules.TICK)
		post_restart=snapshot(); post_restart["command_count"]=inputs.size()-before
		post_restart["economy_audit"]=game.economy.audit().duplicate(true)
	var execution={"paid_villager":false,"training_advanced":false,"gather_target_active":false}
	if not post_restart.is_empty():
		execution.paid_villager=post_restart.snapshot.food==restarted.snapshot.food-game.Rules.COSTS.villager.food and post_restart.snapshot.wood==restarted.snapshot.wood
		for record in post_restart.records.values():
			if record.owned and record.kind=="town_center" and record.queue.size()==1:
				var order=record.queue[0]
				execution.training_advanced=order.kind=="villager" and order.started and order.remaining_ticks==game.Rules.TRAIN_TICKS.villager-40
			if record.owned and record.alive and record.kind=="villager" and record.state=="gather" and record.last_seen_tick==40:
				for command in inputs:
					if command.phase=="restarted" and command.command.type=="order" and command.actor.id==record.id and command.target.id==record.target:
						execution.gather_target_active=true
	var restart_ok=reload_events==1 and ui.old_instance_released and ui.new_instance and not restarted.is_empty() and restarted.snapshot.tick==0 and not restarted.snapshot.game_over and not restarted.snapshot.paused and restarted.ai_enabled and restarted.commands_empty and restarted.action_history_empty and restarted.corpses_empty and not restarted.end_panel_visible
	var passed=natural_defeat and restart_ok and execution.paid_villager and execution.training_advanced and execution.gather_target_active and invariants.is_empty() and audit.ok and not post_restart.is_empty() and post_restart.snapshot.tick==40 and post_restart.ai_enabled and post_restart.economy_audit.ok
	var report={"scope":"One accelerated native economy-only natural defeat plus keyboard UI restart; no touch/browser/render/performance/art acceptance","status":"PASS_DEFEAT_RESTART" if passed else "FAILED_OR_INCOMPLETE","build":EXPECTED_BUILD,"seed":824613,"bound_ticks":MAX_TICKS,"restart_tick_bound":40,"population_limit":game.Rules.POP_LIMIT,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"harness_sha256":FileAccess.get_sha256(get_script().resource_path),"engine":Engine.get_version_info().string,"input_trace":inputs,"initial":checkpoints[0],"checkpoints":checkpoints,"terminal":terminal,"end_reason":reason,"invariant_failures":invariants,"economy_audit":audit,"ui_restart":ui,"restarted":restarted,"post_restart":post_restart,"restart_execution":execution,"wall_ms":Time.get_ticks_msec()-start}
	var file=FileAccess.open(args[0],FileAccess.WRITE)
	if file==null: push_error("Cannot write report."); quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("DEFEAT_RESTART_RESULT ",report.status," reason=",reason," tick=",terminal.snapshot.tick)
	quit(0 if passed else 1)
