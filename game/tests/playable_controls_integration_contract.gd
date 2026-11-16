extends SceneTree
const Rules=preload("res://scripts/rules.gd")
## Prepared only: controlled projected HUD and real command callbacks, not a match.
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"pass":ok})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game.paused=false; game.game_over=false; game.compact_ui=true
	game.commands.clear()
	var records={}
	var workers=[]
	for record in game.faction_views[0].records().values():
		if record.get("owned",false) and record.kind=="villager":
			var worker=record.duplicate(true)
			worker.state="idle"; worker.mode="WORK"; worker.path_request_kind="work"
			worker.path_status="IDLE"; worker.path_pending=false; worker.gather_type="food"; worker.cargo_milli=0
			records[worker.id]=worker; workers.append(worker.id)
		elif record.get("owned",false) and record.kind=="town_center": records[record.id]=record.duplicate(true)
	check("fixture has two workers",workers.size()>=2)
	if workers.size()<2: finish(); return
	var loaded=workers[0]; var empty=workers[1]
	records[loaded].cargo_milli=1
	game.faction_views[0].current=records; game.faction_views[0].memory.clear()
	game.selected=[loaded,empty]; game._update_hud()
	var button=game.return_cargo_button
	check("mixed selection keeps missing count",game.selection_detail.text.contains("1 村民無已知採集點"))
	check("mixed selection has only delivery suffix",game.selection_detail.text.contains("滑動底列") and not game.selection_detail.text.contains("探索或落指令") and not game.selection_detail.text.contains("按指令再點目標"))
	check("partial cargo enables return",not button.disabled)
	records[loaded].cargo_milli=0; game._update_hud()
	check("cargo change preserves button identity",game.return_cargo_button==button)
	check("empty group gets exploration only",button.disabled and game.selection_detail.text.contains("2 村民無已知採集點") and game.selection_detail.text.contains("探索或落指令") and not game.selection_detail.text.contains("滑動底列"))
	records[loaded].cargo_milli=1; records[loaded].state="deliver"; records[loaded].path_status="QUEUED"; game._update_hud()
	check("healthy delivery skipped while empty worker warns",button.disabled and game.selection_detail.text.contains("探索或落指令"))
	records[loaded].path_status="LIMIT_REACHED"; game._update_hud()
	check("terminal delivery eligible without idle hint",not button.disabled and not game.selection_detail.text.contains("滑動底列"))
	records[loaded].state="idle"; game.touch_command=true; game._update_hud()
	check("touch instructions own detail",game.selection_detail.text.contains("取消可返回選取") and not game.selection_detail.text.contains("無已知"))
	game._submit_selected_stance("stop"); game._update_hud()
	check("stance retires targeting and queues explicit intent",not game.touch_command and game.commands.size()==1 and game.commands[0].type=="stop")
	game._return_selected_cargo()
	check("return cannot overwrite queued stance",game.commands.size()==1 and game.return_cargo_button.disabled)
	check("pending own commands suppress warning",not game.selection_detail.text.contains("無已知"))
	game.commands.clear(); game._return_selected_cargo(); game._return_selected_cargo()
	check("return targets only loaded worker once",game.commands.size()==1 and game.commands[0].ids==[loaded] and game.commands[0].target>=0)
	game._submit_selected_stance("defend"); game._return_selected_cargo()
	check("later defend remains final intent",game.commands.size()==2 and game.commands[-1].type=="defend")
	game.commands.clear()
	# Red witness in naive concatenation: pending idle worker plus eligible
	# nonidle terminal delivery must not produce idle-delivery guidance.
	records[empty].cargo_milli=1; records[empty].state="deliver"; records[empty].path_status="NO_PATH"
	game._submit("stop",{"ids":[loaded]}); game._update_hud()
	check("hint eligibility is per worker",not game.return_cargo_button.disabled and not game.selection_detail.text.contains("滑動底列"))
	game.commands.clear(); records[empty].cargo_milli=0; records[empty].state="idle"; records[empty].path_status="IDLE"
	for mode in ["build","box","rally"]:
		game.build_mode="house" if mode=="build" else ""
		game.box_select_mode=mode=="box"; game.rally_building=0 if mode=="rally" else -1
		game._update_hud(); game._return_selected_cargo()
		check(mode+" owns guidance and blocks return",not game.selection_detail.text.contains("無已知") and not game.selection_detail.text.contains("滑動底列") and game.commands.is_empty())
	game.build_mode=""; game.box_select_mode=false; game.rally_building=-1
	game._update_hud()
	var house_index=-1; var return_index=-1
	for i in game.actions.get_child_count():
		var child=game.actions.get_child(i)
		if child is Button and child.text.begins_with("民居"): house_index=i
		if child==game.return_cargo_button: return_index=i
	check("build access precedes delivery",house_index>=0 and return_index>house_index)
	finish()
func finish():
	var failures=checks.filter(func(row): return not row.pass)
	print("PLAYABLE_CONTROLS_INTEGRATION "+JSON.stringify({"build":Rules.BUILD_ID,"checks":checks,"failures":failures.size()}))
	quit(0 if failures.is_empty() else 1)
