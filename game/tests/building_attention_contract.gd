extends SceneTree
const Attention=preload("res://scripts/building_attention.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func building(id,built,hp=100):return {"id":id,"owned":true,"alive":true,"remembered":false,"team":0,"category":"building","kind":"house","built":built,"hp":hp,"max_hp":100}
func _initialize():call_deferred("run")
func run():
	var records={1:building(1,false),2:building(2,true,40),3:building(3,true),4:building(4,false)}
	var s=Attention.snapshot(records,[])
	check("unassigned sites sorted",s.unassigned==[1,4] and s.unfinished==[1,4])
	check("only completed damaged buildings need repair",s.damaged==[2])
	var worker={"id":5,"kind":"villager","owned":true,"alive":true,"team":0,"state":"build","target":1}
	records[5]=worker
	check("active builder protects assigned site",Attention.snapshot(records,[]).unassigned==[4])
	check("pending own order protects site",Attention.snapshot(records,[{"type":"order","team":0,"target":4}]).unassigned.is_empty())
	check("enemy order does not protect site",Attention.snapshot(records,[{"type":"order","team":1,"target":4}]).unassigned==[4])
	for patch in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"category":"unit"}]:
		var b=building(1,false);b.merge(patch,true)
		check("exclude "+str(patch),Attention.snapshot({1:b},[]).unassigned.is_empty())
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var base=g._first(0,"town_center");base.hp-=10
	g._update_vision();g.compact_menu.show();g._set_shortcut_category("production");g._refresh_production_buttons()
	var bank=g.economy.bank_milli(0).duplicate()
	check("native damaged base counted",g.building_attention_buttons.damaged.get_meta("squad_ids",[])==[base.id])
	g.building_attention_buttons.damaged.pressed.emit()
	check("native button locates building",g.selected==[base.id] and g.camera_focus==base.pos and not g.compact_menu.visible)
	check("existing repair action exposed",is_instance_valid(g.repair_dispatch_button))
	check("navigation does not repair spend or command",base.hp==base.max_hp-10 and g.commands.is_empty() and g.economy.bank_milli(0)==bank)
	# Controlled unfinished base record exercises real selection and existing
	# construction dispatch UI; no claim of naturally reached construction.
	base.built=false;base.progress=0.2
	g._update_vision();g.compact_menu.show();g._refresh_production_buttons();g.building_attention_buttons.unassigned.pressed.emit()
	check("unfinished site opens existing resume control",g.selected==[base.id] and is_instance_valid(g.construction_dispatch_button))
	g.compact_menu.show();g._refresh_production_buttons();g._submit("order",{"ids":[g._first(0,"villager").id],"target":base.id})
	g._select([]);g._focus_building_attention("unassigned")
	check("stale pending site cannot select",g.selected.is_empty())
	g.commands.clear();g.paused=true;g._refresh_production_buttons();g._focus_building_attention("unassigned")
	check("pause disables navigation",g.building_attention_buttons.unassigned.disabled and g.selected.is_empty())
	g.paused=false;g._refresh_production_buttons();g._set_shortcut_category("army");g._focus_building_attention("unassigned")
	check("hidden tab cannot navigate",g.selected.is_empty())
	g._set_shortcut_category("production")
	for width in [320,390,844]:
		root.size=Vector2i(width,600);g._layout_ui();await process_frame;await process_frame
		for b in g.building_attention_buttons.values():check("fits "+str(width)+" "+b.name,b.get_global_rect().end.x<=g.compact_menu.get_global_rect().end.x)
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"building_attention_contract","checks":checks,"failed":failed,"scope":"Controlled records and native selection/UI; not natural match or physical phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)
