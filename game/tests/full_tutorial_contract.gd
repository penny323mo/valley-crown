extends SceneTree
const Tutorial=preload("res://scripts/demo_tutorial.gd")
var checks=[]
var g
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func production(count):
	for i in count:
		g.tick_count+=1
		for entity in g.entities:
			if entity.alive and entity.category=="building":g._update_production(entity,g.Rules.TICK,false)
		g._process_ready_production()
func run():
	var tutorial=Tutorial.new()
	check("ten ordered onboarding stages",tutorial.KEYS.size()==10 and tutorial.HINTS.size()==10)
	for key in ["select","gather","deposit","house","barracks","soldier"]:tutorial.record(key)
	check("first army continues to age research",tutorial.step()==6 and tutorial.text(false).contains("7/10"))
	tutorial.record("combat");check("out of order achievement does not skip research",tutorial.step()==6)
	for key in ["age2","advanced_building","advanced_unit"]:tutorial.record(key)
	check("complete progression reaches end",tutorial.step()==10 and tutorial.text(false).begins_with("教學完成"))
	tutorial.reset();tutorial.skip();tutorial.record("age2");check("skip cannot accrue further facts",tutorial.achieved.is_empty())
	tutorial.reset();check("reset restores onboarding",not tutorial.skipped and tutorial.step()==0)
	var font=load("res://assets/fonts/ui_tc.otf");var glyphs=true
	for hint in tutorial.HINTS:
		for i in hint.length():
			if hint.unicode_at(i)>127 and not font.has_char(hint.unicode_at(i)):glyphs=false
	check("all tutorial hint glyphs present",glyphs)
	g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
	var stock={"food":2000,"wood":3000,"stone":1000,"iron":1000}
	g._test_reset([stock,stock]);g.set_process(false);await process_frame
	var keep=g._first(0,"town_center")
	check("funded ordinary research accepted",g._enqueue_research(keep.id,0))
	check("queued research not completed tutorial fact",not g.demo_tutorial.achieved.has("age2"))
	production(1799);check("research does not finish early",not g.demo_tutorial.achieved.has("age2"))
	production(1);check("actual research completion records tutorial fact",g.demo_tutorial.achieved.has("age2"));production(1)
	var worker=g._first(0,"villager");var point=Vector3.INF
	for z in range(-9,10):
		for x in range(-9,10):
			var candidate=g._snap_build_position("stable",g.MapRoutes.home(0)+Vector3(x,0,z))
			if g._placement_reason("stable",candidate,0,worker.id).is_empty():point=candidate;break
		if point!=Vector3.INF:break
	check("legal advanced building site exists",point!=Vector3.INF)
	var stable=g._place_building("stable",point,worker.id,0)
	check("paid construction begins without completion credit",not stable.is_empty() and not g.demo_tutorial.achieved.has("advanced_building"))
	var approach=g._free_adjacent(stable,worker.pos,false,0,worker)
	worker.pos=approach;worker.path=PackedVector3Array();g._update_vision(false)
	check("controlled worker on legal work approach",g._at_work_approach(worker,stable,true))
	for i in 900:g.tick_count+=1;g._update_unit(worker,g.Rules.TICK)
	check("actual advanced construction completion credited",stable.built and g.demo_tutorial.achieved.has("advanced_building"))
	check("ordinary cavalry training accepted",g._enqueue_train(stable.id,"cavalry",0))
	check("queued advanced unit not completion credit",not g.demo_tutorial.achieved.has("advanced_unit"))
	production(600)
	check("actual advanced birth credited",g._count(0,"cavalry")==1 and g.demo_tutorial.achieved.has("advanced_unit"))
	var attacker=g._first(0,"scout");var enemy=g._spawn("spearman",1,attacker.pos+Vector3(0.8,0,0),true)
	g._set_stance(attacker,"STOP");g._set_stance(enemy,"STOP");g._update_vision();var hp=enemy.hp
	check("actual combat release accepted",g._release_attack(attacker,enemy).applied)
	check("release alone earns no combat credit",not g.demo_tutorial.achieved.has("combat"))
	g._tick(g.Rules.TICK)
	check("settled visible damage earns combat credit",enemy.hp<hp and g.demo_tutorial.achieved.has("combat"))
	check("normal paid events conserve ledger",g.economy.audit().ok)
	g._test_reset();check("new match clears advanced achievements",g.demo_tutorial.achieved.is_empty())
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"full_tutorial_contract","checks":checks,"failed":failed,"scope":"Controlled funded native research/paid construction/training and settled combat; worker relocated to legal work approach, not natural full match or device visual acceptance"}))
	g.queue_free();quit(1 if failed else 0)
