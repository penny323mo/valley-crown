extends RefCounted
## Post-capture only. Synchronous synthetic presentation records; no authority/camera writes.
var checks: Array=[]
func check(value: bool, name: String): checks.append({"name":name,"pass":value})
func extent(camera, mesh_node, transform: Transform3D) -> Dictionary:
	var box: AABB=mesh_node.mesh.get_aabb()
	var lo=Vector2(INF,INF); var hi=Vector2(-INF,-INF)
	for x in [0,1]:
		for y in [0,1]:
			for z in [0,1]:
				var point=box.position+box.size*Vector3(x,y,z)
				var pixel: Vector2=camera.unproject_position(transform*point)
				lo=lo.min(pixel);hi=hi.max(pixel)
	return {"width":hi.x-lo.x,"center_x":(hi.x+lo.x)*.5,"height":hi.y-lo.y}
func run(game, subject_id: int, opponent_id: int) -> Dictionary:
	var camera_before: Transform3D=game.camera.global_transform
	var size_before: float=game.camera.size
	var current=game.faction_views[0].current
	var selected: Array=game.selected.duplicate()
	var paused: bool=game.paused
	var authority: Dictionary={}
	for e in game.entities: authority[e.id]=[e.hp,e.alive,e.pos]
	check(game.pending_visual_deaths.is_empty(),"no pending deaths before synthetic presentation checks")
	var actor: Dictionary=game._get_entity(subject_id)
	var enemy: Dictionary=game._get_entity(opponent_id)
	check(game.presentation_nodes.has(opponent_id),"observed opponent proxy exists")
	var proxy: Dictionary=game.presentation_nodes[opponent_id]
	check(actor.bar.get_parent()==actor.node and actor.body.get_parent()==actor.node,"owned bar/body siblings")
	check(proxy.bar.get_parent()==proxy.node and proxy.body.get_parent()==proxy.node,"opponent bar/body siblings")
	check(actor.node.rotation.is_zero_approx() and proxy.node.rotation.is_zero_approx(),"bar parent yaw independent of body facing")
	check(actor.node.scale==Vector3.ONE and proxy.node.scale==Vector3.ONE,"bar parent unit scale matches baseline reconstruction")
	var measurements: Array=[]
	for bar in [actor.bar,proxy.bar]:
		var bg=bar.get_child(0);var fill=bar.get_child(1)
		check(fill.position==Vector3(0,.05,0),"centered fill pivot retained")
		var baseline_bar=Transform3D(Basis.IDENTITY,bar.global_position)
		var actual_background=extent(game.camera,bg,bar.global_transform*bg.transform)
		var baseline_background=extent(game.camera,bg,baseline_bar*bg.transform)
		check(absf(actual_background.width-baseline_background.width)<.002,"background native projected width preserved")
		var left: Vector2=game.camera.unproject_position(bar.global_transform*Vector3(-.5,0,0))
		var right: Vector2=game.camera.unproject_position(bar.global_transform*Vector3(.5,0,0))
		check(absf(left.y-right.y)<.002,"native unit bar centerline horizontal")
		for hp in [0.0,.6,1.0,30.0,60.0]:
			var record={"hp":hp,"max_hp":60.0,"category":"unit"}
			var fraction=maxf(.01,hp/60.0)
			var actual_local=fill.transform
			actual_local.basis=Basis.IDENTITY.scaled(Vector3(game._health_bar_fill_scale(record,bar),1,1))
			var baseline_local=fill.transform
			baseline_local.basis=Basis.IDENTITY.scaled(Vector3(fraction,1,1))
			var a=extent(game.camera,fill,bar.global_transform*actual_local)
			var b=extent(game.camera,fill,baseline_bar*baseline_local)
			check(absf(a.width-b.width)<.002 and absf(a.center_x-b.center_x)<.002,"native centered full-box extent matches baseline at HP "+str(hp))
			measurements.append({"owned":bar==actor.bar,"hp":hp,"max_hp":60,"actual":a,"baseline":b})
	# No frame advances occur during these disclosed synthetic observation/selection cases.
	# HP 0 here verifies inherited 1% presentation clamp, not a living zero-HP gameplay state.
	game.paused=true
	var cases=[
		{"name":"owned full unselected","own":60,"enemy":60,"select":false,"hidden":false,"own_visible":false,"enemy_visible":false},
		{"name":"owned full selected","own":60,"enemy":60,"select":true,"hidden":false,"own_visible":true,"enemy_visible":false},
		{"name":"both damaged","own":30,"enemy":30,"select":false,"hidden":false,"own_visible":true,"enemy_visible":true},
		{"name":"one percent","own":.6,"enemy":.6,"select":false,"hidden":false,"own_visible":true,"enemy_visible":true},
		{"name":"zero clamp diagnostic","own":0,"enemy":0,"select":false,"hidden":false,"own_visible":true,"enemy_visible":true},
		{"name":"hidden opponent","own":60,"enemy":30,"select":false,"hidden":true,"own_visible":false,"enemy_visible":false}]
	for item in cases:
		var records: Dictionary=current.duplicate(true)
		records[subject_id].hp=item.own;records[subject_id].max_hp=60
		records[opponent_id].hp=item.enemy;records[opponent_id].max_hp=60
		if item.hidden: records.erase(opponent_id)
		game.faction_views[0].current=game.faction_views[0].freeze(records)
		game.selected=[subject_id] if item.select else []
		game._update_visuals(0.0)
		check(actor.bar.is_visible_in_tree()==item.own_visible,item.name+" owned visibility")
		check(is_equal_approx(actor.bar_fill.scale.x,game._health_bar_fill_scale(records[subject_id],actor.bar)),item.name+" owned observed HP used")
		check(proxy.bar.is_visible_in_tree()==item.enemy_visible,item.name+" enemy visibility")
		check(not enemy.node.visible and not enemy.bar.visible,item.name+" enemy authority presentation stays hidden")
		if not item.hidden:
			check(is_equal_approx(proxy.fill.scale.x,game._health_bar_fill_scale(records[opponent_id],proxy.bar)),item.name+" observed HP used")
	# Remembered-building bar gate uses an isolated copy of an existing own building.
	var building: Dictionary={}
	for e in game.entities:
		if current.has(e.id) and current[e.id].owned and e.category=="building":building=e;break
	check(not building.is_empty(),"owned building template available")
	if not building.is_empty():
		var node=Node3D.new();game.add_child(node)
		var body=building.body.duplicate();node.add_child(body)
		var bar=building.bar.duplicate();node.add_child(bar)
		check(bar.rotation.is_zero_approx() and bar.scale==Vector3.ONE,"building bar geometry unchanged")
		check(not game.presentation_nodes.has(building.id),"building temporary proxy key unused")
		game.presentation_nodes[building.id]={"node":node,"body":body,"bar":bar,"fill":bar.get_child(1),"remembered":true,"anim":building.anim}
		var records: Dictionary=current.duplicate(true)
		records[building.id].owned=false;records[building.id].remembered=true;records[building.id].hp=1
		game.faction_views[0].current=game.faction_views[0].freeze(records)
		game._update_visuals(0.0)
		check(not bar.is_visible_in_tree(),"remembered building health hidden")
		game.presentation_nodes.erase(building.id);node.free()
	game.faction_views[0].current=current;game.selected=selected;game.paused=paused
	game._update_visuals(0.0)
	for e in game.entities:check(authority[e.id]==[e.hp,e.alive,e.pos],"authority HP/alive/position unchanged "+str(e.id))
	check(game.camera.global_transform==camera_before and game.camera.size==size_before,"camera unchanged throughout probe")
	check(game.faction_views[0].current==current and game.selected==selected and game.paused==paused,"presentation inputs restored")
	var passed=true
	for row in checks:
		if not row["pass"]:passed=false
	return {"schema":"unitbar_native_probe_v1","passed":passed,"checks":checks,"measurements":measurements,"build":game.Rules.BUILD_ID,"visual_acceptance":false,"scope":"Post-capture synchronous native geometry and synthetic presentation-state contract. Not natural fog/gameplay, raster fill visibility, or artwork acceptance.","mutations":["Temporary observation current dictionaries and selected IDs after all four paired frames","Pause flag during synchronous zero-delta presenter updates","Temporary cloned building proxy; removed before return","Presenter reconcile can recreate an observed rig after hidden case; no later paired frames"],"camera_mutated":false,"authority_hp_mutated":false}
