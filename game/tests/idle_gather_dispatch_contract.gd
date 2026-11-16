extends SceneTree
const Dispatch=preload("res://scripts/idle_gather_dispatch.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var w={"id":1,"owned":true,"alive":true,"team":0,"category":"unit","kind":"villager","state":"idle","path":[],"pos":Vector3.ZERO}
	var node={"id":10,"alive":true,"remembered":false,"team":-1,"category":"resource","kind":"berry","hp":100,"pos":Vector3(3,0,0)}
	var records={1:w,10:node}
	check("visible closest matching resource chosen",Dispatch.orders(records,[],"food")[0].target==10)
	check("unavailable resource cannot be conjured",Dispatch.orders(records,[],"iron").is_empty())
	check("invalid resource rejected",Dispatch.orders(records,[],"gold").is_empty())
	for patch in [{"state":"gather"},{"path":[Vector3.ONE]},{"path_pending":true},{"cargo_milli":1},{"carry":1.0},{"owned":false},{"alive":false},{"team":1}]:
		var r=w.duplicate(true);r.merge(patch,true);check("worker excluded "+str(patch),Dispatch.orders({1:r,10:node},[],"food").is_empty())
	check("pending build protected",Dispatch.orders(records,[{"team":0,"type":"build","builder":1}],"food").is_empty())
	check("pending movement protected",Dispatch.orders(records,[{"team":0,"type":"order","ids":[1]}],"food").is_empty())
	for patch in [{"remembered":true},{"alive":false},{"hp":0}]:
		var n=node.duplicate();n.merge(patch,true);check("resource excluded "+str(patch),Dispatch.orders({1:w,10:n},[],"food").is_empty())
	for i in range(2,6):
		var extra=w.duplicate(true);extra.id=i;records[i]=extra
	check("batch capped at three",Dispatch.orders(records,[],"food").size()==3)
	records[20]={"id":20,"alive":true,"team":1,"category":"unit","pos":Vector3(4,0,0)}
	check("known threat excludes dispatch",Dispatch.orders(records,[],"food").is_empty())
	records[20].remembered=true;check("memory not treated as live threat",Dispatch.orders(records,[],"food").size()==3)
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	g.compact_menu.show();g._update_vision();g._update_hud()
	var before=g.economy.bank_milli(0).duplicate(true);var selection=g.selected.duplicate()
	var plan=Dispatch.orders(g.faction_views[0].records(),g.commands,"food")
	check("real idle villagers have available food dispatch",plan.size()>0 and plan.size()<=3 and not g.idle_dispatch_buttons.food.disabled)
	g._dispatch_idle_gather("food")
	check("ordinary gather orders only",g.commands.size()==plan.size() and g.commands.all(func(c):return c.type=="order" and c.idle_gather=="food"))
	check("dispatch does not mint resources or change selection",before==g.economy.bank_milli(0) and g.selected==selection)
	g.compact_menu.show();g._dispatch_idle_gather("food")
	var unique={}
	for c in g.commands:
		var id=c.ids[0];unique[id]=unique.get(id,0)+1
	check("reopened menu cannot duplicate pending workers",unique.values().all(func(count):return count==1) and g.commands.size()>=plan.size())
	var rejected=g.commands.pop_front();var worker=g._get_entity(rejected.ids[0]);worker.state="move";worker.dest=worker.pos+Vector3(1,0,0)
	g._execute(rejected);check("new job before execution preserved",worker.state=="move" and worker.target==-1)
	while not g.commands.is_empty():g._execute(g.commands.pop_front())
	check("normal accepted workers enter gathering",g.entities.any(func(e):return e.alive and e.team==0 and e.kind=="villager" and e.state=="gather"))
	for i in 1800:
		g._tick(Rules.TICK)
		if g.economy.bank_milli(0).food>before.food:break
	check("native gathering and delivery increases real food",g.economy.bank_milli(0).food>before.food)
	check("ledger conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"idle_gather_dispatch_contract","checks":checks,"failed":failed,"scope":"Controlled initial map and native gather/delivery; not arbitrary path safety or physical phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)
