extends SceneTree
## New-contract checks. Run in guarded CI after import; NOT a visual/phone pass.
const Rules=preload("res://scripts/rules.gd")
const Routes=preload("res://scripts/map_routes.gd")
const Bounded=preload("res://scripts/bounded_grid_pathfinder.gd")
const Memory=preload("res://scripts/faction_work_memory.gd")
const View=preload("res://scripts/faction_view.gd")
var g
var checks=[]
var samples={}
func _initialize(): call_deferred("run")
func check(label,ok,detail={}):
	checks.append({"name":label,"pass":bool(ok),"detail":detail})
	print(("PASS " if ok else "FAIL ")+label+" "+JSON.stringify(detail))
func reset(full_visibility=false):
	g._cancel_mode(); g._test_reset()
	for e in g.entities:
		if e.category=="unit": g._set_stance(e,"STOP")
	if full_visibility:
		for team in 2: g.visible_cells[team].fill(1)
		g._refresh_work_memory(); g._publish_faction_views()
func bank(): return g.economy.bank_milli(0).duplicate(true)
func occupied_snapshot():
	return {"bank":bank(),"size":g.entities.size(),"next_id":g.next_id,"nav":g.navigation_version}
func world_anchor(x,y,width):
	return Vector3(x-Rules.MAP_HALF+(0.5 if width%2 else 0),0,y-Rules.MAP_HALF+(0.5 if width%2 else 0))
func sweep(label):
	var builder=g._first(0,"villager")
	# Independent source-model oracle: opening128/66, full-visible4956/4605.
	# The oracle never derives eligibility from _placement_reason's verdict.
	var expected_by_width={2:128,3:66} if label=="opening" else {2:4956,3:4605}
	var known_reasons=["","地圖邊界","需要地點及周邊目前可見","與建築或資源重疊","地點有單位","需要留有施工通道","不可阻住生產建築最後出口"]
	for kind in ["house","barracks","range","storehouse"]:
		var width=Rules.FOOTPRINT[kind]; var reasons={}; var legal_count=0; var unknown_reasons={}
		for y in Rules.MAP_SIZE:
			for x in Rules.MAP_SIZE:
				var p=world_anchor(x,y,width)
				var reason=g._placement_reason(kind,p,0,builder.id)
				reasons[reason]=reasons.get(reason,0)+1
				if reason.is_empty(): legal_count+=1
				if reason not in known_reasons: unknown_reasons[reason]=unknown_reasons.get(reason,0)+1
		var expected=expected_by_width[width]
		check(label+"-"+kind+"-independent-legal-count",legal_count==expected,{"actual":legal_count,"expected":expected,"reasons":reasons})
		check(label+"-"+kind+"-no-unknown-rejection",unknown_reasons.is_empty(),unknown_reasons)
		samples[label+"-"+kind]={"accepted":legal_count,"expected":expected,"reasons":reasons}
