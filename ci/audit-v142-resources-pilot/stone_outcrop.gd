extends RefCounted
## Authored flattened limestone form; no gameplay, atlas, shadow or cache state.
const FULL_HEIGHT := 0.610226
const RIDGES := [
	[Vector2(-0.99,-0.53),Vector2(-0.22,-0.98),Vector2(0.85,-0.80),Vector2(1.00,0.22),Vector2(0.40,0.94),Vector2(-0.67,0.67)],
	[Vector2(-0.87,-0.79),Vector2(0.17,-1.00),Vector2(0.95,-0.41),Vector2(0.75,0.74),Vector2(-0.19,0.98),Vector2(-0.97,0.39)],
	[Vector2(-1.00,-0.36),Vector2(-0.41,-0.96),Vector2(0.75,-0.94),Vector2(0.98,0.47),Vector2(0.27,0.85),Vector2(-0.79,0.75)]
]
static func _tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,tint:Color)->void:
	st.set_color(tint);st.add_vertex(a);st.add_vertex(b);st.add_vertex(c)

static func _piece(st:SurfaceTool,loop:Array,center:Vector2,width:Vector2,h:float,angle:float,phase:float,color:Color,scale_factor:float)->void:
	var rows=[]
	for level in 4:
		var row=[]
		for idx in loop.size():
			var q:Vector2=loop[idx]
			var xy=(q*width).rotated(angle)*[0.94,1.0,0.92,0.67][level]
			var offset=Vector2(0.030*phase,-0.035)*pow(level/3.0,1.5)
			var y:float=[0.0,0.22,0.48,0.80][level]
			if level>0:y+=(q.y+0.35*q.x)*0.09
			row.append(Vector3(center.x+xy.x+offset.x,y*h,center.y+xy.y+offset.y)*scale_factor)
		rows.append(row)
	for level in 3:
		for i in loop.size():
			var n=(i+1)%loop.size()
			var tint=color.darkened(0.13-0.045*level+0.03*(i%2))
			# Stratified faces stay broad and the visual seam is actual geometry.
			_tri(st,rows[level][i],rows[level+1][i],rows[level][n],tint)
			_tri(st,rows[level][n],rows[level+1][i],rows[level+1][n],tint.lightened(0.025))
	var peak=Vector3(center.x+0.06*phase,h,center.y-0.082)*scale_factor
	for i in loop.size():
		_tri(st,rows[3][i],peak,rows[3][(i+1)%loop.size()],color.lightened(0.07+0.02*(i%3)))

static func make_mesh(stage:int,variant:int)->ArrayMesh:
	var kind=posmod(variant,3)
	var amount:float=[1.0,0.83,0.66,0.46][clampi(stage,0,3)]
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var angle:float=[0.27,-0.46,0.80][kind]
	var tone:Color=[Color("d1ccba"),Color("d6c8b2"),Color("c6cdc5")][kind]
	var center=Vector2(-0.035,-0.05).rotated(angle)
	_piece(st,RIDGES[kind],center,Vector2(0.42,0.32),FULL_HEIGHT,angle,1.0,tone,amount)
	_piece(st,RIDGES[(kind+1)%3],Vector2(0.21,0.17).rotated(angle),Vector2(0.28,0.24),0.39,angle-0.32,-1.0,tone.darkened(0.09),amount)
	if stage<3:
		_piece(st,RIDGES[(kind+2)%3],Vector2(-0.27,0.15).rotated(angle),Vector2(0.17,0.14),0.20,angle+0.10,1.0,tone.darkened(0.12),amount)
	st.generate_normals()
	var mat=StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo=true;mat.vertex_color_is_srgb=true;mat.roughness=0.97;mat.metallic_specular=0.10;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st.commit()
