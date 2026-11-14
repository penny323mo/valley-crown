extends SceneTree
const Filter=preload("res://scripts/unit_type_selection.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func unit(id,kind): return {"id":id,"kind":kind,"owned":true,"alive":true,"team":0,"category":"unit"}
func _initialize(): call_deferred("run")
func run():
	var records={1:unit(1,"spearman"),2:unit(2,"archer"),3:unit(3,"villager"),4:unit(4,"archer")}
	var s=Filter.groups(records,[3,2,1,2])
	check("mixed types split",s.keys().size()==3)
	check("duplicate selection deduplicated",s.archer==[2])
	check("unselected same type excluded",not s.archer.has(4))
	for change in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"category":"building"},{"kind":"house"}]:
		var r=unit(1,"archer");r.merge(change,true)
		check("exclude "+str(change),Filter.groups({1:r},[1]).is_empty())
	var g=load("res://main.tscn").instantiate(); root.add_child(g); g.set_process(false); g.test_mode=true; g.ai_enabled=false; g._test_reset(); g.set_process(false)
	await process_frame
	var worker=g._first(0,"villager");var scout=g._first(0,"scout")
	g._update_vision();g._select([worker.id,scout.id]);g._update_hud()
	check("mixed selection exposes two filters",g.unit_type_buttons.size()==2)
	var before=g.commands.size();var camera=g.camera_focus;var state=scout.state;var stance=scout.mode
	g._filter_selected_type("scout")
	check("filter retains chosen type only",g.selected==[scout.id])
	check("orders stance and camera unchanged",g.commands.size()==before and scout.state==state and scout.mode==stance and g.camera_focus==camera)
	g._update_hud();check("single type hides filters",g.unit_type_buttons.is_empty())
	g._select([worker.id,scout.id]);g._update_hud();g.paused=true;g._refresh_unit_type_buttons();g._filter_selected_type("scout")
	check("pause disables filter",g.selected==[worker.id,scout.id] and g.unit_type_buttons.scout.disabled)
	g.paused=false;g._refresh_unit_type_buttons();g.unit_type_buttons.scout.set_meta("squad_ids",[999]);g._filter_selected_type("scout")
	check("stale roster rejected",g.selected==[worker.id,scout.id])
	g._refresh_unit_type_buttons();g.unit_type_buttons.scout.set_meta("selection_source",[scout.id]);g._filter_selected_type("scout")
	check("replacement selection not inherited",g.selected==[worker.id,scout.id])
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"unit_type_selection_contract","checks":checks,"failed":failed,"scope":"Controlled engine/direct UI, not routed touchscreen acceptance"}))
	g.queue_free();quit(1 if failed else 0)
