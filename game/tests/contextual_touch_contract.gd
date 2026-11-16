extends SceneTree
# Controlled pure dispatch/capability checks. Requires guarded Godot execution.
class Fixture:
	extends "res://scripts/game.gd"
	var picked=-1
	var sent=[]
	func _update_hud(): pass
	func _world_at(_screen): return Vector3.ZERO
	func _pick(_screen,_allow_enemy=true): return picked
	func _select(ids): selected=ids.duplicate()
	func _send_world_order(_screen,_contextual=false):
		sent.append({"ids":selected.duplicate(),"target":picked,"rally":rally_building})
class OrderFixture:
	extends "res://scripts/game.gd"
	var picked=5
	func _world_at(_screen): return Vector3.ZERO
	func _pick(_screen,_allow_enemy=true): return picked
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize():
	var g=Fixture.new()
	var worker={"id":1,"owned":true,"alive":true,"team":0,"category":"unit","kind":"villager","remembered":false,"cargo_milli":0}
	var soldier=worker.duplicate(); soldier.id=2; soldier.kind="spearman"
	var keep={"id":3,"owned":true,"alive":true,"team":0,"category":"building","kind":"town_center","built":true,"hp":100,"max_hp":100}
	var enemy={"id":4,"owned":false,"alive":true,"team":1,"category":"unit","kind":"spearman"}
	var tree={"id":5,"owned":false,"alive":true,"team":-1,"category":"resource","kind":"tree"}
	g.faction_views[0].current={1:worker,2:soldier,3:keep,4:enemy,5:tree}
	g.picked=1; g._tap(Vector2.ZERO,true)
	check("friendly tap selects without order",g.selected==[1] and g.sent.is_empty())
	for target in [-1,4,5]:
		g.picked=target; g._tap(Vector2.ZERO,true)
		check("normal contextual target "+str(target),g.sent[-1].target==target and g.sent[-1].ids==[1] and not g.touch_command and g.selected==[1])
	g.selected=[1,2]; g.picked=4; g._tap(Vector2.ZERO,true)
	check("multi selection submits once and retains group",g.sent.size()==4 and g.sent[-1].ids==[1,2] and g.selected==[1,2])
	g.picked=3; g._tap(Vector2.ZERO,true)
	check("friendly building selects rather than orders",g.selected==[3] and g.sent.size()==4)
	g.picked=-1; g._tap(Vector2.ZERO,true)
	check("building only cannot issue movement",g.selected==[3] and g.sent.size()==4)
	g.selected=[1]; g.paused=true; g._tap(Vector2.ZERO,true); g.paused=false
	g.game_over=true; g._tap(Vector2.ZERO,true); g.game_over=false
	g.box_select_mode=true; g._tap(Vector2.ZERO,true); g.box_select_mode=false
	check("paused ended and box modes block contextual orders",g.sent.size()==4)
	g.build_mode="house"; g._tap(Vector2.ZERO,true)
	check("placement tap previews without command",g.build_preview_held and g.sent.size()==4)
	g.build_mode=""; g.touch_command=true; g.picked=3; g._tap(Vector2.ZERO,true)
	check("explicit targeting still targets friendly building",g.sent.size()==5 and g.sent[-1].target==3 and g.selected==[1])
	g.touch_command=false; g.picked=-1; g._tap(Vector2.ZERO,false)
	check("desktop empty left click issues contextual move",g.sent.size()==6 and g.selected==[1] and g.sent[-1].target==-1)
	g.sent.pop_back(); g.selected=[]
	for invalid in [{"alive":false},{"owned":false},{"team":1},{"category":"building"},{"remembered":true}]:
		var record=worker.duplicate(); record.merge(invalid,true); g.faction_views[0].current[1]=record; g.selected=[1,999]
		g._tap(Vector2.ZERO,true)
		check("reject invalid selection "+str(invalid),g.sent.size()==5)
	check("worker resource capability",g._target_order_intent(worker,tree,0)=="gather")
	check("soldier resource capability",g._target_order_intent(soldier,tree,0)=="move")
	check("both attack enemy",g._target_order_intent(worker,enemy,0)=="attack" and g._target_order_intent(soldier,enemy,0)=="attack")
	check("empty ground moves",g._target_order_intent(worker,{},0)=="move")
	var orders=OrderFixture.new()
	orders.faction_views[0].current={1:worker,2:soldier,3:keep,4:enemy,5:tree}
	orders.order_marker=Node3D.new(); orders.selected=[1,2,3,999]
	orders._send_world_order(Vector2.ZERO,true)
	check("resource tap dispatches only capable villagers",orders.commands.size()==1 and orders.commands[0].ids==[1] and orders.commands[0].target==5)
	orders.selected=[2]; orders._send_world_order(Vector2.ZERO,true)
	check("soldier resource tap leaves existing orders alone",orders.commands.size()==1)
	orders.picked=4; orders.selected=[1,2]; orders._send_world_order(Vector2.ZERO,true)
	check("enemy dispatch retains selected combat group",orders.commands.size()==2 and orders.commands[-1].ids==[1,2])
	var farm=keep.duplicate(); farm.id=6; farm.kind="farm"
	orders.faction_views[0].current[6]=farm; orders.picked=6; orders.selected=[1,2]
	orders._send_world_order(Vector2.ZERO,true)
	check("farm tap dispatches only capable villagers",orders.commands[-1].ids==[1] and orders.commands[-1].target==6)
	g.faction_views[0].current[1]=worker; g.faction_views[0].current[6]=farm; g.selected=[1]; g.picked=6
	g._tap(Vector2.ZERO,true)
	check("normal farm touch starts work not building selection",g.selected==[1] and g.sent[-1].target==6)
	# NEW reconstructed coverage. Actual _tap -> inherited producer -> _submit;
	# hit testing/projections are synthetic, not routed device input.
	for kind in ["scout","spearman","archer","cavalry","siege"]:
		var military=soldier.duplicate(); military.kind=kind
		orders.faction_views[0].current[2]=military
		for completed in [false,true]:
			var hostile=farm.duplicate(); hostile.id=7; hostile.owned=false; hostile.team=1; hostile.built=completed; hostile.remembered=false
			orders.faction_views[0].current[7]=hostile; orders.picked=7
			for selection in [[2],[1,2]]:
				orders.commands.clear(); orders.selected=selection.duplicate(); orders.touch_command=false
				orders._tap(Vector2.ZERO,true)
				check("enemy farm contextual "+kind+"/"+str(completed)+"/"+str(selection),orders.commands.size()==1 and orders.commands[0].ids==selection and orders.commands[0].target==7 and not orders.commands[0].has("farm_gather"))
				check("enemy farm authority attack "+kind+"/"+str(completed),orders._target_order_intent(military,hostile,0)=="attack")
		orders.commands.clear(); orders.picked=6; orders.selected=[1,2]; orders.touch_command=false
		orders._tap(Vector2.ZERO,true)
		check("owned farm filters escort "+kind,orders.commands.size()==1 and orders.commands[0].ids==[1] and orders.commands[0].get("farm_gather",false))
		orders.commands.clear(); orders.picked=5; orders.selected=[1,2]
		orders._send_world_order(Vector2.ZERO,true)
		check("resource still filters escort "+kind,orders.commands.size()==1 and orders.commands[0].ids==[1] and not orders.commands[0].has("farm_gather"))
	orders.commands.clear(); orders.picked=6; orders.selected=[1]; orders.touch_command=true
	orders._tap(Vector2.ZERO,true)
	check("explicit owned farm targeting remains untagged",orders.commands.size()==1 and not orders.commands[0].has("farm_gather"))
	orders.order_marker.free(); orders.free()
	g.free()
	print("CONTEXTUAL_TOUCH_CONTRACT "+JSON.stringify(checks))
	quit(0 if checks.all(func(c): return c.passed) else 1)
