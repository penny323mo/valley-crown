extends SceneTree
## Synthetic geometry/races through real preview, confirmation and authority.
## Prepare only locally. Run under the reviewed CI resource supervisor.
const Rules=preload("res://scripts/rules.gd")
const SITE=Vector3(12,0,12)
const FOG="先派村民探索建築範圍"
var g
var checks=[]
func _initialize(): call_deferred("run")
func check(label,ok,detail={}):
	checks.append({"name":label,"pass":bool(ok),"detail":detail})
	print(("PASS " if ok else "FAIL ")+label+" "+JSON.stringify(detail))
func reset(full=true):
	g._cancel_mode(); g._test_reset()
	for e in g.entities:
		if e.category=="unit": g._set_stance(e,"STOP")
	if full:
		for team in 2: g.visible_cells[team].fill(1)
		g._refresh_work_memory(); g._publish_faction_views()
func authority():
	return {"ledger":g.economy.snapshot(),"economy_sequence":g.economy_sequence,"entities":g.entities.size(),"next_id":g.next_id,"navigation_version":g.navigation_version,"footprints":g.footprints.duplicate(true),"population":[g._population(0),g._population(1)],"completed":g.completed_builds.duplicate()}
func preview(point=SITE):
	var builder=g._first(0,"villager")
	g._publish_faction_views(); g._select([builder.id]); g._start_build("house")
	g.pointer_world=point; g.build_preview_held=true; g._update_ghost(); g._update_hud()
	return builder
func alter(kind):
	if kind=="unit": g._first(1,"scout").pos=SITE+Vector3(0.1,0,0.1)
	elif kind=="fog":
		var cell=g._occupied_cells({"kind":"house","pos":SITE})[0]
		g.visible_cells[0][cell.y*Rules.MAP_SIZE+cell.x]=0
func preview_race(kind,at_execution):
	reset(); var builder=preview()
	var label=("execution-" if at_execution else "confirmation-")+kind
	check(label+"-begins-green-and-unpaid",g.placement_ok and not g.build_confirm.disabled and g.commands.is_empty() and g.stocks[0].wood==200)
	if at_execution:
		g._confirm_build()
		check(label+"-valid-confirm-queues-once",g.commands.size()==1 and g.stocks[0].wood==200)
	alter(kind)
	var before=authority()
	var reason=g._placement_reason("house",SITE,0,builder.id)
	if at_execution:
		# Execute the actual confirmed payload. This deliberately stops before
		# movement/vision refresh, making the precise authority race observable.
		if not g.commands.is_empty(): g._execute(g.commands.pop_front())
	else: g._confirm_build()
	check(label+"-latest-state-refused",reason==("地點有單位" if kind=="unit" else FOG),{"reason":reason})
	check(label+"-no-debit-site-or-navigation-mutation",authority()==before and g.commands.is_empty())
	if not at_execution: check(label+"-held-intent-not-silently-committed",g.build_mode=="house" and g.build_preview_held)
func sequential_last_exit():
	reset(); var builder=g._first(0,"villager")
	var producer=g._spawn("barracks",0,Vector3(20.5,0,20.5))
	# Actual neutral resource blockers, not manual edits to the known grid.
	# Two distinct 2-cell exit groups remain. Either house alone is legal.
	var exits=[Vector2i(62,58),Vector2i(62,59),Vector2i(62,61),Vector2i(62,62)]
	for cell in g._perimeter_cells(producer):
		if cell not in exits: g._spawn("pine",-1,g._point(cell))
	g._navigation_rebuild(); g._refresh_work_memory(); g._publish_faction_views()
	var first=Vector3(23,0,19); var second=Vector3(23,0,22)
	check("sequential-both-sites-individually-legal",g._placement_reason("house",first,0,builder.id).is_empty() and g._placement_reason("house",second,0,builder.id).is_empty())
	var before=authority(); var tick=g.tick_count
	g._submit("build",{"kind":"house","position":first,"builder":builder.id},0)
	g._submit("build",{"kind":"house","position":second,"builder":builder.id},0)
	check("sequential-two-intents-same-batch",g.commands.size()==2)
	g._tick(Rules.TICK)
	check("sequential-only-first-commits",g.tick_count==tick+1 and g._count(0,"house")==1 and g.stocks[0].wood==150 and g.entities.size()==before.entities+1 and g.next_id==before.next_id+1 and g.navigation_version==before.navigation_version+1 and g.economy.audit().ok)
	# Restore just the test's synthetic observation, then prove a repeat reject
	# also has no additional cost/footprint effect. No extra simulation tick.
	g.visible_cells[0].fill(1); g._refresh_work_memory(); g._publish_faction_views()
	var second_reason=g._placement_reason("house",second,0,builder.id)
	check("sequential-second-is-last-exit-refusal",second_reason=="不可阻住生產建築最後出口",{"reason":second_reason})
	before=authority()
	var rejected=g._place_building("house",second,builder.id,0)
	check("sequential-repeat-last-exit-zero-debit",rejected.is_empty() and authority()==before)
func hidden_producer_case(variant):
	reset(false)
	g.visible_cells[0].fill(0)
	var footprint=g._occupied_cells({"kind":"house","pos":SITE})
	for cell in g._placement_visibility_cells(footprint): g.visible_cells[0][cell.y*Rules.MAP_SIZE+cell.x]=1
	var enemy={}
	if variant!="absent":
		enemy=g._spawn("barracks",1,Vector3(30.5,0,-30.5),variant!="unfinished")
		if variant=="dead": enemy.alive=false
		elif variant=="moved": enemy.pos=Vector3(32.5,0,-32.5)
		elif variant=="blocked":
			for cell in g._perimeter_cells(enemy): g._spawn("pine",-1,g._point(cell))
	g._navigation_rebuild(); g._refresh_work_memory(); g._publish_faction_views()
	var builder=preview()
	var before=authority()
	var reason=g._placement_reason("house",SITE,0,builder.id)
	var result={"view":g.faction_views[0].records(),"visible":g.visible_cells[0].duplicate(),"reason":reason,"green":g.placement_ok,"disabled":g.build_confirm.disabled,"color":g.ghost.get_child(0).material_override.albedo_color,"bank":g.economy.bank_milli(0)}
	check("hidden-producer-"+variant+"-unobserved",enemy.is_empty() or (not g._visible_to(enemy,0) and g.faction_views[0].get_record(enemy.id).is_empty()))
	check("hidden-producer-"+variant+"-preview-pure",authority()==before and reason.is_empty() and g.placement_ok and not g.build_confirm.disabled)
	return result
func run():
	g=load("res://main.tscn").instantiate(); root.add_child(g); g.test_mode=true; g.set_process(false)
	for kind in ["unit","fog"]:
		preview_race(kind,false); preview_race(kind,true)
	sequential_last_exit()
	var reference=hidden_producer_case("absent")
	for variant in ["living","unfinished","blocked","dead","moved"]:
		check("hidden-producer-"+variant+"-noninterference",hidden_producer_case(variant)==reference)
	var failed=checks.filter(func(row): return not row.pass).size()
	var report={"build":Rules.BUILD_ID,"passed":checks.size()-failed,"failed":failed,"checks":checks,"scope":"Synthetic placement race, atomicity and hidden-producer negative fixtures; no phone/browser/visual acceptance."}
	print("MAP80_PLACEMENT_RACES "+JSON.stringify(report))
	if not OS.get_cmdline_user_args().is_empty(): FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(1 if failed else 0)
