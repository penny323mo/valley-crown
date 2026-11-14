extends SceneTree
const Routes=preload("res://scripts/order_routes.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var record={"id":1,"owned":true,"alive":true,"remembered":false,"category":"unit","state":"move","target":-1,"pos":Vector3.ZERO,"dest":Vector3(4,0,0)}
	var records={1:record}
	check("selected movement intent shown",Routes.routes(records,[1]).size()==1)
	check("unselected orders private",Routes.routes(records,[]).is_empty())
	check("duplicate selection bounded",Routes.routes(records,[1,1]).size()==1)
	record.owned=false;check("enemy orders excluded",Routes.routes(records,[1]).is_empty());record.owned=true
	record.remembered=true;check("remembered records excluded",Routes.routes(records,[1]).is_empty());record.remembered=false
	record.target=5;check("entity chase never reveals target",Routes.routes(records,[1]).is_empty());record.target=-1
	record.state="attack";check("attack routes excluded",Routes.routes(records,[1]).is_empty());record.state="move"
	record.dest=Vector3.INF;check("nonfinite rejected",Routes.routes(records,[1]).is_empty());record.dest=Vector3.ZERO
	check("arrival clears guide",Routes.routes(records,[1]).is_empty());record.dest=Vector3(4,0,0)
	record.path=PackedVector3Array([Vector3(99,0,99)])
	check("pathfinding geometry never copied",Routes.routes(records,[1])[0].destination==Vector3(4,0,0) and not Routes.routes(records,[1])[0].has("path"))
	var many={};var ids=[]
	for id in 30:
		var copy=record.duplicate(true);copy.id=id;many[id]=copy;ids.append(id)
	check("large selections limited to twelve guides",Routes.routes(many,ids).size()==12)
	var holder=Node3D.new();root.add_child(holder);var presenter=Routes.new();presenter.update(holder,records,[1],false)
	check("one instanced mesh allocated",holder.get_child_count()==1 and presenter.node.multimesh.instance_count==288)
	check("visible geometry bounded",presenter.node.multimesh.visible_instance_count>0 and presenter.node.multimesh.visible_instance_count<=24)
	check("depth tested geometry",not presenter.node.material_override.no_depth_test)
	var same=presenter.node;presenter.update(holder,records,[1],false);check("repeat update reuses mesh",presenter.node==same)
	presenter.update(holder,records,[],false);check("deselect hides guides",not presenter.node.visible)
	presenter.update(holder,records,[1],true);check("end frees guide",presenter.node==null)
	var rally={"id":2,"owned":true,"alive":true,"category":"building","built":true,"pos":Vector3.ZERO,"rally_mode":"move","rally_point":Vector3(6,0,0)}
	check("own movement rally shown",Routes.routes({2:rally},[2])[0].rally)
	rally.rally_mode="gather";check("resource rally excluded",Routes.routes({2:rally},[2]).is_empty())
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var unit=g._first(0,"scout");var bank=g.economy.bank_milli(0).duplicate();var hp=unit.hp
	# Controlled accepted own intent: presenter observes published values only.
	unit.state="move";unit.target=-1;unit.dest=unit.pos+Vector3(3,0,0);g.selected=[unit.id];g._publish_faction_views();g._update_visuals(0)
	check("game connects own intent presentation",is_instance_valid(g.order_routes.node) and g.order_routes.node.visible)
	check("guide cannot change hp or bank",unit.hp==hp and g.economy.bank_milli(0)==bank)
	g.selected=[];g._update_visuals(0);check("game selection removal hides guide",not g.order_routes.node.visible)
	g._test_reset();check("restart clears guide",g.order_routes.node==null)
	check("ledger conserved",g.economy.audit().ok)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"order_routes_contract","checks":checks,"failed":failed,"scope":"Native intent filtering and instanced geometry/lifecycle; controlled own move record, not route feasibility or browser visual acceptance"}))
	holder.queue_free();g.queue_free();quit(1 if failed else 0)
