extends SceneTree
const Retreat=preload("res://scripts/wounded_retreat.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var unit={"id":1,"owned":true,"alive":true,"team":0,"category":"unit","kind":"spearman","hp":30,"max_hp":100,"pos":Vector3(20,0,0)}
	var base={"id":2,"owned":true,"alive":true,"team":0,"category":"building","kind":"town_center","built":true,"pos":Vector3.ZERO}
	var records={1:unit,2:base}
	check("wounded selection deduplicated",Retreat.injured(records,[1,1])==[1])
	check("one ordinary ground retreat",Retreat.orders(records,[1],[]).size()==1 and Retreat.orders(records,[1],[])[0].target==-1)
	check("unselected wounded never ordered",Retreat.orders(records,[],[]).is_empty())
	check("pending command protected",Retreat.orders(records,[1],[{"team":0,"ids":[1]}]).is_empty())
	for patch in [{"hp":100},{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"kind":"villager"},{"kind":"siege_ram"}]:
		var bad=unit.duplicate();bad.merge(patch,true);check("ineligible "+str(patch),Retreat.orders({1:bad,2:base},[1],[]).is_empty())
	var near=unit.duplicate();near.pos=Vector3(6,0,0)
	check("already home not interrupted",Retreat.orders({1:near,2:base},[1],[]).is_empty())
	var threat={"id":3,"alive":true,"team":1,"category":"unit","pos":Vector3(6,0,0)}
	records[3]=threat
	check("known threatened base excluded",Retreat.orders(records,[1],[]).is_empty())
	threat.remembered=true
	check("remembered enemy never treated as live threat",Retreat.orders(records,[1],[]).size()==1)
	var dead=base.duplicate();dead.alive=false
	check("dead home excluded",Retreat.orders({1:unit,2:dead},[1],[]).is_empty())
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
	g._test_reset([{"food":500,"wood":500,"stone":100,"iron":100},{"food":150,"wood":200,"stone":100,"iron":0}]);g.set_process(false);await process_frame
	var home=g._first(0,"town_center");var soldier=g._spawn("spearman",0,home.pos+Vector3(16,0,0));soldier.hp-=10
	g._update_vision();g._select([soldier.id]);g._update_hud()
	check("injured selection exposes action",is_instance_valid(g.wounded_retreat_button) and not g.wounded_retreat_button.disabled)
	var before=soldier.hp;g._retreat_wounded()
	check("explicit action submits ordinary marked order",g.commands.size()==1 and g.commands[0].type=="order" and g.commands[0].wounded_retreat)
	g._retreat_wounded();check("rapid tap protected",g.commands.size()==1)
	g._execute(g.commands.pop_front())
	check("ordinary movement without instant healing",soldier.state=="move" and soldier.hp==before)
	var stale=Retreat.orders(g.faction_views[0].records(),[soldier.id],[])[0];stale.type="order";stale.team=0
	soldier.hp=soldier.max_hp;soldier.state="idle";soldier.dest=soldier.pos;var old_dest=soldier.dest
	g._execute(stale)
	check("healed-before-execution order rejected",soldier.dest==old_dest and soldier.state=="idle" and soldier.hp==soldier.max_hp)
	g._update_vision();g._update_hud()
	check("fully healed selection removes action",not is_instance_valid(g.wounded_retreat_button))
	soldier.hp-=10;g._update_vision();home.alive=false;g._execute(stale)
	check("destroyed home at execution cannot redirect unit",soldier.dest==old_dest and soldier.state=="idle")
	home.alive=true
	check("no resource minting",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"wounded_retreat_contract","checks":checks,"failed":failed,"scope":"Controlled selection/order contract, not guaranteed path arrival or physical phone acceptance"}))
	g.queue_free();quit(1 if failed else 0)
