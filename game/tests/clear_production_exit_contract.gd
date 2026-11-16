extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
	var stock={"food":1000,"wood":1000,"stone":1000,"iron":1000}
	g._test_reset([stock,stock.duplicate(true)]);g.set_process(false);await process_frame
	var home=g._first(0,"town_center");var worker=g._first(0,"villager");var place=Vector3.INF;var distance=INF
	for y in Rules.MAP_SIZE:
		for x in Rules.MAP_SIZE:
			var point=g._point(Vector2i(x,y));var d=point.distance_squared_to(home.pos)
			if d<distance and g._placement_reason("barracks",point,0,worker.id).is_empty():place=point;distance=d
	var producer=g._spawn("barracks",0,place)
	for i in 5:g._spawn("house",0,Vector3(15,0,8+i*3))
	g._navigation_rebuild()
	for cell in g._production_exit_cells(producer,"spearman"):
		if not g.navigation.is_point_solid(cell):g._spawn("scout",0,g._point(cell))
	g._update_vision()
	check("paid training accepted with available capacity",g._enqueue_train(producer.id,"spearman",0))
	var paid=g.economy.bank_milli(0).duplicate(true);var initial_army=g._count(0,"spearman")
	for i in Rules.TRAIN_TICKS.spearman+2:g._tick(Rules.TICK)
	check("actual training finishes but occupied exit blocks birth",producer.queue.size()==1 and producer.queue[0].remaining_ticks==0 and g._count(0,"spearman")==initial_army)
	check("small-unit exit geometry unchanged",g._production_exit_cells(producer,"spearman")==g._perimeter_cells(producer))
	var expanded={}
	for first_cell in g._perimeter_cells(producer):
		for dx in [-1,0,1]:
			for dy in [-1,0,1]:expanded[first_cell+Vector2i(dx,dy)]=true
	var expected=expanded.keys();expected.sort_custom(func(a,b):return a.x<b.x or (a.x==b.x and a.y<b.y))
	check("large-unit exit geometry and order unchanged",g._production_exit_cells(producer,"siege")==expected)
	var receipt=producer.queue[0].receipt_id
	g._select([producer.id]);g._update_hud()
	check("ready producer offers clearing",is_instance_valid(g.clear_exit_button) and not g.clear_exit_button.disabled)
	var plan=g._clear_exit_plan(producer.id)
	check("bounded ordinary move plan",plan.size()>0 and plan.size()<=8 and plan.all(func(o):return o.target==-1 and o.clear_exit_building==producer.id))
	var first=plan[0].ids[0];var foreign=g._get_entity(first);foreign.team=1;g._update_vision()
	check("enemy occupying exit never receives move order",g._clear_exit_plan(producer.id).all(func(o):return o.ids[0]!=first))
	foreign.team=0;g._update_vision();g._refresh_clear_exit_button()
	g.paused=true;g._refresh_clear_exit_button();g._clear_production_exit(producer.id)
	check("paused clear does not issue orders",g.commands.is_empty() and g.clear_exit_button.disabled)
	g.paused=false;g._refresh_clear_exit_button()
	g._submit("stop",{"ids":[first]})
	check("pending unit order protected",g._clear_exit_plan(producer.id).all(func(o):return o.ids[0]!=first))
	g.commands.clear();g._refresh_clear_exit_button()
	g._clear_production_exit(producer.id)
	check("only ordinary movement submitted",g.commands.size()==plan.size() and g.commands.all(func(c):return c.type=="order"))
	check("queue and payment unchanged by clearing request",producer.queue[0].receipt_id==receipt and g.economy.bank_milli(0)==paid)
	var queued=g.commands.size();g._clear_production_exit(producer.id)
	var seen={}
	for command in g.commands:
		for id in command.ids:seen[id]=seen.get(id,0)+1
	check("repeated clear cannot duplicate pending units",seen.values().all(func(n):return n==1))
	for i in 600:
		g._tick(Rules.TICK)
		if producer.queue.is_empty():break
	check("native movement enables normal birth",producer.queue.is_empty() and g._count(0,"spearman")==initial_army+1)
	check("no second payment or duplicate unit",g.economy.bank_milli(0)==paid and g.trained_total[0]==1)
	g._update_hud();check("clear action removed when queue completed",not is_instance_valid(g.clear_exit_button))
	var stale=plan[0].duplicate();stale.type="order";stale.team=0
	var unit=g._get_entity(first);unit.state="idle";unit.dest=unit.pos;var old_dest=unit.dest
	g._execute(stale);check("retired queue cannot move former blocker",unit.state=="idle" and unit.dest==old_dest)
	check("economy conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"clear_production_exit_contract","checks":checks,"failed":failed,"scope":"Controlled spawned housing/blockers; actual paid full training, native move and birth; not natural match progression or physical phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)
