extends SceneTree
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await process_frame
	shell._show_page("battle_groups");shell.buttons.get_node("BattleGroup2").pressed.emit();shell.buttons.get_node("ChooseBattle_fortress").pressed.emit()
	check("mode cycle reaches fortress after quick battle",shell.selected_mode=="fortress")
	shell._choose_battle("survival");check("staged defense remains selectable",shell.selected_mode=="survival")
	shell.selected_mode="fortress";shell.selected_victory_mode="conquest";shell._show_page("setup")
	check("setup discloses symmetric scenario army",shell.description.text.contains("長槍兵 4") and shell.description.text.contains("兩座箭塔"))
	for size in [Vector2i(390,844),Vector2i(320,568),Vector2i(568,320),Vector2i(1280,800)]:
		root.size=size;shell._layout();await process_frame;await process_frame
		var prose=shell.scroll.get_global_rect()
		var actions=shell.buttons.get_global_rect()
		var separated=prose.end.x+14.0<=actions.position.x if shell.setup_split_active else prose.end.y<=actions.position.y
		check("fortress setup prose cannot overlap actions %s" % size,separated and not prose.intersects(actions))
		for button in shell.buttons.get_children():check("fortress setup button fits %s %s" % [size,button.name],Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()))
	shell._start_match();await process_frame;await process_frame
	var g=shell.match_node;g.set_process(false)
	check("fortress launch selects ready army",g.selected.size()==12 and g.camera_focus.distance_to(Vector3(-25,0,11))<0.1)
	g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false)
	check("fortress mode preserved through actual menu",g.skirmish_mode=="fortress" and g.victory_mode=="conquest")
	for team in 2:
		check("mixed army exact team %d"%team,g._count(team,"spearman")==4 and g._count(team,"archer")==4 and g._count(team,"cavalry")==2 and g._count(team,"siege")==2)
		check("original workers scout retained team %d"%team,g._count(team,"villager")==5 and g._count(team,"scout")==1)
		check("population supported team %d"%team,g._population(team)==18 and g._capacity(team)==25)
		check("age two unlocked immediately team %d"%team,g._age2(team) and g._kind_unlocked("stable",team))
	var occupied={};var overlap=false
	for ent in g.entities:
		if ent.category=="unit":continue
		for cell in g._occupied_cells(ent):
			if occupied.has(cell):overlap=true;print("COLLISION ",cell," ",occupied.get(cell)," ",ent.kind," ",ent.pos)
			occupied[cell]=ent.kind
	check("scenario structures and resources never overlap",not overlap)
	for team in 2:
		for kind in ["barracks","range","stable","workshop"]:
			var b=g._first(team,kind)
			check("producer present and completed %d %s"%[team,kind],not b.is_empty() and b.built)
		check("two defensive towers %d"%team,g._count(team,"tower")==2)
	var physical=true;var mirrors=true
	for unit in g.entities:
		if unit.team!=0 or unit.category!="unit" or unit.kind in ["villager","scout"]:continue
		physical=physical and g._unit_step_is_free(unit,unit.pos)
		var found=false
		for enemy in g.entities:
			if enemy.team==1 and enemy.kind==unit.kind and enemy.pos==-unit.pos:found=true
		mirrors=mirrors and found
	check("military births clear terrain and other entities",physical)
	check("opposing armies exactly mirrored",mirrors)
	check("initial gifts not misreported as training or construction",g.match_report.events.is_empty() and g.trained_total==[0,0] and g.completed_builds==[0,0])
	check("banks remain symmetric ordinary opening funds",g.economy.bank_milli(0)==g.economy.bank_milli(1) and g.economy.bank_milli(0).food==g.INITIAL_STOCKS[0].food*1000)
	check("normal tutorial hidden for fortress start",g.demo_tutorial.skipped)
	check("normal standard ai policy retained",g.SkirmishPolicy.offensive("fortress") and g.SkirmishPolicy.muster("fortress")==5 and g.SkirmishPolicy.interval("fortress")==1800)
	var barracks=g._first(0,"barracks");var before=g.economy.bank_milli(0).duplicate()
	g._submit("train",{"building":barracks.id,"kind":"spearman"})
	g._tick(g.Rules.TICK)
	check("scenario producer accepts paid reinforcement",barracks.queue.size()==1 and g.economy.bank_milli(0).food==before.food-g.Rules.COSTS.spearman.food*1000)
	for i in 365:g._tick(g.Rules.TICK)
	check("reinforcement completes through actual production exit",g._count(0,"spearman")==5 and barracks.queue.is_empty() and g.trained_total[0]==1)
	g._submit("surrender",{});g._tick(g.Rules.TICK)
	check("standard surrender ends fortress game",g.game_over and g.outcome=="defeat")
	check("report does not claim free age was researched",g.end_report_label.text.contains("開局已有") and not g.end_report_label.text.contains("00:00  研究"))
	shell._restart_match();await process_frame;await process_frame;g=shell.match_node;g.set_process(false)
	check("restart retains fortress scenario",g.skirmish_mode=="fortress" and g._count(0,"siege")==2)
	g.skirmish_mode="standard";g._test_reset();check("ordinary start unchanged",g._population(0)==6 and g._capacity(0)==10 and not g._age2(0) and not g.demo_tutorial.skipped)
	check("ledger conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"fortress_battle_contract","checks":checks,"failed":failed,"scope":"Native real menu scenario start, geometry, mirrored populations/positions, opening ledgers and restart; not natural match balance or rendered acceptance"}))
	shell.queue_free();quit(1 if failed else 0)