func run():
	g=load("res://main.tscn").instantiate(); root.add_child(g); g.test_mode=true; g.set_process(false)
	reset()
	check("map-regions-and-fog-size",g.navigation.region.size==Vector2i(80,80) and g.work_memory[0].grid.region.size==Vector2i(80,80) and g.visible_cells[0].size()==6400 and g.fog.multimesh.instance_count==6400)
	var home=g._first(0,"town_center"); var enemy=g._first(1,"town_center")
	check("separated-starts",home.pos==Routes.home(0) and enemy.pos==Routes.home(1) and home.pos.distance_to(enemy.pos)>69)
	check("opening-camera-at-home",g.camera_focus==home.pos)
	var hidden=true
	for e in g.entities:
		if e.team==1: hidden=hidden and not g._visible_to(e,0) and g.faction_views[0].get_record(e.id).is_empty()
	check("opening-enemy-unobserved",hidden)
	var units=0; var trees=0; var berries=0; var minerals={"stone":0,"iron":0}; var local=[{"wood":0,"food":0},{"wood":0,"food":0}]
	for e in g.entities:
		if e.category=="unit": units+=1
		elif e.category=="resource":
			if e.kind=="berry": berries+=1
			elif e.kind in ["pine","oak"]: trees+=1
			elif minerals.has(e.kind): minerals[e.kind]+=1
			for team in 2:
				if e.kind in ["pine","oak","berry"] and e.pos.distance_to(Routes.home(team))<13:
					local[team]["food" if e.kind=="berry" else "wood"]+=int(e.hp)
	check("finite-resource-counts",units==12 and trees==40 and berries==24,{"units":units,"trees":trees,"berries":berries})
	check("v1-mineral-counts-added",minerals=={"stone":12,"iron":12},minerals)
	check("home-resource-quotas-preserved",local[0]=={"wood":2100,"food":1200} and local[0]==local[1],local)
	var cell_ok=true
	for c in [Vector2i(0,0),Vector2i(2,2),Vector2i(40,40),Vector2i(77,77),Vector2i(79,79)]: cell_ok=cell_ok and g._cell(g._point(c))==c
	check("coordinate-round-trip-full-new-map",cell_ok)
	g.camera_focus=Vector3(999,0,-999); g._camera_update()
	check("camera-clamp-expanded-world",g.camera_focus==Vector3(35,0,-35))
	g.camera_focus=Routes.home(0); g._camera_update()
	var click=InputEventMouseButton.new(); click.pressed=true; click.button_index=MOUSE_BUTTON_LEFT
	click.position=g.minimap.size-Vector2(9,9); g.minimap._gui_input(click)
	check("minimap-far-corner-target",g.camera_focus==Vector3(35,0,35))
	g.camera_focus=Routes.home(0); g._camera_update()
	sweep("opening")
	reset(true); sweep("full-current-visibility")
	var builder=g._first(0,"villager")
	# Road-positive and road-negative sites are both legal. Exhaustive sweeps
	# above also prove plots are not a hidden whitelist.
	var road_legal=false; var offroad_legal=false
	for y in range(10,70):
		for x in range(10,70):
			var p=world_anchor(x,y,3)
			if not g._placement_reason("barracks",p,0,builder.id).is_empty(): continue
			var overlaps=false
			for cell in g._occupied_cells({"kind":"barracks","pos":p}): overlaps=overlaps or g.ground_trails.has(cell)
			road_legal=road_legal or overlaps; offroad_legal=offroad_legal or not overlaps
	check("road-and-offroad-producers-legal",road_legal and offroad_legal)
	# Visible occupied geometry rejects before payment.
	for target_kind in ["town_center","pine","berry"]:
		var target={}
		for e in g.entities:
			if e.kind==target_kind: target=e; break
		var before=occupied_snapshot()
		var site=g._place_building("house",target.pos,builder.id,0)
		check("reject-"+target_kind+"-without-debit",site.is_empty() and occupied_snapshot()==before)
	var unit=g._first(1,"scout"); unit.pos=Vector3(10.2,0,10.5)
	var before=occupied_snapshot()
	check("unit-disk-overlap-rejected",g._place_building("house",Vector3(10,0,10),builder.id,0).is_empty() and occupied_snapshot()==before)
	# Fog safety: changing an unseen occupant cannot change refusal or debit.
	g.visible_cells[0].fill(0); var fog_results=[]
	for point in [Vector3(10,0,10),Vector3(30,0,30)]:
		unit.pos=point; before=occupied_snapshot()
		fog_results.append(g._placement_reason("house",Vector3(10,0,10),0,builder.id))
		check("fog-no-debit-"+str(point),g._place_building("house",Vector3(10,0,10),builder.id,0).is_empty() and occupied_snapshot()==before)
	check("fog-response-independent-of-hidden-occupancy",fog_results[0]=="需要地點及周邊目前可見" and fog_results[0]==fog_results[1])
	# Geometry-only local exit guard. Synthetic known blockers do not assert
	# global connectivity and do not grant enemy knowledge.
	reset(true); builder=g._first(0,"villager")
	var producer=g._spawn("barracks",0,Vector3(20.5,0,20.5)); g._navigation_rebuild()
	var only_exit=Vector2i(62,60)
	for cell in g._perimeter_cells(producer): g.work_memory[0].grid.set_point_solid(cell,cell!=only_exit)
	check("last-owned-producer-exit-protected",g._placement_reason("house",Vector3(23,0,20),0,builder.id)=="不可阻住生產建築最後出口")
	reset(true); builder=g._first(0,"villager")
	var site_point=Vector3(12,0,12); var mock={"kind":"house","pos":site_point}
	for cell in g._perimeter_cells(mock): g.work_memory[0].grid.set_point_solid(cell)
	check("fully-enclosed-site-needs-entrance",g._placement_reason("house",site_point,0,builder.id)=="需要留有施工通道")
	# Legitimate normal command path, natural movement and paid construction.
	reset(); builder=g._first(0,"villager")
	var chosen=Vector3.INF
	for p in Routes.build_plots(0,2):
		if g._placement_reason("house",p,0,builder.id).is_empty(): chosen=p; break
	check("opening-real-build-site-found",chosen!=Vector3.INF)
	if chosen!=Vector3.INF:
		var start=builder.pos; var old_bank=bank()
		g._submit("build",{"kind":"house","position":chosen,"builder":builder.id},0)
		g._test_advance(45)
		var house=g._first(0,"house")
		check("worker-walks-to-site-and-completes",not house.is_empty() and house.built and builder.pos.distance_to(start)>0.5,{"position":builder.pos,"site":chosen})
		check("paid-build-conservation",bank().wood==old_bank.wood-50000 and g.economy.audit().ok)
	# Preserve distant-route budgets; no A* ceiling was raised for map size.
	reset(true)
	var path=Bounded.search(g.navigation,Vector2i(19,62),Vector2i(61,18))
	check("cross-map-path-within-existing-budget",path.status==Bounded.FOUND and path.expanded<=4096,path)
	for y in range(2,41): g.navigation.set_point_solid(Vector2i(40,y))
	var alternate=Bounded.search(g.navigation,Vector2i(19,62),Vector2i(61,18))
	check("alternate-macro-route",alternate.status==Bounded.FOUND and alternate.expanded<=4096,alternate)
	# Sparse memory updates release old cells, retain unseen cells, and keep
	# fixed edges solid on the enlarged grid.
	var memory=Memory.new(); var observed={7:{"id":7,"category":"resource","alive":true,"cells":[Vector2i(70,70)]}}
	memory.observe(observed,{}, {},1)
	check("memory-upper-map-obstacle",memory.grid.is_point_solid(Vector2i(70,70)))
	memory.observe({}, {}, {},2)
	check("memory-unseen-obstacle-retained",memory.grid.is_point_solid(Vector2i(70,70)))
	observed[7].alive=false; memory.observe(observed,{}, {},3)
	check("memory-observed-death-releases-cell",not memory.grid.is_point_solid(Vector2i(70,70)) and memory.grid.is_point_solid(Vector2i(79,79)))
	memory.observe({}, {8:{"id":8}}, {Vector2i(65,66):true},4)
	memory.observe({}, {}, {},5)
	check("memory-owned-demolition-releases-cell",not memory.grid.is_point_solid(Vector2i(65,66)))
	var view=View.new(); var visible=PackedByteArray(); visible.resize(6400); visible.fill(0)
	var observed_record={9:{"pos":Vector3(30.5,0,30.5),"category":"building","owned":false}}
	view.publish(observed_record,visible,1); view.publish({},visible,2)
	check("view-remembers-far-map-building",view.get_record(9).get("remembered",false))
	visible[70*80+70]=1; view.publish({},visible,3)
	check("view-retires-observed-empty-far-map",view.get_record(9).is_empty())
	var failed=0
	for row in checks:
		if not row.pass: failed+=1
	print("MAP80_REPORT "+JSON.stringify({"build":Rules.BUILD_ID,"map":Rules.MAP_VERSION,"passed":checks.size()-failed,"failed":failed,"checks":checks,"samples":samples,"not_run":["phone","browser","visual acceptance","long-match balance"]}))
	if not OS.get_cmdline_user_args().is_empty(): FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"build":Rules.BUILD_ID,"passed":checks.size()-failed,"failed":failed,"checks":checks,"samples":samples},"  "))
	quit(1 if failed else 0)
