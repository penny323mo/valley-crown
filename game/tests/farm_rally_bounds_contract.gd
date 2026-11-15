extends SceneTree
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	# Controlled registered farms, not a natural expansion or path test.
	var anchor=g._spawn("farm",0,Vector3.ZERO,true)
	var worker=g._first(0,"villager")
	g.economy.assign_farm("bounds-anchor",worker.id,anchor.id)
	var far=g._spawn("farm",0,Vector3(8.01,0,0),true)
	# Spawn snaps odd footprints; explicitly set the intended relative boundary.
	far.pos=anchor.pos+Vector3(8.01,0,0)
	g._update_vision(false);g._publish_faction_views()
	check("outside eight-unit cluster excluded",g._farm_rally_destination(anchor,0).is_empty())
	far.pos=anchor.pos+Vector3(8,0,0);g._publish_faction_views()
	check("exact eight-unit boundary eligible",g._farm_rally_destination(anchor,0).get("id",-1)==far.id)
	var near=g._spawn("farm",0,Vector3(4,0,0),true)
	var equal=g._spawn("farm",0,Vector3(-4,0,0),true)
	g._update_vision(false);g._publish_faction_views()
	check("nearest farm and stable lower ID tie break",g._farm_rally_destination(anchor,0).get("id",-1)==near.id)
	g.commands.append({"type":"order","team":0,"farm_gather":true,"target":near.id})
	check("pending same-team destination skipped",g._farm_rally_destination(anchor,0).get("id",-1)==equal.id)
	g.commands.clear()
	g.commands.append({"type":"order","team":1,"farm_gather":true,"target":near.id})
	check("other-team command does not reserve our farm",g._farm_rally_destination(anchor,0).get("id",-1)==near.id)
	g.commands.clear()
	g._kill(near);g._kill(equal);far.built=false;g._update_vision(false);g._publish_faction_views()
	check("dead and unfinished farms excluded",g._farm_rally_destination(anchor,0).is_empty())
	far.built=true;far.team=1;g._publish_faction_views()
	check("enemy farm excluded even if observed",g._farm_rally_destination(anchor,0).is_empty())
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"farm_rally_bounds","checks":checks,"failed":failed,"scope":"controlled records and ownership boundaries, no actual travel"}));g.queue_free();quit(1 if failed else 0)
