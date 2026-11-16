extends SceneTree
const Goal=preload("res://scripts/supply_race.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func supply(g,team,resource,amount):
	# Controlled component setup through real extraction/deposit APIs, no travel claim.
	var worker=90000+team*100+(0 if resource=="food" else 1)
	var node=worker+1000
	g.economy.register_worker(worker,team);g.economy.register_node(node,resource,amount)
	var tick=0
	while g.economy.node_view(node).remaining_milli>0:
		tick+=1;g.economy.gather_tick(worker,node,tick)
		var w=g.economy.worker_view(worker)
		if w.cargo_milli==10000 or g.economy.node_view(node).remaining_milli==0:g.economy.deposit("supply:%d:%d" % [worker,tick],worker,w.cargo_revision)
func run():
	check("initial stock and refund never count",not Goal.complete({"food":9000000,"wood":9000000,"refunded":{"food":9000000,"wood":9000000}}))
	check("both resource targets required",not Goal.complete({"delivered":{"food":600000,"wood":399999}}))
	check("exact delivery thresholds win",Goal.complete({"delivered":{"food":600000,"wood":400000}}))
	check("public progress capped",Goal.progress({"delivered":{"food":900000,"wood":-2}})=={"food":600000,"wood":0})
	var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await process_frame
	shell._show_page("setup")
	shell._show_page("battle_groups");shell.buttons.get_node("BattleGroup1").pressed.emit();shell.buttons.get_node("ChooseBattle_supply").pressed.emit()
	check("menu enters distinct supply mode",shell.selected_victory_mode=="supply" and shell.mode_title.text=="資源爭奪戰")
	check("rules disclose delivered-only and public opponent progress","進度公開" in shell.description.text and "退款" in shell.description.text and "600" in shell.description.text)
	for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size=size;shell._layout();await process_frame;await process_frame
		for button in shell.buttons.get_children():check("setup fits %s %s" % [size,button.name],Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()))
	shell.buttons.get_node("LaunchMatchButton").pressed.emit();await process_frame;await process_frame
	var g=shell.match_node;g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);g._update_hud()
	check("real menu launches supply match without king flag",g.victory_mode=="supply" and not g.control_point_marker.visible and g.objective_button.visible)
	check("starting supplies do not win",not g.game_over and not Goal.complete(g.economy.stats_view(0)))
	for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size=size;g._update_hud();g._layout_ui();await process_frame;await process_frame
		check("score HUD fits %s" % size,Rect2(Vector2.ZERO,Vector2(size)).encloses(g.objective_button.get_global_rect()) and g.objective_button.get_global_rect().end.y<g.hud_bottom.position.y)
	g.objective_button.pressed.emit();check("objective click returns own keep without orders",g.camera_focus==g._first(0,"town_center").pos and g.commands.is_empty())
	supply(g,0,"food",600000);g._check_end();check("food alone does not finish",not g.game_over)
	supply(g,0,"wood",400000);g._check_end()
	check("actual ledger deliveries trigger official victory",g.game_over and g.outcome=="victory" and g.end_reason=="supply_race")
	check("result screen and report explain supply outcome",g.end_title.text=="資源目標完成" and "資源爭奪戰" in g.MatchReport.page_text(g.last_match_report,"overview"))
	check("public objective report captures both sides",g.last_match_report.supply_progress[0]=={"food":600000,"wood":400000} and g.last_match_report.supply_progress[1]=={"food":0,"wood":0})
	check("component setup conserves ledger",g.economy.audit().ok)
	g._test_reset();supply(g,1,"food",600000);supply(g,1,"wood",400000);g._check_end()
	check("same rule permits computer victory",g.outcome=="defeat" and g.end_reason=="supply_race")
	g._test_reset()
	for team in 2:supply(g,team,"food",600000);supply(g,team,"wood",400000)
	g._check_end();check("same settlement round is draw",g.outcome=="draw")
	g._test_reset();supply(g,0,"food",600000);supply(g,0,"wood",400000);g.victory_mode="conquest";g._check_end()
	check("conquest does not adopt supply victory",not g.game_over)
	g.victory_mode="supply";g._surrender_intent[0]=true;g._check_end();check("accepted surrender keeps precedence",g.outcome=="defeat" and g.end_reason=="surrender")
	shell._restart_match();await process_frame;await process_frame;g=shell.match_node;g.set_process(false)
	check("restart retains supply mode but resets delivery",g.victory_mode=="supply" and Goal.progress(g.economy.stats_view(0))=={"food":0,"wood":0})
	shell._choose_battle("standard");check("ordinary modes remain reachable",shell.selected_victory_mode=="conquest")
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"supply_race_contract","checks":checks,"failed":failed,"scope":"Native menu/end lifecycle with controlled real ledger deposits; not natural full-match balance, travel or physical phone acceptance"}))
	shell.queue_free();quit(1 if failed else 0)
