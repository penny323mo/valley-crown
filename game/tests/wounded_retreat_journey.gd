extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
	g._test_reset();g.set_process(false);await process_frame
	var home=g._first(0,"town_center")
	var soldier=g._spawn("scout",0,home.pos+Vector3(10,0,0));soldier.hp=20
	var origin=soldier.pos
	g._update_vision();g._select([soldier.id]);g._update_hud()
	g._retreat_wounded()
	check("player button submits retreat",g.commands.size()==1)
	for i in 600:
		g._tick(Rules.TICK)
		if soldier.hp>20:break
	check("walks to home through native ticks before healing",soldier.hp==21 and soldier.pos.distance_to(origin)>1 and soldier.pos.distance_to(home.pos)<=7.0)
	check("finished movement rests without another player order",soldier.state=="idle" and soldier.rest_ticks>=200)
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"wounded_retreat_journey","checks":checks,"failed":failed,"scope":"Controlled clear route and actual native ticks; not arbitrary map/path safety or physical-phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)
