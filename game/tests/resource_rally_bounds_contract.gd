extends SceneTree
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var point=Vector3(0,0,-12)
	var scout=g._spawn("scout",0,point)
	var first=g._spawn("berry",-1,point+Vector3(3,0,0))
	var second=g._spawn("berry",-1,point+Vector3(-3,0,0))
	var wood=g._spawn("pine",-1,point+Vector3(1,0,0))
	g._update_vision(false);g._publish_faction_views()
	var plan={"rally_resource_type":"food","rally_point":point}
	check("same distance stable lower resource ID",g._resource_rally_replacement(plan,0).id==first.id)
	check("nearer wrong resource not selected",g._resource_rally_replacement(plan,0).id!=wood.id)
	g._kill(first);g._update_vision(false);g._publish_faction_views()
	check("dead candidate excluded",g._resource_rally_replacement(plan,0).id==second.id)
	# Isolate the boundary candidate from map-generated berry nodes.
	for entity in g.entities:
		if entity.alive and entity.category=="resource" and entity.kind=="berry" and entity.id!=second.id:g._kill(entity)
	second.pos=point+Vector3(8.01,0,0);scout.pos=second.pos
	g._update_vision(false);g._publish_faction_views()
	check("outside cluster excluded even if visible",g._resource_rally_replacement(plan,0).is_empty())
	second.pos=point+Vector3(8,0,0);g._update_vision(false);g._publish_faction_views()
	check("exact cluster boundary accepted",g._resource_rally_replacement(plan,0).id==second.id)
	plan.rally_resource_type="wood"
	check("wood intent stays wood",g._resource_rally_replacement(plan,0).id==wood.id)
	plan.rally_resource_type=""
	check("missing legacy type cannot invent intent",g._resource_rally_replacement(plan,0).is_empty())
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"resource_rally_bounds","checks":checks,"failed":failed}));g.queue_free();quit(1 if failed else 0)
