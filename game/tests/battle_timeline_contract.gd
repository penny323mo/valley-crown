extends SceneTree
const Report=preload("res://scripts/match_report.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var log=Report.new()
	var unit={"id":1,"team":0,"alive":true,"category":"unit","kind":"spearman"}
	check("own birth accepted",log.record_training(unit,600))
	check("event has actual supplied timestamp",log.events[0].tick==600 and log.events[0].action=="trained")
	check("repeated birth deduplicated",not log.record_training(unit,601) and log.events.size()==1)
	var enemy=unit.duplicate();enemy.id=2;enemy.team=1
	check("enemy birth never recorded",not log.record_training(enemy,700) and log.events.size()==1)
	var building={"id":3,"team":0,"alive":true,"category":"building","kind":"house","built":false}
	check("unfinished building not a milestone",not log.record_completion(building,800))
	building.built=true;log.record_completion(building,900)
	unit.hp=0;log.record_settled_loss(unit,10,1000)
	check("construction and loss timestamps retained",log.events[1].tick==900 and log.events[1].action=="completed" and log.events[2].tick==1000 and log.events[2].action=="lost")
	var report=log.make_report("defeat","surrender",1100,750,{},{});var text=Report.page_text(report,"overview")
	check("chronological age milestone interleaved",text.find("00:30  出兵")<text.find("00:37  研究") and text.find("00:37  研究")<text.find("00:45  完工"))
	check("loss timestamp visible",text.contains("00:50  戰損"))
	log.events[0].tick=9999
	check("frozen report detached from live events",report.events[0].tick==600)
	log.reset();check("reset clears bounded history",log.events.is_empty() and log.omitted_events==0)
	for i in 80:
		var fresh=unit.duplicate();fresh.id=i+10;log.record_training(fresh,i*20)
	check("history capped to sixty four",log.events.size()==64 and log.omitted_events==16)
	report=log.make_report("victory","castle",1600,-1,{},{});text=Report.page_text(report,"overview")
	check("retained totals stay complete",report.trained.spearman==80)
	check("only latest twelve and omissions disclosed",text.contains("較早 68 項未列出") and text.contains("01:19  出兵") and not text.contains("01:07  出兵"))
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	check("opening army not timeline events",g.match_report.events.is_empty())
	var keep=g._first(0,"town_center");g._enqueue_train(keep.id,"villager",0)
	check("queueing is not a timeline event",g.match_report.events.is_empty())
	for i in 300:
		g.tick_count+=1;g._update_production(keep,g.Rules.TICK,false);g._process_ready_production()
	check("actual production hook records exact tick",g.match_report.events.size()==1 and g.match_report.events[0].tick==300 and g.match_report.events[0].kind=="villager")
	g._submit("surrender",{});g._tick(g.Rules.TICK)
	check("end overview contains real birth time",g.game_over and g.end_report_label.text.contains("00:15  出兵 · 村民"))
	var frozen=g.last_match_report.duplicate(true);g._check_end()
	check("repeated end cannot duplicate history",g.last_match_report==frozen)
	check("ledger conserved",g.economy.audit().ok)
	g._test_reset();check("restart clears current events but not frozen report",g.match_report.events.is_empty() and frozen.events.size()==1)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"battle_timeline_contract","checks":checks,"failed":failed,"scope":"Native bounded immutable own-event history and real paid birth/end hooks; controlled fixture, no natural full-match or rendered acceptance"}))
	g.queue_free();quit(1 if failed else 0)
