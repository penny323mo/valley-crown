extends SceneTree
const Overview=preload("res://scripts/production_overview.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func building(id,queue=[],repeat_kind=""):
	return {"id":id,"owned":true,"alive":true,"remembered":false,"team":0,"category":"building","kind":"barracks","built":true,"queue":queue,"repeat_kind":repeat_kind}
func _initialize(): call_deferred("run")
func run():
	var records={1:building(1),2:building(2,[{"kind":"spearman"},{"kind":"forged_blades"}]),3:building(3,[],"spearman")}
	var s=Overview.snapshot(records).barracks
	check("all three buildings counted",s.ids==[1,2,3])
	check("idle count excludes auto waiting",s.idle==1)
	check("busy count not queued unit count",s.busy==1 and s.queued==2)
	check("auto waiting visible separately",s.automatic==1)
	check("cycle first",Overview.next_id(s.ids,-1)==1)
	check("cycle next",Overview.next_id(s.ids,1)==2)
	check("cycle wrap",Overview.next_id(s.ids,3)==1)
	check("empty cycle",Overview.next_id([],-1)==-1)
	for change in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"kind":"house"},{"built":false},{"category":"unit"}]:
		var b=building(1); b.merge(change,true)
		check("exclude "+str(change),Overview.snapshot({1:b}).barracks.ids.is_empty())
	var g=load("res://main.tscn").instantiate(); root.add_child(g); g.set_process(false); g.test_mode=true; g.ai_enabled=false; g._test_reset(); g.set_process(false)
	await process_frame
	var center=g._first(0,"town_center"); var worker=g._first(0,"villager")
	g._update_vision(); g._select([worker.id]); g.compact_menu.show(); g._refresh_production_buttons()
	var before=g.commands.size(); var queue=center.queue.duplicate(true)
	g._focus_production("town_center")
	check("actual building selected",g.selected==[center.id])
	check("selection preserves queue and commands",center.queue==queue and g.commands.size()==before)
	check("missing kind disabled",g.production_buttons.workshop.disabled)
	g._select([worker.id]); g.compact_menu.show(); g._refresh_production_buttons()
	g.production_buttons.town_center.set_meta("squad_ids",[9999]); g._focus_production("town_center")
	check("stale membership rejected",g.selected==[worker.id])
	g.paused=true; g._refresh_production_buttons(); g._focus_production("town_center")
	check("paused selection disabled",g.production_buttons.town_center.disabled and g.selected==[worker.id])
	g.paused=false; root.size=Vector2i(320,568); g.compact_menu.show(); g._layout_ui()
	await process_frame
	await process_frame
	var fits=true
	for button in g.production_buttons.values(): fits=fits and button.get_global_rect().end.x<=g.compact_menu.get_global_rect().end.x
	check("production rows fit 320px",fits)
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"production_overview_contract","checks":checks,"failed":failed,"scope":"Controlled engine/direct GUI calls, not routed touch or iPhone acceptance"}))
	g.queue_free(); quit(1 if failed else 0)
