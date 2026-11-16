extends RefCounted
## Straight intent guides, NOT pathfinding previews. Own movement/rally only.
const MAX_ROUTES=12
const DASHES=24
var node: MultiMeshInstance3D
static func routes(records: Dictionary,selected: Array) -> Array:
	var result=[];var ids=selected.duplicate();ids.sort();var seen={}
	for id in ids:
		if seen.has(id):continue
		seen[id]=true
		var record=records.get(id,{})
		if not record.get("owned",false) or not record.get("alive",false) or record.get("remembered",false):continue
		var destination=Vector3.INF;var rally=false
		if record.get("category","")=="unit" and record.get("state","")=="move" and record.get("target",-1)==-1:
			destination=record.get("dest",Vector3.INF)
		elif record.get("category","")=="building" and record.get("built",false) and record.get("rally_mode","")=="move":
			destination=record.get("rally_point",Vector3.INF);rally=true
		var origin=record.get("pos",Vector3.INF)
		if not origin is Vector3 or not destination is Vector3 or not origin.is_finite() or not destination.is_finite():continue
		if origin.distance_squared_to(destination)<0.16:continue
		result.append({"id":id,"origin":origin,"destination":destination,"rally":rally})
		if result.size()>=MAX_ROUTES:break
	return result
func clear():
	if is_instance_valid(node):node.visible=false;node.queue_free()
	node=null
func update(parent: Node3D,records: Dictionary,selected: Array,ended: bool):
	if ended:clear();return
	var plans=routes(records,selected)
	if plans.is_empty():
		if is_instance_valid(node):node.visible=false
		return
	if not is_instance_valid(node):
		node=MultiMeshInstance3D.new();node.name="SelectedOrderGuides"
		var batch=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_colors=true
		var dash=BoxMesh.new();dash.size=Vector3(0.07,0.025,0.35);batch.mesh=dash
		batch.instance_count=MAX_ROUTES*DASHES;node.multimesh=batch
		var material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.vertex_color_use_as_albedo=true;material.albedo_color=Color.WHITE;node.material_override=material
		parent.add_child(node)
	node.visible=true;var count=0
	for plan in plans:
		var start: Vector3=plan.origin;var finish: Vector3=plan.destination
		start.y=0.10;finish.y=0.10
		var direction=(finish-start).normalized()
		if direction.length_squared()<0.5:continue
		var distance=start.distance_to(finish);var amount=mini(DASHES,maxi(2,ceili(distance/0.7)))
		var basis=Basis.looking_at(direction,Vector3.UP)
		for index in amount:
			var point=start.lerp(finish,float(index+1)/amount)
			node.multimesh.set_instance_transform(count,Transform3D(basis,point))
			node.multimesh.set_instance_color(count,Color("91d6e8") if plan.rally else Color("e6c17a"));count+=1
	node.multimesh.visible_instance_count=count
