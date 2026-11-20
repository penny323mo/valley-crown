extends RefCounted
# UNACCEPTED candidate: CC0 foliage normalized to existing resource envelope.
# Custom white-atlas green material and original attached fruit clusters.
# Every harvestable low-stock stage retains fruit; authority removes truly exhausted nodes.
const DONOR=preload('res://assets/diagnostic/bush_common/Bush_Common.gltf')
static var cached:ArrayMesh
static var stages:Dictionary={}
static func collect(node:Node, parent_transform:Transform3D, result:Array) -> void:
 var local=parent_transform*node.transform if node is Node3D else parent_transform
 if node is MeshInstance3D:result.append({'mesh':node.mesh,'transform':local})
 for child in node.get_children():collect(child,local,result)
static func make_mesh() -> ArrayMesh:
 if cached!=null:return cached
 var root=DONOR.instantiate();var meshes=[];collect(root,Transform3D.IDENTITY,meshes)
 assert(meshes.size()==1 and meshes[0].mesh.get_surface_count()==1)
 var arrays=meshes[0].mesh.surface_get_arrays(0)
 var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
 var transform:Transform3D=meshes[0].transform
 var low=Vector3(INF,INF,INF);var high=Vector3(-INF,-INF,-INF)
 for i in vertices.size():
  vertices[i]=transform*vertices[i];low=low.min(vertices[i]);high=high.max(vertices[i])
 var center=Vector3((low.x+high.x)*.5,low.y,(low.z+high.z)*.5)
 var radius=0.0
 for p in vertices:radius=maxf(radius,Vector2(p.x-center.x,p.z-center.z).length())
 var scale=minf(.54/radius,.76/(high.y-low.y))
 var normal_basis=transform.basis.inverse().transposed()
 for i in vertices.size():
  var point=(vertices[i]-center)*scale
  var azimuth=atan2(point.z,point.x)
  var radius_xz=Vector2(point.x,point.z).length()
  var crown=smoothstep(.10,.32,point.y)*(1.0-smoothstep(.62,.76,point.y))
  var lobes=0.82+0.30*cos(3.0*azimuth+.31)+0.15*sin(2.0*azimuth-.42)
  var radial=minf(lobes*crown+1.0-crown,.55/maxf(.001,radius_xz))
  point.x*=radial;point.z*=radial
  vertices[i]=point;normals[i]=(normal_basis*normals[i]).normalized()
 arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
 cached=ArrayMesh.new();cached.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var material=meshes[0].mesh.surface_get_material(0).duplicate()
 # Retain imported alpha-scissor rather than switching to alpha blend/opaque.
 assert(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
 # Custom CC0 derivative material, NOT an official green variant. PNG unchanged.
 material.albedo_texture=preload('res://assets/diagnostic/bush_common/Leaves_TwistedTree.png')
 material.albedo_color=Color('788c42')
 cached.surface_set_material(0,material);root.free();return cached

static func tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,color:Color) -> void:
 st.set_color(color.srgb_to_linear());st.add_vertex(a);st.add_vertex(b);st.add_vertex(c)
static func stem(st:SurfaceTool,a:Vector3,b:Vector3) -> void:
 var axis=(b-a).normalized();var side=axis.cross(Vector3.UP).normalized();var other=axis.cross(side)
 for i in 5:
  var p=(side*cos(TAU*i/5.0)+other*sin(TAU*i/5.0))*.009
  var q=(side*cos(TAU*(i+1)/5.0)+other*sin(TAU*(i+1)/5.0))*.009
  tri(st,a+p,a+q,b+p,Color('70533a'));tri(st,a+q,b+q,b+p,Color('70533a'))
static func fruit(st:SurfaceTool,c:Vector3,r:float) -> void:
 for band in 4:
  var a=PI*band/4.0;var b=PI*(band+1)/4.0
  for i in 8:
   var u=TAU*i/8.0;var v=TAU*(i+1)/8.0
   var p0=c+Vector3(sin(a)*cos(u),cos(a),sin(a)*sin(u))*Vector3(r,r*1.12,r)
   var p1=c+Vector3(sin(b)*cos(u),cos(b),sin(b)*sin(u))*Vector3(r,r*1.12,r)
   var p2=c+Vector3(sin(a)*cos(v),cos(a),sin(a)*sin(v))*Vector3(r,r*1.12,r)
   var p3=c+Vector3(sin(b)*cos(v),cos(b),sin(b)*sin(v))*Vector3(r,r*1.12,r)
   if band>0:tri(st,p0,p1,p2,Color('bd313b'))
   if band<3:tri(st,p2,p1,p3,Color('de5146'))
static func resource_mesh(stage:int) -> ArrayMesh:
 assert(stage>=0 and stage<=3)
 if stages.has(stage):return stages[stage]
 var foliage=make_mesh();var mesh=ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,foliage.surface_get_arrays(0));mesh.surface_set_material(0,foliage.surface_get_material(0))
 if stage<=3:
  var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
  for cluster in range(maxi(1,3-stage)):
   var angle=TAU*cluster/3.0+.35
   var radial=Vector3(cos(angle),0,sin(angle));var tangent=Vector3(-sin(angle),0,cos(angle))
   var junction=radial*.411+Vector3(0,.53+cluster*.021,0)
   stem(st,radial*.21+Vector3(0,.60+cluster*.021,0),junction)
   var fruit_count=2 if stage==3 else 3
   for j in fruit_count:
    var center=junction+radial*.027+tangent*(j-(fruit_count-1)*.5)*.064+Vector3(0,-.051-(.057 if j==1 else 0),0)
    stem(st,junction,center+Vector3(0,.04,0));fruit(st,center,.064 if stage==3 else .077)
  st.generate_normals();var fruit_mesh=st.commit()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,fruit_mesh.surface_get_arrays(0))
  var mat=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=1;mesh.surface_set_material(1,mat)
 stages[stage]=mesh;return mesh
