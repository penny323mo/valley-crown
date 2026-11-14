extends SceneTree
const Overview=preload("res://scripts/workforce_overview.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func worker(id,state,resource=""):
	return {"id":id,"owned":true,"alive":true,"remembered":false,"team":0,"category":"unit","kind":"villager","state":state,"gather_type":resource,"path":[],"path_pending":false}
func _initialize(): call_deferred("run")
func run():
	var records={1:worker(1,"gather","food"),2:worker(2,"deliver","wood"),3:worker(3,"gather","stone"),4:worker(4,"gather","iron"),5:worker(5,"build"),6:worker(6,"idle"),7:worker(7,"move"),8:worker(8,"repair"),9:worker(9,"gather","food")}
	var s=Overview.snapshot(records,[{"type":"order","team":0,"ids":[9]}])
	for group in ["food","wood","stone","iron","idle","other","pending"]: check(group+" classified once",s.groups[group].size()==1)
	check("build and repair together",s.groups.building==[5,8])
	var count=0
	for group in s.groups: count+=s.groups[group].size()
	check("all categories sum to total",count==s.total and s.total==9)
	for change in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"kind":"scout"},{"category":"building"}]:
		var r=worker(1,"gather","wood"); r.merge(change,true)
		check("exclude "+str(change),Overview.snapshot({1:r},[]).total==0)
	check("pending build separate",Overview.snapshot(records,[{"type":"build","team":0,"builder":1}]).groups.pending==[1])
	check("opponent orders irrelevant",Overview.snapshot(records,[{"type":"order","team":1,"ids":[1]}]).groups.food==[1,9])
	var g=load("res://main.tscn").instantiate(); root.add_child(g); g.set_process(false); g.test_mode=true; g.ai_enabled=false; g._test_reset(); g.set_process(false)
	await process_frame
	var w=g._first(0,"villager"); var scout=g._first(0,"scout"); var source={}
	for r in g.faction_views[0].records().values():
		if r.kind in ["oak","pine"] and not r.remembered: source=r; break
	check("visible wood source exists",not source.is_empty())
	if not source.is_empty(): g._order(w,"gather",source.id)
	g._update_vision(); g._select([scout.id]); g.compact_menu.show(); g._refresh_workforce_buttons()
	var before=g.commands.size(); var target=w.target
	g._select_workforce("wood")
	check("real gather assignment selected",g.selected==[w.id])
	check("selection does not alter work or queue",w.target==target and w.state=="gather" and g.commands.size()==before)
	g._select([scout.id]); g.compact_menu.show(); g._refresh_workforce_buttons(); g._submit("stop",{"ids":[w.id]}); g._select_workforce("wood")
	check("pending reassignment rejects stale click",g.selected==[scout.id])
	g.commands.clear(); g.paused=true; g._refresh_workforce_buttons(); g._select_workforce("wood")
	check("paused selection disabled",g.workforce_buttons.wood.disabled and g.selected==[scout.id])
	g.paused=false; root.size=Vector2i(320,568); g.compact_menu.show(); g._layout_ui()
	await process_frame
	await process_frame
	var fits=true
	for button in g.workforce_buttons.values(): fits=fits and button.get_global_rect().end.x<=g.compact_menu.get_global_rect().end.x
	check("four resource buttons fit 320px",fits)
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"workforce_contract","checks":checks,"failed":failed,"scope":"Controlled engine/direct GUI calls, not routed touch or iPhone acceptance"}))
	g.queue_free(); quit(1 if failed else 0)
