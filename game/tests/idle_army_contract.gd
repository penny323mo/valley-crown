extends SceneTree
const Selector=preload("res://scripts/idle_army_selection.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	var r={1:{"id":1,"owned":true,"alive":true,"remembered":false,"team":0,"category":"unit","kind":"scout","state":"idle","path":[],"path_pending":false}}
	check("own ready scout selected",Selector.eligible(r,[])==[1])
	for change in [{"alive":false},{"remembered":true},{"owned":false},{"team":1},{"kind":"villager"},{"category":"building"},{"state":"move"},{"mode":"PATROL"},{"state":"attack"},{"path_pending":true},{"path":[Vector3.ZERO]}]:
		var copy=r.duplicate(true); copy[1].merge(change,true)
		check("reject "+str(change),Selector.eligible(copy,[]).is_empty())
	for type in ["order","advance","patrol","stop","defend"]:
		check("pending "+type+" excluded",Selector.eligible(r,[{"type":type,"team":0,"ids":[1]}]).is_empty())
	check("opponent command irrelevant",Selector.eligible(r,[{"type":"order","team":1,"ids":[1]}])==[1])
	var g=load("res://main.tscn").instantiate(); root.add_child(g); g.set_process(false); g.test_mode=true; g.ai_enabled=false; g._test_reset(); g.set_process(false)
	await process_frame
	var scout=g._first(0,"scout"); var villager=g._first(0,"villager")
	g._update_vision(); g._select([villager.id]); g.compact_menu.show(); g._refresh_idle_army_button()
	var n=g.commands.size(); var mode=scout.mode
	g._select_idle_army()
	check("GUI selects military not worker",g.selected==[scout.id])
	check("selection issues no command or stance change",g.commands.size()==n and scout.mode==mode)
	g._select([villager.id]); g.compact_menu.show(); g._refresh_idle_army_button()
	g._submit("order",{"ids":[scout.id],"intent":"move","position":scout.pos+Vector3(2,0,0)})
	g._select_idle_army()
	check("stale button cannot select newly busy soldier",g.selected==[villager.id])
	g.commands.clear(); g.paused=true; g._refresh_idle_army_button(); g._select_idle_army()
	check("pause disables shortcut",g.idle_army_button.disabled and g.selected==[villager.id])
	g.paused=false; g.game_over=true; g._refresh_idle_army_button()
	check("game end disables shortcut",g.idle_army_button.disabled)
	g.game_over=false; root.size=Vector2i(320,568); g.compact_menu.show(); g._layout_ui()
	await process_frame
	await process_frame
	check("phone button stays inside menu",g.idle_army_button.get_global_rect().end.x<=g.compact_menu.get_global_rect().end.x)
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c): return not c.passed).size()
	print(JSON.stringify({"suite":"idle_army_contract","checks":checks,"failed":failed,"scope":"Controlled direct GUI helpers and selector; no browser/iPhone acceptance"}))
	g.queue_free(); quit(1 if failed else 0)
