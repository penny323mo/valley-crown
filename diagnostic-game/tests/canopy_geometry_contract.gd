extends SceneTree
# PREPARED ONLY. No full game _ready(), authority mutation, browser or render claim.
# Synthetic public observation records and tiny presentation triangle meshes isolate
# the actual GDScript picking branch. Run only after a separate resource gate.
var game
var camera:Camera3D
var checks=[]
var journal:FileAccess
func _initialize():call_deferred("run")
func check(name,ok,detail={}):
	var row={"name":name,"pass":bool(ok),"detail":detail};checks.append(row)
	print("CHECK ",JSON.stringify(row));journal.store_line(JSON.stringify(row));journal.flush()
func record(id,category="resource",position=Vector3.ZERO,team=-1):
	return {"id":id,"category":category,"kind":"pine" if category=="resource" else "villager","pos":position,"team":team,"owned":team==0,"remembered":false,"alive":true}
func publish(records):
	var visible={}
	for value in records:visible[value.id]=value
	game.faction_views[0].current=game.FactionView.freeze(visible)
func proxy(id,position=Vector3.ZERO,scale=Vector3.ONE):
	var node=Node3D.new();root.add_child(node);node.position=position
	var body=Node3D.new();node.add_child(body)
	var mesh=MeshInstance3D.new();body.add_child(mesh);mesh.scale=scale
	var resource=ArrayMesh.new();var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-2,0,0),Vector3(2,0,0),Vector3(0,4,0)])
	resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.mesh=resource
	game.presentation_nodes[id]={"node":node,"body":body}
	return mesh
func pick_at(world,allow_enemy=true):return game._pick(camera.unproject_position(world),allow_enemy)
func expect(name,world,wanted,allow_enemy=true):
	var observed=pick_at(world,allow_enemy)
	check(name,observed==wanted,{"expected":wanted,"observed":observed,"world":str(world)})
func run():
	var out=OS.get_cmdline_user_args()[0]
	journal=FileAccess.open(out+".progress.jsonl",FileAccess.WRITE)
	root.size=Vector2i(1170,2532);root.content_scale_factor=3.0
	# Do not add game to the tree: _ready and its world/simulation never run.
	game=load("res://scripts/game.gd").new();game.compact_ui=true
	camera=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=30;camera.position=Vector3(0,0,10);camera.look_at(Vector3.ZERO);camera.current=true;game.camera=camera
	var tree=record(7);var mesh=proxy(7);publish([tree]);await process_frame
	check("CSS-equivalent synthetic fixture",root.get_visible_rect().size.is_equal_approx(Vector2(390,844)))
	expect("Command ray hits upper canopy beyond legacy anchor",Vector3(0,3,0),7)
	expect("Command ray hits crown side",Vector3(0.4,3,0),7)
	expect("Selection path does not gain canopy region",Vector3(0,3,0),-1,false)
	expect("Blank corner inside broad-phase AABB is not a tree",Vector3(1.8,3.8,0),-1)
	expect("Empty ground outside geometry and anchor halo",Vector3(3.0,3.0,0),-1)
	expect("Legacy resource-anchor tolerance remains",Vector3(0,1,0),7,false)
	var px_per_unit=root.get_visible_rect().size.y/camera.size
	for offset in [0.0,12.0,13.0,24.0,33.9]:
		var worker=record(2,"unit",Vector3(offset/px_per_unit,2.4,0),0);publish([tree,worker])
		expect("Existing unit target retained at "+str(offset)+" CSS px",Vector3(0,3,0),2)
		expect("Ordinary selection retained at "+str(offset)+" CSS px",Vector3(0,3,0),2,false)
	publish([tree,record(2,"unit",Vector3(0,1.3,0),0)])
	expect("Rendered head offset retains legacy unit winner",Vector3(0,3,0),2)
	publish([tree,record(2,"unit",Vector3(0,2.0,0),0)])
	expect("Rendered torso offset retains legacy unit winner",Vector3(0,3,0),2)
	publish([tree,record(3,"unit",Vector3(0,2.4,0),1)])
	expect("Visible enemy anchor remains targetable",Vector3(0,3,0),3)
	expect("Selection excludes enemy and canopy branch",Vector3(0,3,0),-1,false)
	var near=record(8,"resource",Vector3(0,0,1));proxy(8,near.pos);publish([tree,near])
	expect("Foreground neighboring resource beats farther mesh",Vector3(0,3,0),8)
	publish([near,tree]);expect("Neighbor depth independent of iteration order",Vector3(0,3,0),8)
	game.presentation_nodes[8].node.position=Vector3.ZERO;near.pos=Vector3.ZERO
	for order in [[near,tree],[tree,near]]:
		publish(order);expect("Equal depth uses stable lower resource ID",Vector3(0,3,0),7)
	var remembered=tree.duplicate();remembered.remembered=true;publish([remembered])
	expect("Remembered resource never enters geometry",Vector3(0,3,0),-1)
	var dead=tree.duplicate();dead.alive=false;publish([dead])
	expect("Dead observed record never enters geometry",Vector3(0,3,0),-1)
	publish([]);expect("Hidden resource proxy without current record is ignored",Vector3(0,3,0),-1)
	publish([tree]);game.presentation_nodes[7].node.hide()
	expect("Invisible presentation proxy is not geometry",Vector3(0,3,0),-1)
	game.presentation_nodes[7].node.show()
	for scale in [Vector3.ONE*0.85,Vector3.ONE*1.05,Vector3(0.7,1.3,1.6)]:
		mesh.scale=scale;var point=mesh.global_transform*Vector3(0,3,0)
		expect("Actual presentation scale "+str(scale),point,7)
		var origin=camera.project_ray_origin(camera.unproject_position(point));var direction=camera.project_ray_normal(camera.unproject_position(point))
		check("World-distance ranking after inverse scale "+str(scale),absf(game._resource_ray_distance(tree,origin,direction)-origin.distance_squared_to(point))<0.001)
	mesh.scale=Vector3.ZERO
	expect("Singular mesh transform is rejected",Vector3(0,3,0),-1)
	check("Nonfinite input screen rejected",game._pick(Vector2(NAN,0))==-1)
	check("Mesh cache retains resource keys",not game.resource_pick_face_cache.is_empty() and game.resource_pick_face_cache.keys()[0] is Mesh)
	var failed=checks.filter(func(row):return not row.pass).size()
	var report={"build":game.Rules.BUILD_ID,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"checks":checks,"passed":checks.size()-failed,"failed":failed,"scope":"Synthetic native public-observation/presentation-mesh fixture only. No real tree pixels, browser, initial user flow, performance or physical-phone acceptance."}
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"  "));game.free()
	quit(0 if failed==0 else 1)
